"""
capture.py — Captura de pacotes via Npcap/Scapy
Requer: Npcap instalado no Windows + scapy via pip
"""

import threading
import logging
import os
import time
from typing import Callable, Optional
from scapy.all import sniff, get_if_list, conf
from scapy.layers.inet import IP, TCP, UDP
from scapy.utils import PcapWriter

logger = logging.getLogger(__name__)

# Auto-detect combat port (AION 2 usa porta dinâmica)
# Detecção acontece ao encontrar magic bytes nos pacotes
AION2_PORTS = set()  # Será preenchido dinamicamente
DETECTED_PORT = None

# Tamanho mínimo de payload para ser relevante
MIN_PAYLOAD_SIZE = 6


class PacketCapture:
    """
    Captura pacotes de rede do AION 2 usando Npcap via Scapy.
    Chama on_packet(payload: bytes) para cada pacote relevante capturado.
    """

    def __init__(self, on_packet: Callable[[bytes, str], None], interface: Optional[str] = None):
        self.on_packet = on_packet
        self.interface = interface
        self._thread: Optional[threading.Thread] = None
        self._running = False
        self._pcap_writer: Optional[PcapWriter] = None
        # directory to save pcaps
        self._pcap_dir = os.path.join(os.path.dirname(__file__), 'pcaps')
        try:
            os.makedirs(self._pcap_dir, exist_ok=True)
        except Exception:
            pass

    def list_interfaces(self) -> list[str]:
        """Retorna lista de interfaces de rede disponíveis."""
        return get_if_list()

    def start(self):
        """Inicia a captura em uma thread separada."""
        if self._running:
            logger.warning("Captura já está rodando.")
            return

        self._running = True
        self._thread = threading.Thread(target=self._capture_loop, daemon=True)
        self._thread.start()
        logger.info(
            f"Captura iniciada na interface: {self.interface or 'auto'}")

        # open pcap writer for this session
        try:
            safe_name = (self.interface or 'auto').replace('\\', '_').replace(
                '/', '_').replace(':', '_').replace('{', '').replace('}', '')
            fname = f"capture_{safe_name}_{int(time.time())}.pcap"
            fpath = os.path.join(self._pcap_dir, fname)
            self._pcap_writer = PcapWriter(fpath, append=False, sync=True)
            logger.info(f"PCAP writer opened: {fpath}")
        except Exception as e:
            logger.debug(f"Não foi possível abrir PCAP writer: {e}")

    def stop(self):
        """Para a captura."""
        self._running = False
        logger.info("Captura encerrada.")
        # close pcap writer
        try:
            if self._pcap_writer:
                try:
                    self._pcap_writer.close()
                except Exception:
                    pass
                self._pcap_writer = None
                logger.info("PCAP writer fechado.")
        except Exception:
            pass

    def _capture_loop(self):
        try:
            sniff(
                iface=self.interface,
                filter=self._build_bpf_filter(),
                prn=self._handle_packet,
                store=False,
                stop_filter=lambda _: not self._running,
            )
        except Exception as e:
            logger.error(f"Erro na captura: {e}")

    def _build_bpf_filter(self) -> str:
        """Gera filtro BPF - captura TCP (porta dinâmica)."""
        # Captura todo tráfego TCP para detectar porta automaticamente
        if DETECTED_PORT:
            return f"tcp port {DETECTED_PORT}"
        return "tcp"  # Captura tudo até detectar porta

    def _handle_packet(self, pkt):
        """Processa cada pacote capturado."""
        try:
            direction = "unknown"

            if IP in pkt:
                if TCP in pkt:
                    layer = pkt[TCP]
                    sport, dport = layer.sport, layer.dport
                    payload = bytes(layer.payload)
                elif UDP in pkt:
                    layer = pkt[UDP]
                    sport, dport = layer.sport, layer.dport
                    payload = bytes(layer.payload)
                else:
                    return

                if len(payload) < MIN_PAYLOAD_SIZE:
                    return

                # Log básico do pacote (debug) — mostra portas e começo do payload
                try:
                    logger.debug(
                        f"Pkt sport={sport} dport={dport} len={len(payload)} magic_in={magic in payload} payload_hex={payload[:48].hex()}"
                    )
                except Exception:
                    pass

                # Magic bytes para detectar porta do AION 2: 0x06 0x00 0x36
                global DETECTED_PORT, AION2_PORTS
                magic = b'\x06\x00\x36'
                if DETECTED_PORT is None and magic in payload:
                    DETECTED_PORT = sport if sport > 1024 else dport
                    AION2_PORTS.add(DETECTED_PORT)
                    logger.info(
                        f"🔥 Porta de combate detectada: {DETECTED_PORT}")

                # Log quando já detectamos a porta (debug)
                if DETECTED_PORT:
                    logger.debug(
                        f"Using DETECTED_PORT={DETECTED_PORT}; direction={direction}")

                # Determina direção
                if DETECTED_PORT:
                    if sport == DETECTED_PORT:
                        direction = "incoming"  # Servidor → Cliente
                    elif dport == DETECTED_PORT:
                        direction = "outgoing"  # Cliente → Servidor
                    else:
                        return
                else:
                    return

                self.on_packet(payload, direction)

                # write full scapy packet to pcap if enabled
                try:
                    if self._pcap_writer is not None:
                        self._pcap_writer.write(pkt)
                except Exception:
                    pass

        except Exception as e:
            logger.debug(f"Erro ao processar pacote: {e}")


class MockCapture:
    """
    Captura simulada para desenvolvimento sem Npcap.
    Gera eventos de dano aleatórios para testar a UI.
    """

    import random
    import time

    def __init__(self, on_packet: Callable[[bytes, str], None]):
        self.on_packet = on_packet
        self._running = False
        self._thread: Optional[threading.Thread] = None

    def start(self):
        import random
        import time
        self._running = True
        self._thread = threading.Thread(target=self._mock_loop, daemon=True)
        self._thread.start()
        logger.info("MockCapture iniciado — gerando dados simulados.")

    def stop(self):
        self._running = False

    def _mock_loop(self):
        import random
        import time
        import struct

        player_ids = [0x01, 0x02, 0x03, 0x04]
        target_ids = [0xA1, 0xA2, 0xA3]
        # Skills reais do AION 2 TW (validados contra 3 projetos open source)
        skill_ids = [
            11_020_000,  # Gladiator - Keen Strike
            11_250_000,  # Gladiator - Zikel's Blessing
            12_010_000,  # Templar - Vicious Strike
            12_780_000,  # Templar - Fury
            13_010_000,  # Assassin - Quick Slice
            13_350_000,  # Assassin - Heart Gore
            14_020_000,  # Ranger - Snipe
            14_310_000,  # Ranger - Rapid Scattershot
            15_210_000,  # Sorcerer - Flame Arrow
            16_010_000,  # Elementalist - Cold Shock
            17_010_000,  # Cleric - Earth's Retribution
            18_010_000,  # Chanter - Wave Strike
        ]

        while self._running:
            time.sleep(random.uniform(0.05, 0.3))
            # Simula pacote de dano: [opcode(2)] [attacker(1)] [target(1)] [skill(4)] [damage(4)] [crit(1)]
            opcode = 0x0301  # opcode fictício de ataque
            attacker = random.choice(player_ids)
            target = random.choice(target_ids)
            skill = random.choice(skill_ids)
            damage = random.randint(50, 8000)
            is_crit = random.random() < 0.15

            # Formato ajustado: skill agora é I (4 bytes) em vez de H (2 bytes)
            payload = struct.pack(">HBBIIB",
                                  opcode, attacker, target, skill, damage, int(is_crit))
            self.on_packet(payload, "incoming")
