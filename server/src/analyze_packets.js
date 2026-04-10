'use strict';
/**
 * analyze_packets.js — AION 2 packet analyzer
 *
 * Suporta dois modos de captura:
 *   1. Loopback (NPF_Loopback, NULL link type) — VPN/ExitLag: pacotes AION 2 limpos
 *   2. Ethernet (NIC físico) — VPN ExitLag com wrapper outer 01-LL-LL-00 + TLV
 *
 * GameStream framing (TK A2Tools Rust, confirmado):
 *   VarInt(value, length) → total_packet_bytes = value - 3
 *   Após o VarInt: 2 bytes de opcode
 *   Opcode 04 38 = dano, 05 38 = DoT
 *
 * Usage:
 *   node analyze_packets.js --iface=\Device\NPF_Loopback
 *   node analyze_packets.js --iface=\Device\NPF_{GUID}
 *   Flags: --verbose  --dump-raw  --brute
 */

const {Cap, decoders} = require('cap');
const fs = require('fs');
const path = require('path');

// ─── Config ───────────────────────────────────────────────────────────────────
const AION_PORTS = [23960, 30343, 20387, 38138];
const LOG_DIR = path.join(__dirname, '../../logs');
const MAGIC = Buffer.from([0x06, 0x00, 0x36]);

// ─── Args ─────────────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
const ifaceArg = args.find((a) => a.startsWith('--iface='));
const iface = ifaceArg ? ifaceArg.split('=').slice(1).join('=') : null;
const verbose = args.includes('--verbose');
const dumpRaw = args.includes('--dump-raw'); // dump hex of every TCP payload
const brute = args.includes('--brute'); // also brute-scan for 04 38

// ─── State ─────────────────────────────────────────────────────────────────────
const streams = new Map(); // connKey → accumulated game stream Buffer
let tcpPkts = 0,
  magicConns = 0,
  opcodeHits = 0,
  outerFrames = 0;
const seenMagic = new Set();
const startTime = Date.now();

// ─── Logging ──────────────────────────────────────────────────────────────────
if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, {recursive: true});
const logPath = path.join(LOG_DIR, `analyze_${Date.now()}.log`);
const logStream = fs.createWriteStream(logPath, {flags: 'a'});
function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}`;
  console.log(line);
  logStream.write(line + '\n');
}
function hex(buf, start = 0, len) {
  const end = len !== undefined ? start + len : buf.length;
  return Buffer.from(buf)
    .slice(start, end)
    .toString('hex')
    .match(/.{1,2}/g)
    .join(' ');
}

// ─── VarInt ────────────────────────────────────────────────────────────────────
// Returns {value, length} — exact port of A2Tools Rust read_varint
function readVarInt(buf, offset = 0) {
  let value = 0,
    shift = 0,
    count = 0;
  while (true) {
    if (offset + count >= buf.length) return {value: -1, length: -1};
    const b = buf[offset + count++] & 0xff;
    value |= (b & 0x7f) << shift;
    if ((b & 0x80) === 0) return {value, length: count};
    shift += 7;
    if (shift >= 32) return {value: -1, length: -1};
  }
}

// ─── Outer ExitLag TLV extractor ──────────────────────────────────────────────
// Only called when link=ETHERNET (NIC). Extracts field 0x22 (game bytes).
// Outer frame: [01][LE24 len] + Inner TLV: 05 <field> <varintLen> <data> ...
function extractGameBytesFromTLV(payload) {
  const result = [];
  let pos = 0;
  while (pos + 4 <= payload.length) {
    if (payload[pos] !== 0x01) {
      pos++;
      continue;
    }
    const innerLen =
      payload[pos + 1] | (payload[pos + 2] << 8) | (payload[pos + 3] << 16);
    if (innerLen < 4 || innerLen > 0x10000) {
      pos++;
      continue;
    }
    const end = pos + 4 + innerLen;
    if (end > payload.length) break;
    outerFrames++;

    let i = pos + 4;
    while (i < end) {
      if (payload[i] !== 0x05) {
        i++;
        continue;
      }
      i++;
      if (i >= end) break;
      const fieldId = payload[i++];
      if (i >= end) break;
      const vi = readVarInt(payload, i);
      if (vi.length < 0 || i + vi.length + vi.value > end) break;
      i += vi.length;
      if (fieldId === 0x22 && vi.value > 0) {
        result.push(payload.slice(i, i + vi.value));
      }
      i += vi.value;
    }
    pos = end;
  }
  return result;
}

// ─── Game stream: consume_stream (A2Tools Rust port) ─────────────────────────
// Feeds accumulated game bytes and extracts complete VarInt-framed packets.
// total_packet_bytes = value - 3  (AION 2 quirk, confirmed by Rust source)
function consumeStream(connKey, newBytes) {
  if (!streams.has(connKey)) streams.set(connKey, Buffer.alloc(0));
  const buf = Buffer.concat([streams.get(connKey), newBytes]);

  let offset = 0;
  while (offset < buf.length) {
    // Skip zero padding (as Rust does)
    if (buf[offset] === 0x00) {
      offset++;
      continue;
    }

    const vi = readVarInt(buf, offset);
    if (vi.length <= 0 || vi.value <= 0) {
      if (offset + 5 > buf.length) break;
      offset++;
      continue;
    }

    // AION 2 quirk: total_packet_bytes = value - 3
    const total = vi.value - 3;

    if (total <= 0 || total > 65535) {
      offset++;
      continue;
    }
    if (offset + total > buf.length) break; // fragment — wait

    const pkt = buf.slice(offset, offset + total);
    const opcodeOff = vi.length;

    if (opcodeOff + 2 <= pkt.length) {
      const op0 = pkt[opcodeOff],
        op1 = pkt[opcodeOff + 1];

      if (op0 === 0x04 && op1 === 0x38) {
        opcodeHits++;
        log(`[DAMAGE] ${connKey} pkLen=${total}`);
        log(`  hex: ${hex(pkt)}`);
        parseDamage(pkt, opcodeOff, connKey);
      } else if (op0 === 0x05 && op1 === 0x38) {
        opcodeHits++;
        log(`[DOT] ${connKey} pkLen=${total}`);
        log(`  hex: ${hex(pkt)}`);
      } else if (verbose) {
        log(
          `[PKT] ${connKey} len=${total} op=${op0.toString(16).padStart(2, '0')} ${op1.toString(16).padStart(2, '0')}`,
        );
      }
    }
    offset += total;
  }
  streams.set(connKey, buf.slice(offset));
}

// ─── Damage parser (port of A2Tools Rust parsing_damage_inner) ───────────────
function parseDamage(pkt, oo, connKey) {
  try {
    let off = oo + 2; // skip opcode 04 38

    // Target
    const tv = readVarInt(pkt, off);
    if (tv.length < 0) return;
    off += tv.length;
    // Switch
    const sv = readVarInt(pkt, off);
    if (sv.length < 0) return;
    off += sv.length;
    const andRes = sv.value & 0x0f;
    if (andRes < 4 || andRes > 7) {
      log(`  [!] bad andRes=${andRes}`);
      return;
    }
    // Flag (unused)
    const fv = readVarInt(pkt, off);
    if (fv.length < 0) return;
    off += fv.length;
    // Actor
    const av = readVarInt(pkt, off);
    if (av.length < 0) return;
    off += av.length;
    // 4-byte skill code
    if (off + 4 > pkt.length) return;
    const skillCode = pkt.readUInt32LE(off);
    off += 4;
    // Skip 1-byte UID field
    if (off < pkt.length) off++;
    // dummy_type (damage type)
    const dtv = readVarInt(pkt, off);
    if (dtv.length < 0) return;
    off += dtv.length;
    // Skip special damage block
    const specSz = {4: 8, 5: 12, 6: 10, 7: 14}[andRes];
    off += specSz;
    if (off >= pkt.length) return;
    // first/second values → damage
    const first = readVarInt(pkt, off);
    if (first.length < 0) return;
    off += first.length;
    const second = readVarInt(pkt, off);
    if (second.length < 0) return;
    // Use first as damage if second looks like a loop count (<=25)
    const dmg = second.value <= 25 ? first.value : second.value;

    log(
      `  >>> actor=${av.value} target=${tv.value} skill=${skillCode} DMG=${dmg}`,
    );
    log(`      switch=${sv.value} flag=${fv.value} type=${dtv.value}`);
  } catch (e) {
    log(`  [!] parseDamage: ${e.message}`);
  }
}

// ─── Brute-force scan (optional, for verification) ───────────────────────────
function bruteScan(payload, connKey) {
  for (let i = 0; i + 1 < payload.length; i++) {
    if (
      (payload[i] === 0x04 || payload[i] === 0x05) &&
      payload[i + 1] === 0x38
    ) {
      const opName = payload[i] === 0x04 ? 'DMG' : 'DOT';
      log(
        `[BRUTE-${opName}] ${connKey} offset=${i} ctx: ${hex(payload, Math.max(0, i - 4), Math.min(32, payload.length - Math.max(0, i - 4)))}`,
      );
    }
  }
}

// ─── TCP payload → game stream handler ───────────────────────────────────────
function handleTcpPayload(payload, srcAddr, srcPort, dstPort, linkType) {
  if (!payload || payload.length < 5) return;
  tcpPkts++;
  const connKey = `${srcAddr}:${srcPort}`;

  // Log magic byte detection
  if (!seenMagic.has(connKey) && payload.indexOf(MAGIC) !== -1) {
    seenMagic.add(connKey);
    magicConns++;
    log(`[MAGIC] ${connKey} (total: ${magicConns})`);
  }

  if (dumpRaw) {
    log(
      `[RAW] ${connKey} len=${payload.length} hex=${hex(payload, 0, Math.min(48, payload.length))}`,
    );
  }

  // Brute force on raw payload (optional)
  if (brute) bruteScan(payload, connKey);

  if (linkType === 'NULL') {
    // Loopback: raw AION 2 stream, no wrapper — feed directly
    consumeStream(connKey, payload);
  } else {
    // Ethernet / NIC: has ExitLag outer TLV wrapper
    const chunks = extractGameBytesFromTLV(payload);
    if (chunks.length > 0) {
      for (const chunk of chunks) {
        consumeStream(connKey, chunk);
      }
    } else {
      // Fallback: try feeding raw payload (in case of non-tunnelled connection)
      consumeStream(connKey, payload);
    }
  }
}

// ─── Capture ──────────────────────────────────────────────────────────────────
function start() {
  if (!iface) {
    log('[ERROR] Use: node analyze_packets.js --iface=\\Device\\NPF_Loopback');
    log('[ERROR]  or: node analyze_packets.js --iface=\\Device\\NPF_{GUID}');
    process.exit(1);
  }

  const rawBuf = Buffer.alloc(65535);
  // On loopback, ExitLag uses local ports (e.g. 52921) — no remote port filter possible.
  // A2Tools Rust captures all TCP and detects game stream via magic bytes.
  const isLoopback =
    iface.toLowerCase().includes('loopback') ||
    iface.toLowerCase().includes('npcap_loopback');
  const filter = isLoopback
    ? 'tcp'
    : AION_PORTS.map((p) => `tcp port ${p}`).join(' or ');
  const cap = new Cap();
  const lt = cap.open(iface, filter, 10 * 1024 * 1024, rawBuf);

  log(`[ANALYZE] iface=${iface}`);
  log(`[ANALYZE] linkType=${lt}`);
  log(`[ANALYZE] filter: ${filter}`);
  log(`[ANALYZE] log: ${logPath}`);
  log(`[ANALYZE] ATAQUE UM BONECO DE TREINO AGORA!`);
  if (lt === 'NULL') {
    log(`[ANALYZE] Modo: LOOPBACK — pacotes AION 2 limpos (VPN/ExitLag)`);
  } else {
    log(`[ANALYZE] Modo: ETHERNET — com wrapper ExitLag (campo 0x22)`);
  }

  cap.on('packet', (nbytes) => {
    try {
      if (lt === 'NULL') {
        // NULL/Loopback: 4-byte AF header + IPv4 + TCP
        if (nbytes < 24 + 4) return;
        // Verify AF_INET (little-endian 2)
        const af =
          rawBuf[0] | (rawBuf[1] << 8) | (rawBuf[2] << 16) | (rawBuf[3] << 24);
        if (af !== 2) return; // not IPv4
        const ipOff = 4;
        if (rawBuf[ipOff] >> 4 !== 4) return; // not IPv4
        const ipHdrLen = (rawBuf[ipOff] & 0x0f) * 4;
        if (rawBuf[ipOff + 9] !== 6) return; // not TCP
        const srcIp = `${rawBuf[ipOff + 12]}.${rawBuf[ipOff + 13]}.${rawBuf[ipOff + 14]}.${rawBuf[ipOff + 15]}`;
        const tcpOff = ipOff + ipHdrLen;
        const srcPort = (rawBuf[tcpOff] << 8) | rawBuf[tcpOff + 1];
        const dstPort = (rawBuf[tcpOff + 2] << 8) | rawBuf[tcpOff + 3];
        const tcpHdrLen = (rawBuf[tcpOff + 12] >> 4) * 4;
        const payOff = tcpOff + tcpHdrLen;
        const payLen = nbytes - payOff;
        if (payLen < 5) return;
        const payload = Buffer.from(rawBuf.slice(payOff, payOff + payLen));
        handleTcpPayload(payload, srcIp, srcPort, dstPort, 'NULL');
      } else {
        // ETHERNET
        const eth = decoders.Ethernet(rawBuf);
        if (eth.info.type !== decoders.PROTOCOL.ETHERNET.IPV4) return;
        const ipv4 = decoders.IPV4(rawBuf, eth.offset);
        if (ipv4.info.protocol !== decoders.PROTOCOL.IP.TCP) return;
        const tcp = decoders.TCP(rawBuf, ipv4.offset);
        const payLen = nbytes - tcp.offset;
        if (payLen < 5) return;
        const payload = Buffer.from(
          rawBuf.slice(tcp.offset, tcp.offset + payLen),
        );
        handleTcpPayload(
          payload,
          ipv4.info.srcaddr,
          tcp.info.srcport,
          tcp.info.dstport,
          'ETHERNET',
        );
      }
    } catch (e) {
      /* silent */
    }
  });

  setInterval(() => {
    const s = ((Date.now() - startTime) / 1000).toFixed(0);
    log(
      `[STATS] elapsed=${s}s tcp=${tcpPkts} magic=${magicConns} outerFrames=${outerFrames} opcodeHits=${opcodeHits} conns=${streams.size}`,
    );
  }, 10000);

  process.on('SIGINT', () => {
    log(
      `[FIM] tcp=${tcpPkts} magic=${magicConns} outerFrames=${outerFrames} opcodeHits=${opcodeHits}`,
    );
    cap.close();
    logStream.end();
    process.exit(0);
  });
}

start();
