'use strict';
/**
 * scan_connections.js
 * Captura todo TCP por 20 segundos, registra cada conexão única
 * e avisa se encontrou os magic bytes do AION 2 (0x06 0x00 0x36).
 *
 * Uso: node src/scan_connections.js [--iface=\Device\NPF_XXXX]
 * Saída também em: logs/scan_<timestamp>.log
 */

const fs = require('fs');
const path = require('path');
const {Cap, decoders} = require('cap');

const MAGIC = Buffer.from([0x06, 0x00, 0x36]);
const DURATION = 20000; // ms

// ---- args ----
const args = process.argv.slice(2);
const ifaceArg =
  (args.find((a) => a.startsWith('--iface=')) || '').split('=')[1] || null;

// ---- log file ----
const logDir = path.join(__dirname, '..', '..', 'logs');
try {
  fs.mkdirSync(logDir, {recursive: true});
} catch (_) {}
const logPath = path.join(logDir, `scan_${Date.now()}.log`);
const logStream = fs.createWriteStream(logPath, {flags: 'a'});

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}`;
  console.log(line);
  logStream.write(line + '\n');
}

// ---- select interface ----
const devices = Cap.deviceList();
let device = ifaceArg;
if (!device) {
  const found = devices.find((d) =>
    d.addresses.some((a) => a.addr && !a.addr.startsWith('127.')),
  );
  if (!found) {
    log('Nenhuma interface encontrada');
    process.exit(1);
  }
  device = found.name;
}
log(`Interface: ${device}`);
log(`Capturando por ${DURATION / 1000}s — log: ${logPath}`);

// ---- capture ----
const cap = new Cap();
const buffer = Buffer.alloc(65535);
let linkType;

try {
  linkType = cap.open(device, 'tcp', 10 * 1024 * 1024, buffer);
} catch (e) {
  log(`ERRO ao abrir interface: ${e.message}`);
  process.exit(1);
}

log(`Link type: ${linkType}`);

const seen = new Map(); // connKey -> { count, bytesSeen, hasMagic }
let raw = 0;

cap.on('packet', (nbytes) => {
  raw++;
  try {
    if (linkType !== 'ETHERNET') return;
    const eth = decoders.Ethernet(buffer);
    if (eth.info.type !== decoders.PROTOCOL.ETHERNET.IPV4) return;
    const ipv4 = decoders.IPV4(buffer, eth.offset);
    if (ipv4.info.protocol !== decoders.PROTOCOL.IP.TCP) return;
    const tcp = decoders.TCP(buffer, ipv4.offset);
    const payLen = nbytes - tcp.offset;
    if (payLen < 4) return;

    const payload = Buffer.from(buffer.slice(tcp.offset, tcp.offset + payLen));
    const sport = tcp.info.srcport;
    const dport = tcp.info.dstport;
    const srcAddr = ipv4.info.srcaddr;
    const dstAddr = ipv4.info.dstaddr;

    // Group by remote server (não-loopback, não-broadcast)
    if (srcAddr.startsWith('127.') && dstAddr.startsWith('127.')) return;

    const remoteAddr =
      srcAddr.startsWith('192.168.') || srcAddr.startsWith('127.')
        ? dstAddr
        : srcAddr;
    const remotePort =
      srcAddr.startsWith('192.168.') || srcAddr.startsWith('127.')
        ? dport
        : sport;

    const key = `${remoteAddr}:${remotePort}`;
    const hasMagic = payload.indexOf(MAGIC) !== -1;

    if (!seen.has(key)) {
      seen.set(key, {
        count: 0,
        bytes: 0,
        hasMagic: false,
        firstHex: payload.slice(0, 24).toString('hex'),
      });
      log(
        `[NEW] ${srcAddr}:${sport} <-> ${dstAddr}:${dport}  remoto=${key}  firstHex=${payload.slice(0, 24).toString('hex')}`,
      );
    }
    const entry = seen.get(key);
    entry.count++;
    entry.bytes += payLen;
    if (hasMagic && !entry.hasMagic) {
      entry.hasMagic = true;
      log(
        `[MAGIC!] AION 2 magic bytes encontrados em ${key} !! hex=${payload.slice(0, 40).toString('hex')}`,
      );
    }
  } catch (e) {
    // ignore
  }
});

// Print summary every 5s
const summaryInterval = setInterval(() => {
  log(`--- Raw packets: ${raw} | Conexões únicas: ${seen.size} ---`);
  for (const [key, entry] of seen.entries()) {
    log(
      `  ${key.padEnd(30)} pkts=${String(entry.count).padStart(6)} bytes=${String(entry.bytes).padStart(8)} magic=${entry.hasMagic}`,
    );
  }
}, 5000);

// Stop after DURATION
setTimeout(() => {
  clearInterval(summaryInterval);
  cap.close();
  log('\n=== SCAN COMPLETO ===');
  log(`Raw packets: ${raw}`);
  for (const [key, entry] of seen.entries()) {
    log(
      `  ${key.padEnd(30)} pkts=${entry.count}  bytes=${entry.bytes}  MAGIC=${entry.hasMagic}  firstHex=${entry.firstHex}`,
    );
  }
  logStream.end();
  process.exit(0);
}, DURATION);

process.on('SIGINT', () => {
  cap.close();
  logStream.end();
  process.exit(0);
});
