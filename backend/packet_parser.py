"""
packet_parser.py — Parser de pacotes do AION 2

⚠️  IMPORTANTE: O protocolo do AION 2 é proprietário.
    Os offsets aqui são ESTIMATIVAS baseadas em protocolos
    semelhantes de MMORPGs. Você precisará ajustá-los usando
    Wireshark + análise manual dos pacotes capturados.

Estrutura estimada de pacote de dano (incoming, big-endian):
  Offset  Tamanho  Campo
  0x00    2 bytes  Tamanho do pacote
  0x02    2 bytes  Opcode
  0x04    4 bytes  Attacker ID
  0x08    4 bytes  Target ID
  0x0C    2 bytes  Skill ID
  0x0E    4 bytes  Damage value
  0x12    1 byte   Flags (bit0=crit, bit1=miss, bit2=dodge)
  0x13    ...      Restante
"""

from nickname_cache import NicknameCache
from job_detector import detect_job_from_skill, get_job_icon
from skill_lookup import get_skill_lookup
import struct
import logging
from dataclasses import dataclass
from typing import Optional

# Habilita logs detalhados para depuração de parsing
logging.basicConfig(level=logging.DEBUG)


logger = logging.getLogger(__name__)

# ─── Opcodes AION 2 TW (confirmados de repositórios existentes) ──────────────
# Formato: 2 bytes (usando notação de byte individual para clareza)
OPCODE_DAMAGE = (0x04, 0x38)  # Dano direto
OPCODE_DOT = (0x05, 0x38)  # Dano DoT (Damage over Time)
OPCODE_NICKNAME = (0x04, 0x8D)  # Nome de entidade
OPCODE_SUMMON = (0x40, 0x36)  # Summon/invocação
OPCODE_MOB_HP = (0x00, 0x8D)  # HP de mob
OPCODE_PING = (0x03, 0x36)  # Ping/tempo
OPCODE_COMPRESSED = (0xFF, 0xFF)  # Stream comprimido (LZ4)

# Mock opcode (compatibilidade)
OPCODE_MOCK_DAMAGE = 0x0301

KNOWN_OPCODES = {OPCODE_DAMAGE, OPCODE_DOT,
                 OPCODE_NICKNAME, OPCODE_SUMMON, OPCODE_MOB_HP}

# ─── Special Damage Flags (confirmado de projetos existentes) ────────────────
FLAG_BACK_ATTACK = 0x01  # Ataque pelas costas
FLAG_UNKNOWN1 = 0x02  # Desconhecido
FLAG_PARRY = 0x04  # Aparado
FLAG_PERFECT = 0x08  # Perfeito
FLAG_DOUBLE = 0x10  # Dano duplo
FLAG_ENDURE = 0x20  # Endure
FLAG_UNKNOWN2 = 0x40  # Desconhecido
FLAG_POWER_SHARD = 0x80  # Power Shard


@dataclass
class CombatEvent:
    event_type: str          # "damage" | "heal" | "dot"
    attacker_id: int
    target_id: int
    skill_id: int
    value: int               # quantidade de dano ou cura
    is_crit: bool = False
    is_back_attack: bool = False
    is_perfect: bool = False
    is_double: bool = False
    is_parry: bool = False
    is_dot: bool = False     # Damage over time
    is_miss: bool = False    # Ataque errou
    is_dodge: bool = False   # Ataque foi esquivado
    timestamp: float = 0.0   # preenchido pelo calculator
    # Enriquecimentos (preenchidos pelo parser)
    skill_name: str = ""
    skill_icon: str = ""
    attacker_name: str = ""
    attacker_class: str = "Unknown"
    attacker_class_icon: str = ""


class PacketParser:
    """
    Interpreta payloads brutos em CombatEvents.
    Adapte os offsets à medida que descobrir o protocolo real.
    """

    def __init__(self, use_mock_format: bool = False):
        """
        use_mock_format: True quando usando MockCapture (formato fixo do simulador)
        """
        self.use_mock_format = use_mock_format
        self._unknown_opcodes: set[tuple[int, int]] = set()

        # Sistemas de enriquecimento
        self.skill_lookup = get_skill_lookup()
        self.nickname_cache = NicknameCache()

        logger.info(
            "PacketParser inicializado com skill_lookup e nickname_cache")

    def parse(self, payload: bytes, direction: str) -> Optional[CombatEvent]:
        """
        Retorna CombatEvent ou None se o pacote não for relevante.
        """
        if len(payload) < 6:
            return None

        logger.debug(
            f"Parsing payload len={len(payload)} dir={direction} head={payload[:48].hex()}")

        try:
            if self.use_mock_format:
                return self._parse_mock(payload)
            else:
                return self._parse_real(payload, direction)
        except struct.error:
            return None
        except Exception as e:
            logger.debug(f"Erro ao parsear pacote: {e}")
            return None

    # ─── Formato simulado (MockCapture) ───────────────────────────────────────
    def _parse_mock(self, payload: bytes) -> Optional[CombatEvent]:
        """
        Formato: [opcode:H][attacker:B][target:B][skill:I][damage:I][crit:B]
        Total: 13 bytes (skill agora é 4 bytes para suportar skill_ids reais do AION 2)
        """
        if len(payload) < 13:
            return None

        opcode, attacker, target, skill, damage, crit_byte = struct.unpack_from(
            ">HBBIIB", payload, 0)

        if opcode != OPCODE_MOCK_DAMAGE:
            return None

        event = CombatEvent(
            event_type="damage",
            attacker_id=attacker,
            target_id=target,
            skill_id=skill,
            value=damage,
            is_crit=bool(crit_byte),
        )

        return self._enrich_event(event)

    # ─── Formato real AION 2 TW (baseado em projetos existentes) ─────────────────
    def _parse_real(self, payload: bytes, direction: str) -> Optional[CombatEvent]:
        """
        Parser de pacotes AION 2 TW usando VarInt (Protocol Buffers)
        Estrutura: [VarInt:length][2bytes:opcode][payload]
        """
        if len(payload) < 3:
            return None

        # Lê VarInt length
        length, varint_len = self._read_varint(payload, 0)
        if length < 0:
            return None

        offset = varint_len
        if len(payload) < offset + 2:
            return None

        # Lê opcode (2 bytes)
        opcode = (payload[offset], payload[offset + 1])
        offset += 2

        if opcode not in KNOWN_OPCODES:
            if opcode not in self._unknown_opcodes:
                self._unknown_opcodes.add(opcode)
                logger.debug(
                    f"Opcode desconhecido: 0x{opcode[0]:02X} 0x{opcode[1]:02X}")
            return None

        # ── Pacote de dano direto (0x04 0x38) ──
        if opcode == OPCODE_DAMAGE:
            return self._parse_damage_packet(payload, offset)

        # ── Pacote de DoT (0x05 0x38) ──
        if opcode == OPCODE_DOT:
            return self._parse_dot_packet(payload, offset)

        return None

    def _parse_damage_packet(self, payload: bytes, offset: int) -> Optional[CombatEvent]:
        """Parser de pacote de dano direto 0x04 0x38"""
        try:
            # Target ID (varint)
            target_id, consumed = self._read_varint(payload, offset)
            if target_id <= 0:
                return None
            offset += consumed

            # Switch value (varint)
            switch_val, consumed = self._read_varint(payload, offset)
            offset += consumed

            # Flag field (varint - skip)
            _, consumed = self._read_varint(payload, offset)
            offset += consumed

            # Actor ID (varint)
            actor_id, consumed = self._read_varint(payload, offset)
            if actor_id <= 0 or actor_id == target_id:
                return None
            offset += consumed

            # Skill code (uint32le) + 1 byte unknown
            if offset + 5 > len(payload):
                return None
            skill_id = struct.unpack_from("<I", payload, offset)[0]
            offset += 5

            # Damage type (varint)
            damage_type, consumed = self._read_varint(payload, offset)
            offset += consumed

            # Special flags block (tamanho depende de switch_val)
            switch_mask = switch_val & 0x0F
            flag_size = {4: 8, 5: 12, 6: 10, 7: 14}.get(switch_mask, 0)
            if flag_size == 0:
                return None

            flags_byte = 0
            if flag_size >= 10:  # Tem flag byte
                flags_byte = payload[offset] if offset < len(payload) else 0
            offset += flag_size

            # Unknown varint
            _, consumed = self._read_varint(payload, offset)
            offset += consumed

            # Damage value (varint)
            damage, _ = self._read_varint(payload, offset)
            logger.debug(
                f"Parsed damage packet: actor_id={actor_id} target_id={target_id} skill_id={skill_id} damage={damage} damage_type={damage_type} flags=0x{flags_byte:02X}")

            event = CombatEvent(
                event_type="damage",
                attacker_id=actor_id,
                target_id=target_id,
                skill_id=skill_id,
                value=damage,
                is_crit=(damage_type == 3),
                is_back_attack=bool(flags_byte & FLAG_BACK_ATTACK),
                is_perfect=bool(flags_byte & FLAG_PERFECT),
                is_double=bool(flags_byte & FLAG_DOUBLE),
                is_parry=bool(flags_byte & FLAG_PARRY),
            )

            return self._enrich_event(event)
        except Exception as e:
            logger.debug(f"Erro ao parsear dano: {e}")
            return None

    def _parse_dot_packet(self, payload: bytes, offset: int) -> Optional[CombatEvent]:
        """Parser de pacote DoT 0x05 0x38"""
        try:
            # Target ID
            target_id, consumed = self._read_varint(payload, offset)
            if target_id <= 0:
                return None
            offset += consumed

            # Effect type byte (deve ter bit 0x02)
            if offset >= len(payload):
                return None
            effect_type = payload[offset]
            if not (effect_type & 0x02):
                return None
            offset += 1

            # Actor ID
            actor_id, consumed = self._read_varint(payload, offset)
            if actor_id <= 0 or actor_id == target_id:
                return None
            offset += consumed

            # Unknown varint
            _, consumed = self._read_varint(payload, offset)
            offset += consumed

            # Skill code (uint32le)
            if offset + 4 > len(payload):
                return None
            skill_id = struct.unpack_from("<I", payload, offset)[0]
            offset += 4

            # Damage
            damage, _ = self._read_varint(payload, offset)

            event = CombatEvent(
                event_type="damage",
                attacker_id=actor_id,
                target_id=target_id,
                skill_id=skill_id,
                value=damage,
                is_dot=True,
            )

            return self._enrich_event(event)
        except Exception as e:
            logger.debug(f"Erro ao parsear DoT: {e}")
            return None

    def _read_varint(self, data: bytes, offset: int) -> tuple[int, int]:
        """Lê VarInt (Protocol Buffers style). Retorna (valor, bytes_consumidos)"""
        value = 0
        shift = 0
        consumed = 0

        while offset + consumed < len(data):
            byte = data[offset + consumed]
            consumed += 1

            value |= (byte & 0x7F) << shift

            if not (byte & 0x80):  # MSB = 0, fim do varint
                return value, consumed

            shift += 7
            if shift >= 32:  # Overflow protection
                return -1, -1

        return -1, -1

    def _enrich_event(self, event: CombatEvent) -> CombatEvent:
        """
        Enriquece CombatEvent com informações de skill e classe.

        Args:
            event: CombatEvent básico

        Returns:
            CombatEvent enriquecido
        """
        # Skill info
        skill_info = self.skill_lookup.get_skill_info(event.skill_id)
        if skill_info:
            event.skill_name = skill_info.name
            event.skill_icon = skill_info.icon
        else:
            event.skill_name = f"Skill {event.skill_id}"
            event.skill_icon = f"skill_{event.skill_id}.png"

        # Job/Class detection
        job = detect_job_from_skill(event.skill_id)
        if job:
            event.attacker_class = job.class_name
            event.attacker_class_icon = get_job_icon(job)

        # Nickname lookup
        event.attacker_name = self.nickname_cache.get_nickname(
            event.attacker_id) or ""

        # Confirmar actor em combate
        self.nickname_cache.confirm_combat_actor(event.attacker_id)

        return event

    def dump_unknown_opcodes(self) -> set[tuple[int, int]]:
        """Retorna opcodes encontrados mas não reconhecidos (útil para engenharia reversa)."""
        return self._unknown_opcodes.copy()
