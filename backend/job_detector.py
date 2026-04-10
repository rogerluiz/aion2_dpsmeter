"""
job_detector.py — Detecção automática de classe baseado em skills usadas

Baseado em análise de repositórios AION 2:
- nousx/aion2-dps-meter
- Kuroukihime/AIon2-Dps-Meter
- TK-open-public/Aion2-Dps-Meter

AION 2 Skill Code Format: XXYYZZZZ (8 dígitos)
- XX = Class ID (11-18)
- YYZZZZ = Skill específica
"""

from enum import Enum
from typing import Optional


class JobClass(Enum):
    """Classes do AION 2 TW"""
    GLADIATOR = ("Gladiator", "glad", 11)      # 검성
    TEMPLAR = ("Templar", "temp", 12)         # 수호성
    ASSASSIN = ("Assassin", "asmo", 13)        # 살성
    RANGER = ("Ranger", "rang", 14)           # 궁성
    SORCERER = ("Sorcerer", "sorc", 15)       # 마도성
    ELEMENTALIST = ("Elementalist", "elem", 16)  # 정령성
    CLERIC = ("Cleric", "cleric", 17)         # 치유성
    CHANTER = ("Chanter", "chant", 18)        # 호법성
    UNKNOWN = ("Unknown", "unknown", 0)

    def __init__(self, class_name: str, prefix: str, class_id: int):
        self.class_name = class_name
        self.prefix = prefix
        self.class_id = class_id


# Mapeamento de skill ranges para classes (validado contra 3 projetos AION 2)
# Skills do AION 2 seguem padrão: XXYYZZZZ onde XX = classe (11-18)
SKILL_RANGES = {
    # Warrior (Espada/Escudo)
    (11_000_000, 11_999_999): JobClass.GLADIATOR,   # 검성
    (12_000_000, 12_999_999): JobClass.TEMPLAR,     # 수호성

    # Scout (Arco/Adaga)
    (13_000_000, 13_999_999): JobClass.ASSASSIN,    # 살성
    (14_000_000, 14_999_999): JobClass.RANGER,      # 궁성

    # Mage (Magia)
    (15_000_000, 15_999_999): JobClass.SORCERER,      # 마도성
    (16_000_000, 16_999_999): JobClass.ELEMENTALIST,  # 정령성

    # Priest (Cura/Suporte)
    (17_000_000, 17_999_999): JobClass.CLERIC,      # 치유성
    (18_000_000, 18_999_999): JobClass.CHANTER,     # 호법성
}


# Skills específicas conhecidas (extraídas dos projetos AION 2)
SIGNATURE_SKILLS = {
    # Gladiator (11M)
    11_020_000: JobClass.GLADIATOR,  # Keen Strike
    11_800_008: JobClass.GLADIATOR,  # Murderous Burst
    11_250_000: JobClass.GLADIATOR,  # Zikel's Blessing

    # Templar (12M)
    12_010_000: JobClass.TEMPLAR,  # Vicious Strike
    12_780_000: JobClass.TEMPLAR,  # Fury
    12_120_000: JobClass.TEMPLAR,  # Taunt

    # Assassin (13M)
    13_010_000: JobClass.ASSASSIN,  # Quick Slice
    13_350_000: JobClass.ASSASSIN,  # Heart Gore

    # Ranger (14M)
    14_020_000: JobClass.RANGER,  # Snipe
    14_310_000: JobClass.RANGER,  # Rapid Fire

    # Sorcerer (15M)
    15_210_000: JobClass.SORCERER,  # Flame Arrow
    15_320_000: JobClass.SORCERER,  # Delayed Explosion

    # Elementalist (16M)
    16_010_000: JobClass.ELEMENTALIST,  # Cold Shock
    16_370_000: JobClass.ELEMENTALIST,  # Fire Blessing

    # Cleric (17M)
    17_010_000: JobClass.CLERIC,  # Earth's Retribution
    17_420_000: JobClass.CLERIC,  # Yustiel's Power

    # Chanter (18M)
    18_010_000: JobClass.CHANTER,  # Wave Strike (presumed)
    18_780_000: JobClass.CHANTER,  # Earth's Promise
}


def detect_job_from_skill(skill_code: int) -> Optional[JobClass]:
    """
    Detecta a classe do jogador baseado no código da skill usada.

    Args:
        skill_code: Código da skill (ex: 10001234)

    Returns:
        JobClass detectado ou None se não identificado
    """
    # Primeiro verifica skills signature (mais preciso)
    if skill_code in SIGNATURE_SKILLS:
        return SIGNATURE_SKILLS[skill_code]

    # Depois verifica ranges
    for (min_range, max_range), job in SKILL_RANGES.items():
        if min_range <= skill_code <= max_range:
            return job

    return None


def get_job_icon(job: JobClass) -> str:
    """
    Retorna o path do ícone da classe.

    Args:
        job: JobClass enum

    Returns:
        Path para o ícone (ex: "assets/classes/gladiator.png")
    """
    if job == JobClass.UNKNOWN:
        return "assets/classes/unknown.png"

    return f"assets/classes/{job.prefix}.png"


def normalize_skill_code(raw_code: int) -> int:
    """
    Normaliza código de skill removendo variações.

    Exemplos:
      10001234 → 10001230 (remove últimos dígitos)
      10001235 → 10001230

    Isso agrupa variações da mesma skill base.

    Args:
        raw_code: Código bruto da skill

    Returns:
        Código normalizado
    """
    # Remove últimos 4 dígitos, mantém base
    base = raw_code - (raw_code % 10000)
    return base


def is_player_skill(skill_code: int) -> bool:
    """
    Verifica se uma skill pertence a um jogador (não NPC).

    Args:
        skill_code: Código da skill

    Returns:
        True se for skill de player
    """
    # Player skills no AION 2: 11M-18M
    return 11_000_000 <= skill_code <= 18_999_999


def is_npc_skill(skill_code: int) -> bool:
    """
    Verifica se uma skill pertence a um NPC/mob.

    Args:
        skill_code: Código da skill

    Returns:
        True se for skill de NPC
    """
    # NPC skills: 1M-9M (7 dígitos)
    return 1_000_000 <= skill_code <= 9_999_999
