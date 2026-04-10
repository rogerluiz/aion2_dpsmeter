"""
calculator.py — Agregação de DPS/HPS em tempo real

Usa janelas deslizantes de tempo para calcular DPS/HPS por jogador.
"""

import time
import threading
from collections import defaultdict, deque
from dataclasses import dataclass, field
from typing import Optional, Dict

from packet_parser import CombatEvent


# Janela de tempo para cálculo de DPS (em segundos)
DPS_WINDOW_SECONDS = 10.0


@dataclass
class SkillStats:
    """Estatísticas agregadas de uma skill"""
    skill_code: int
    skill_name: str
    skill_icon: str = ""
    total_damage: int = 0
    hit_count: int = 0
    crit_count: int = 0
    back_count: int = 0
    parry_count: int = 0
    perfect_count: int = 0
    double_count: int = 0
    min_damage: int = 999999
    max_damage: int = 0
    is_dot: bool = False

    @property
    def avg_damage(self) -> float:
        return self.total_damage / self.hit_count if self.hit_count > 0 else 0

    @property
    def crit_rate(self) -> float:
        return (self.crit_count / self.hit_count * 100) if self.hit_count > 0 else 0

    @property
    def back_rate(self) -> float:
        return (self.back_count / self.hit_count * 100) if self.hit_count > 0 else 0

    def to_dict(self) -> dict:
        return {
            "skill_code": self.skill_code,
            "skill_name": self.skill_name,
            "skill_icon": self.skill_icon,
            "total_damage": self.total_damage,
            "hit_count": self.hit_count,
            "crit_count": self.crit_count,
            "crit_rate": round(self.crit_rate, 1),
            "back_count": self.back_count,
            "back_rate": round(self.back_rate, 1),
            "parry_count": self.parry_count,
            "perfect_count": self.perfect_count,
            "double_count": self.double_count,
            "avg_damage": round(self.avg_damage, 1),
            "min_damage": self.min_damage if self.min_damage < 999999 else 0,
            "max_damage": self.max_damage,
            "is_dot": self.is_dot,
        }


# Nomes de jogadores conhecidos (fallback para ID hex)
PLAYER_NAMES: dict[int, str] = {
    0x01: "Gladiator",
    0x02: "Ranger",
    0x03: "Sorcerer",
    0x04: "Cleric",
}


@dataclass
class PlayerStats:
    player_id: int
    name: str
    total_damage: int = 0
    total_heal: int = 0
    total_hits: int = 0
    total_crits: int = 0
    total_misses: int = 0
    current_dps: float = 0.0
    current_hps: float = 0.0
    max_hit: int = 0
    # Classe do jogador
    class_name: str = "Unknown"
    class_icon: str = ""
    # Skills agregadas (skill_code → SkillStats)
    skills: Dict[int, SkillStats] = field(default_factory=dict)
    # Eventos recentes para janela deslizante
    _damage_events: deque = field(default_factory=deque)
    _heal_events: deque = field(default_factory=deque)

    @property
    def crit_rate(self) -> float:
        if self.total_hits == 0:
            return 0.0
        return self.total_crits / self.total_hits

    def to_dict(self) -> dict:
        return {
            "id": self.player_id,
            "name": self.name,
            "class_name": self.class_name,
            "class_icon": self.class_icon,
            "total_damage": self.total_damage,
            "total_heal": self.total_heal,
            "total_hits": self.total_hits,
            "total_crits": self.total_crits,
            "total_misses": self.total_misses,
            "current_dps": round(self.current_dps, 1),
            "current_hps": round(self.current_hps, 1),
            "max_hit": self.max_hit,
            "crit_rate": round(self.crit_rate * 100, 1),
            "skills": [skill.to_dict() for skill in sorted(
                self.skills.values(),
                key=lambda s: s.total_damage,
                reverse=True
            )[:10]],  # Top 10 skills por dano
        }


@dataclass
class CombatSession:
    start_time: float = field(default_factory=time.time)
    end_time: Optional[float] = None
    active: bool = True

    @property
    def duration(self) -> float:
        end = self.end_time or time.time()
        return end - self.start_time


class DPSCalculator:
    """
    Recebe CombatEvents e mantém estatísticas em tempo real por jogador.
    Thread-safe para uso com o servidor WebSocket.
    """

    def __init__(self, window_seconds: float = DPS_WINDOW_SECONDS):
        self.window_seconds = window_seconds
        self._players: dict[int, PlayerStats] = {}
        self._session = CombatSession()
        self._lock = threading.Lock()
        # Histórico de DPS para gráfico de linha (últimos 60 ticks)
        self._dps_history: dict[int, deque] = defaultdict(
            lambda: deque(maxlen=60))

    def process_event(self, event: CombatEvent):
        """Processa um CombatEvent e atualiza as estatísticas."""
        event.timestamp = time.time()

        with self._lock:
            player = self._get_or_create_player(event.attacker_id)

            # Atualizar nome se disponível
            if event.attacker_name and player.name.startswith("Player"):
                player.name = event.attacker_name

            # Atualizar classe se detectada (não sobrescrever se já conhecida)
            if event.attacker_class != "Unknown" and player.class_name == "Unknown":
                player.class_name = event.attacker_class
                player.class_icon = event.attacker_class_icon

            if event.event_type == "damage" and not event.is_miss and not event.is_dodge:
                player.total_damage += event.value
                player.total_hits += 1
                player.max_hit = max(player.max_hit, event.value)
                if event.is_crit:
                    player.total_crits += 1
                player._damage_events.append((event.timestamp, event.value))

                # Atualizar estatísticas de skill
                self._update_skill_stats(player, event)

            elif event.event_type == "heal":
                player.total_heal += event.value
                player._heal_events.append((event.timestamp, event.value))

            elif event.is_miss or event.is_dodge:
                player.total_misses += 1

            self._update_dps(player, event.timestamp)

    def tick(self):
        """
        Deve ser chamado periodicamente (ex: 1x/segundo) para
        atualizar o DPS de jogadores que não receberam novos eventos.
        """
        now = time.time()
        with self._lock:
            for player in self._players.values():
                self._update_dps(player, now)
                self._dps_history[player.player_id].append({
                    "t": round(now - self._session.start_time, 1),
                    "dps": round(player.current_dps, 1),
                    "hps": round(player.current_hps, 1),
                })

    def get_snapshot(self) -> dict:
        """Retorna snapshot atual de todos os jogadores, ordenado por DPS."""
        with self._lock:
            players = sorted(
                self._players.values(),
                key=lambda p: p.total_damage,
                reverse=True
            )
            total_damage = sum(p.total_damage for p in players)

            return {
                "session_duration": round(self._session.duration, 1),
                "total_damage": total_damage,
                "players": [p.to_dict() for p in players],
                "dps_history": {
                    pid: list(hist)
                    for pid, hist in self._dps_history.items()
                },
            }

    def reset(self):
        """Reseta o combate."""
        with self._lock:
            self._players.clear()
            self._dps_history.clear()
            self._session = CombatSession()

    # ─── Internals ────────────────────────────────────────────────────────────

    def _get_or_create_player(self, player_id: int) -> PlayerStats:
        if player_id not in self._players:
            name = PLAYER_NAMES.get(player_id, f"Player_{player_id:02X}")
            self._players[player_id] = PlayerStats(
                player_id=player_id, name=name)
        return self._players[player_id]

    def _update_skill_stats(self, player: PlayerStats, event: CombatEvent):
        """Atualiza estatísticas agregadas de uma skill."""
        skill_code = event.skill_id

        # Criar entrada de skill se não existe
        if skill_code not in player.skills:
            player.skills[skill_code] = SkillStats(
                skill_code=skill_code,
                skill_name=event.skill_name,
                skill_icon=event.skill_icon,
                is_dot=event.is_dot,
            )

        skill = player.skills[skill_code]

        # Atualizar contadores
        skill.total_damage += event.value
        skill.hit_count += 1
        skill.min_damage = min(skill.min_damage, event.value)
        skill.max_damage = max(skill.max_damage, event.value)

        # Flags especiais
        if event.is_crit:
            skill.crit_count += 1
        if event.is_back_attack:
            skill.back_count += 1
        if event.is_parry:
            skill.parry_count += 1
        if event.is_perfect:
            skill.perfect_count += 1
        if event.is_double:
            skill.double_count += 1

    def _update_dps(self, player: PlayerStats, now: float):
        """Remove eventos fora da janela e recalcula DPS/HPS."""
        cutoff = now - self.window_seconds

        # Purge eventos antigos de dano
        while player._damage_events and player._damage_events[0][0] < cutoff:
            player._damage_events.popleft()

        # Purge eventos antigos de cura
        while player._heal_events and player._heal_events[0][0] < cutoff:
            player._heal_events.popleft()

        # DPS = soma da janela / tamanho da janela
        window_damage = sum(v for _, v in player._damage_events)
        window_heal = sum(v for _, v in player._heal_events)
        actual_window = min(self.window_seconds, now -
                            self._session.start_time)

        if actual_window > 0:
            player.current_dps = window_damage / actual_window
            player.current_hps = window_heal / actual_window
        else:
            player.current_dps = 0.0
            player.current_hps = 0.0
