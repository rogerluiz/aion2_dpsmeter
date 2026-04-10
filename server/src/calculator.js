'use strict';
/**
 * calculator.js — Acumula eventos de combate e calcula DPS por jogador.
 */

// ─── Class detection from skill code (port of A2Tools job_class.rs) ──────────
const CLASS_NAMES = {
  11: 'Gladiator',
  12: 'Templar',
  13: 'Assassin',
  14: 'Ranger',
  15: 'Sorcerer',
  16: 'Elementalist',
  17: 'Cleric',
  18: 'Chanter',
};

function detectClass(skillCode) {
  if (!skillCode) return null;
  // Elementalist 6-digit specific ranges
  if (
    (skillCode >= 100510 && skillCode <= 103500) ||
    (skillCode >= 109300 && skillCode <= 109362)
  ) {
    return 'Elementalist';
  }
  // Standard 8-digit player skills (10_000_000..19_999_999)
  if (skillCode >= 10_000_000 && skillCode <= 19_999_999) {
    const prefix = Math.floor(skillCode / 1_000_000);
    return CLASS_NAMES[prefix] || null;
  }
  return null;
}

class DpsCalculator {
  constructor() {
    this._players = {};
    this._startTime = Date.now();
    this._history = {}; // actorId → [{t, dps, hps}]
    this._histInterval = setInterval(() => this._recordHistory(), 1000);
  }

  _recordHistory() {
    const now = Date.now();
    const elapsed = (now - this._startTime) / 1000;
    const DPS_WINDOW_MS = 10000;
    for (const [id, p] of Object.entries(this._players)) {
      p._window = p._window.filter((e) => now - e.t <= DPS_WINDOW_MS);
      const windowDmg = p._window.reduce((s, e) => s + e.dmg, 0);
      const windowSec = Math.min(elapsed, DPS_WINDOW_MS / 1000);
      const dps = windowSec > 0 ? windowDmg / windowSec : 0;
      if (!this._history[id]) this._history[id] = [];
      this._history[id].push({t: elapsed, dps: Math.round(dps), hps: 0});
      // Keep last 300 points (5 min)
      if (this._history[id].length > 300) this._history[id].shift();
    }
  }

  /**
   * @param {{ actorId: number, damage: number, isCrit?: boolean, isDot?: boolean, skillCode?: number }} event
   */
  addEvent(event) {
    const id = event.actorId;
    if (!this._players[id]) {
      this._players[id] = {
        id,
        name: `Player_${id}`,
        class_name: '',
        totalDamage: 0,
        hits: 0,
        crits: 0,
        misses: 0,
        maxHit: 0,
        _window: [],
      };
    }
    const p = this._players[id];
    // Detect class from first resolved skill code
    if (!p.class_name && event.skillCode) {
      const cls = detectClass(event.skillCode);
      if (cls) p.class_name = cls;
    }
    const dmg = event.damage || 0;
    p.totalDamage += dmg;
    p.hits += 1;
    if (event.isCrit) p.crits += 1;
    if (dmg > p.maxHit) p.maxHit = dmg;
    p._window.push({t: Date.now(), dmg});
  }

  /** Retorna snapshot compatível com o WebSocket do frontend Flutter. */
  getSnapshot() {
    const now = Date.now();
    const elapsed = (now - this._startTime) / 1000;
    const DPS_WINDOW_MS = 10000; // 10s rolling window

    const totalDamage = Object.values(this._players).reduce(
      (s, p) => s + p.totalDamage,
      0,
    );

    const players = Object.values(this._players).map((p) => {
      // Trim old window entries
      p._window = p._window.filter((e) => now - e.t <= DPS_WINDOW_MS);
      const windowDmg = p._window.reduce((s, e) => s + e.dmg, 0);
      const windowSec = Math.min(elapsed, DPS_WINDOW_MS / 1000);
      const currentDps = windowSec > 0 ? windowDmg / windowSec : 0;
      const critRate = p.hits > 0 ? p.crits / p.hits : 0;

      return {
        id: p.id,
        name: p.name,
        class_name: p.class_name,
        total_damage: p.totalDamage,
        total_heal: 0,
        total_hits: p.hits,
        total_crits: p.crits,
        total_misses: p.misses,
        current_dps: Math.round(currentDps),
        current_hps: 0,
        max_hit: p.maxHit,
        crit_rate: parseFloat(critRate.toFixed(4)),
      };
    });

    // Ordena por current_dps decrescente
    players.sort((a, b) => b.current_dps - a.current_dps);

    return {
      type: 'snapshot',
      data: {
        session_duration: elapsed,
        total_damage: totalDamage,
        players,
        dps_history: Object.fromEntries(
          Object.entries(this._history).map(([id, pts]) => [id, pts]),
        ),
      },
    };
  }

  /** Update the display name of a player from a nickname packet. */
  setNickname(actorId, nickname) {
    if (!this._players[actorId]) return;
    this._players[actorId].name = nickname;
  }

  reset() {
    this._players = {};
    this._history = {};
    this._startTime = Date.now();
  }
}

module.exports = DpsCalculator;
