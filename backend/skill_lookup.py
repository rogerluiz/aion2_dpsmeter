"""
skill_lookup.py — Sistema de lookup de skills do AION 2

Mapeia skill codes para nomes, ícones e informações
"""

import json
import logging
from pathlib import Path
from typing import Dict, Optional

logger = logging.getLogger(__name__)


class SkillInfo:
    """Informações de uma skill"""

    def __init__(self, code: int, name: str, icon: str = "", job_class: str = "Unknown"):
        self.code = code
        self.name = name
        self.icon = icon or f"skill_{code}.png"
        self.job_class = job_class

    def to_dict(self) -> dict:
        return {
            "code": self.code,
            "name": self.name,
            "icon": self.icon,
            "class": self.job_class
        }


class SkillLookup:
    """
    Gerencia banco de dados de skills.

    Carrega skills de arquivo JSON e fornece lookup rápido.
    """

    def __init__(self, data_file: Optional[Path] = None):
        """
        Inicializa skill lookup.

        Args:
            data_file: Path para arquivo JSON com skills (opcional)
        """
        self.skills: Dict[int, SkillInfo] = {}

        # Carregar skills do arquivo se fornecido
        if data_file and data_file.exists():
            self._load_from_file(data_file)
        else:
            # Usar skills padrão embutidas
            self._load_default_skills()

        logger.info(f"SkillLookup inicializado com {len(self.skills)} skills")

    def _load_from_file(self, data_file: Path):
        """Carrega skills de arquivo JSON"""
        try:
            with open(data_file, 'r', encoding='utf-8') as f:
                data = json.load(f)

            for code_str, info in data.items():
                code = int(code_str)
                self.skills[code] = SkillInfo(
                    code=code,
                    name=info.get("name", f"Skill {code}"),
                    icon=info.get("icon", ""),
                    job_class=info.get("class", "Unknown")
                )

            logger.info(f"Carregadas {len(self.skills)} skills de {data_file}")
        except Exception as e:
            logger.error(f"Erro ao carregar skills de {data_file}: {e}")
            self._load_default_skills()

    def _load_default_skills(self):
        """
        Carrega skills padrão do AION 2 TW.

        Skills extraídas de 3 repositórios AION 2 verificados:
        - nousx/aion2-dps-meter (391 skills)
        - Kuroukihime/AIon2-Dps-Meter
        - TK-open-public/Aion2-Dps-Meter

        Em produção, carregar de arquivo JSON completo.
        """
        # Skills mais comuns do AION 2 (validadas contra repositórios)
        default_skills = {
            # Gladiator (11M) - 검성
            11_020_000: ("Keen Strike", "Gladiator"),
            11_250_000: ("Zikel's Blessing", "Gladiator"),
            11_400_000: ("Assault Stance", "Gladiator"),
            11_800_008: ("Murderous Burst", "Gladiator"),
            11_030_000: ("Ferocious Strike", "Gladiator"),
            11_040_000: ("Focused Evasion", "Gladiator"),

            # Templar (12M) - 수호성
            12_010_000: ("Vicious Strike", "Templar"),
            12_020_000: ("Decisive Strike", "Templar"),
            12_030_000: ("Desperate Strike", "Templar"),
            12_060_000: ("Punishing Strike", "Templar"),
            12_100_000: ("Shield Smite", "Templar"),
            12_120_000: ("Taunt", "Templar"),
            12_240_000: ("Judgment", "Templar"),
            12_350_000: ("Warding Strike", "Templar"),
            12_780_000: ("Fury", "Templar"),

            # Assassin (13M) - 살성
            13_010_000: ("Quick Slice", "Assassin"),
            13_030_000: ("Breaking Slice", "Assassin"),
            13_040_000: ("Swift Slice", "Assassin"),
            13_060_000: ("Ambush", "Assassin"),
            13_070_000: ("Shadowstrike", "Assassin"),
            13_100_000: ("Savage Roar", "Assassin"),
            13_210_000: ("Whirlwind Slice", "Assassin"),
            13_350_000: ("Heart Gore", "Assassin"),
            13_220_000: ("Shadow Fall", "Assassin"),

            # Ranger (14M) - 궁성
            14_020_000: ("Snipe", "Ranger"),
            14_030_000: ("Rapid Fire", "Ranger"),
            14_040_000: ("Spiral Arrow", "Ranger"),
            14_090_000: ("Marking Shot", "Ranger"),
            14_100_000: ("Tempest Arrow", "Ranger"),
            14_220_000: ("Blessed Arrow", "Ranger"),
            14_310_000: ("Rapid Scattershot", "Ranger"),
            14_340_000: ("Tempest Shot", "Ranger"),

            # Sorcerer (15M) - 마도성
            15_010_000: ("Flame Scattershot", "Sorcerer"),
            15_030_000: ("Burst", "Sorcerer"),
            15_040_000: ("Firestorm", "Sorcerer"),
            15_050_000: ("Blaze", "Sorcerer"),
            15_060_000: ("Hellfire", "Sorcerer"),
            15_110_000: ("Winter's Shackles", "Sorcerer"),
            15_150_000: ("Frost", "Sorcerer"),
            15_210_000: ("Flame Arrow", "Sorcerer"),
            15_220_000: ("Frost Burst", "Sorcerer"),
            15_320_000: ("Delayed Explosion", "Sorcerer"),

            # Elementalist (16M) - 정령성 (era Spiritmaster no AION 1)
            16_010_000: ("Cold Shock", "Elementalist"),
            16_020_000: ("Vacuum Explosion", "Elementalist"),
            16_030_000: ("Earth Tremor", "Elementalist"),
            16_040_000: ("Combustion", "Elementalist"),
            16_050_000: ("Ashy Call", "Elementalist"),
            16_140_000: ("Jointstrike: Curse", "Elementalist"),
            16_150_000: ("Cooperative: Corrosion", "Elementalist"),
            16_220_000: ("Armor of Flame", "Elementalist"),
            16_370_000: ("Fire Blessing", "Elementalist"),

            # Cleric (17M) - 치유성
            17_010_000: ("Earth's Retribution", "Cleric"),
            17_020_000: ("Thunder and Lightning", "Cleric"),
            17_030_000: ("Discharge", "Cleric"),
            17_040_000: ("Judgment Thunder", "Cleric"),
            17_050_000: ("Divine Punishment", "Cleric"),
            17_060_000: ("Heal", "Cleric"),
            17_070_000: ("Chain of Pain", "Cleric"),
            17_080_000: ("Debilitating Mark", "Cleric"),
            17_090_000: ("Resurrection", "Cleric"),
            17_160_000: ("Word of Inspiration", "Cleric"),
            17_400_000: ("Earth Punishment", "Cleric"),
            17_420_000: ("Yustiel's Power", "Cleric"),

            # Chanter (18M) - 호법성
            18_010_000: ("Wave Strike", "Chanter"),  # presumed
            18_080_000: ("Wave Strike", "Chanter"),
            18_160_000: ("Blessing of Speed", "Chanter"),
            18_170_000: ("Healing Touch", "Chanter"),
            18_190_000: ("Invincibility Mantra", "Chanter"),
            18_230_000: ("Ensnaring Mark", "Chanter"),
            18_240_000: ("Blocking Power", "Chanter"),
            18_250_000: ("Power of the Storm", "Chanter"),
            18_440_000: ("Barrier Spell", "Chanter"),
            18_780_000: ("Earth's Promise", "Chanter"),
        }

        for code, (name, job_class) in default_skills.items():
            self.skills[code] = SkillInfo(code, name, "", job_class)

    def get_skill_info(self, skill_code: int) -> Optional[SkillInfo]:
        """
        Obtém informações de uma skill.

        Args:
            skill_code: Código da skill

        Returns:
            SkillInfo ou None se não encontrado
        """
        # Tenta exato primeiro
        if skill_code in self.skills:
            return self.skills[skill_code]

        # Tenta normalizado (base)
        normalized = skill_code - (skill_code % 10000)
        if normalized in self.skills:
            return self.skills[normalized]

        return None

    def get_skill_name(self, skill_code: int) -> str:
        """
        Obtém nome de uma skill.

        Args:
            skill_code: Código da skill

        Returns:
            Nome da skill ou string genérica se não encontrado
        """
        info = self.get_skill_info(skill_code)
        if info:
            return info.name

        # Fallback: retorna código
        return f"Skill {skill_code}"

    def get_skill_icon(self, skill_code: int) -> str:
        """
        Obtém path do ícone de uma skill.

        Args:
            skill_code: Código da skill

        Returns:
            Path do ícone
        """
        info = self.get_skill_info(skill_code)
        if info:
            return info.icon

        return f"skill_{skill_code}.png"

    def get_skill_class(self, skill_code: int) -> str:
        """
        Obtém classe associada a uma skill.

        Args:
            skill_code: Código da skill

        Returns:
            Nome da classe
        """
        info = self.get_skill_info(skill_code)
        if info:
            return info.job_class

        return "Unknown"

    def add_skill(self, code: int, name: str, icon: str = "", job_class: str = "Unknown"):
        """
        Adiciona uma skill ao lookup (útil para aprendizado dinâmico).

        Args:
            code: Código da skill
            name: Nome da skill
            icon: Path do ícone (opcional)
            job_class: Classe associada (opcional)
        """
        self.skills[code] = SkillInfo(code, name, icon, job_class)

    def export_to_json(self, output_file: Path):
        """
        Exporta skills para arquivo JSON.

        Args:
            output_file: Path do arquivo de saída
        """
        data = {
            str(code): info.to_dict()
            for code, info in self.skills.items()
        }

        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)

        logger.info(f"Exportadas {len(self.skills)} skills para {output_file}")


# Instância global singleton
_skill_lookup_instance: Optional[SkillLookup] = None


def get_skill_lookup() -> SkillLookup:
    """Retorna instância global do SkillLookup (singleton)"""
    global _skill_lookup_instance
    if _skill_lookup_instance is None:
        _skill_lookup_instance = SkillLookup()
    return _skill_lookup_instance
