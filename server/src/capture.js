'use strict';
/**
 * capture.js — Captura de pacotes via Npcap (Windows)
 *
 * Prioriza loopback (NPF_Loopback) onde ExitLag/VPN entrega pacotes AION 2 limpos.
 * Fallback: interface Ethernet física (com extração de TLV ExitLag).
 * Requer Npcap instalado e processo rodando como Administrador.
 */

const EventEmitter = require('events');

// 'cap' carregado lazily — evita crash ao iniciar sem Npcap instalado (ex: modo --mock)
let Cap, decoders;
function loadCap() {
  if (!Cap) {
    try {
      ({Cap, decoders} = require('cap'));
    } catch (e) {
      throw new Error(
        'Npcap não encontrado. Instale o Npcap (https://npcap.com) e reinicie.\n' + e.message
      );
    }
  }
}

const MAGIC = Buffer.from([0x06, 0x00, 0x36]);
const MIN_PAYLOAD = 5;

class PacketCapture extends EventEmitter {
  constructor() {
    super();
    this._cap = null;
    this._running = false;
  }

  static listInterfaces() {
    loadCap();
    return Cap.deviceList();
  }

  /**
   * Inicia a captura.
   * @param {string|null} iface — nome do device (null = auto)
   */
  start(iface = null) {
    loadCap();
    let device = iface;
    let isLoopback = false;

    if (!device) {
      // Auto-select: prefer loopback (VPN/ExitLag path), then first IPv4 NIC
      const devices = Cap.deviceList();
      const loopDev = devices.find(
        (d) =>
          d.name.toLowerCase().includes('loopback') ||
          (d.flags && d.flags.includes('PCAP_IF_LOOPBACK')),
      );
      if (loopDev) {
        device = loopDev.name;
        isLoopback = true;
        console.log(`[CAPTURE] Auto-selecionada loopback: ${device}`);
      } else {
        const nicDev = devices.find((d) =>
          d.addresses.some((a) => a.addr && !a.addr.startsWith('127.')),
        );
        if (!nicDev) throw new Error('Nenhuma interface de rede disponível.');
        device = nicDev.name;
        console.log(
          `[CAPTURE] Auto-selecionada NIC: ${nicDev.description || nicDev.name}`,
        );
      }
    } else {
      isLoopback =
        device.toLowerCase().includes('loopback') ||
        device.toLowerCase().includes('npcap_loopback');
    }

    const rawBuf = Buffer.alloc(65535);
    // Loopback: captura todo TCP (ExitLag usa porta local, não porta do server do jogo)
    // Ethernet: filtra portas conhecidas do AION 2
    const AION_PORTS = [23960, 30343, 20387, 38138];
    const filter = isLoopback
      ? 'tcp'
      : AION_PORTS.map((p) => `tcp port ${p}`).join(' or ');

    let linkType;
    try {
      linkType = this._cap = new Cap();
      linkType = this._cap.open(device, filter, 10 * 1024 * 1024, rawBuf);
    } catch (err) {
      throw new Error(
        `Falha ao abrir "${device}": ${err.message}\n` +
          'Verifique Npcap instalado e executar como Administrador.',
      );
    }

    this._running = true;
    const lt = linkType;
    console.log(
      `[CAPTURE] Interface: ${device} | LinkType: ${lt} | Filter: ${filter}`,
    );

    const seenMagic = new Set();

    this._cap.on('packet', (nbytes) => {
      if (!this._running) return;
      try {
        let srcAddr, srcPort, dstAddr, dstPort, payload;

        if (lt === 'NULL') {
          // Loopback: 4-byte AF_INET header + raw IPv4 + TCP
          if (nbytes < 28) return;
          const af =
            rawBuf[0] |
            (rawBuf[1] << 8) |
            (rawBuf[2] << 16) |
            (rawBuf[3] << 24);
          if (af !== 2) return; // only IPv4
          const ipOff = 4;
          if (rawBuf[ipOff] >> 4 !== 4) return;
          const ipHdrLen = (rawBuf[ipOff] & 0x0f) * 4;
          if (rawBuf[ipOff + 9] !== 6) return; // only TCP
          srcAddr = `${rawBuf[ipOff + 12]}.${rawBuf[ipOff + 13]}.${rawBuf[ipOff + 14]}.${rawBuf[ipOff + 15]}`;
          dstAddr = `${rawBuf[ipOff + 16]}.${rawBuf[ipOff + 17]}.${rawBuf[ipOff + 18]}.${rawBuf[ipOff + 19]}`;
          const tcpOff = ipOff + ipHdrLen;
          srcPort = (rawBuf[tcpOff] << 8) | rawBuf[tcpOff + 1];
          dstPort = (rawBuf[tcpOff + 2] << 8) | rawBuf[tcpOff + 3];
          const tcpHdrLen = (rawBuf[tcpOff + 12] >> 4) * 4;
          const payOff = tcpOff + tcpHdrLen;
          const payLen = nbytes - payOff;
          if (payLen < MIN_PAYLOAD) return;
          payload = Buffer.from(rawBuf.slice(payOff, payOff + payLen));
        } else {
          // ETHERNET
          const eth = decoders.Ethernet(rawBuf);
          if (eth.info.type !== decoders.PROTOCOL.ETHERNET.IPV4) return;
          const ipv4 = decoders.IPV4(rawBuf, eth.offset);
          if (ipv4.info.protocol !== decoders.PROTOCOL.IP.TCP) return;
          const tcp = decoders.TCP(rawBuf, ipv4.offset);
          const payLen = nbytes - tcp.offset;
          if (payLen < MIN_PAYLOAD) return;
          payload = Buffer.from(rawBuf.slice(tcp.offset, tcp.offset + payLen));
          srcAddr = ipv4.info.srcaddr;
          dstAddr = ipv4.info.dstaddr;
          srcPort = tcp.info.srcport;
          dstPort = tcp.info.dstport;
        }

        const connKey = `${srcAddr}:${srcPort}`;

        // Magic byte detection
        if (!seenMagic.has(connKey) && payload.indexOf(MAGIC) !== -1) {
          seenMagic.add(connKey);
          console.log(`[CAPTURE] Magic bytes detectados em ${connKey}`);
          this.emit('magic', {connKey, srcAddr, srcPort, dstAddr, dstPort});
        }

        this.emit('packet', {
          connKey,
          srcAddr,
          srcPort,
          dstAddr,
          dstPort,
          payload,
          linkType: lt,
        });
      } catch (e) {
        // ignore individual frame errors
      }
    });
  }

  stop() {
    this._running = false;
    if (this._cap) {
      try {
        this._cap.close();
      } catch (_) {}
      this._cap = null;
    }
    console.log('[CAPTURE] Captura encerrada.');
  }
}

module.exports = PacketCapture;
