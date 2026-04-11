'use strict';
/**
 * calculator.js - Acumula eventos de combate e calcula DPS por jogador.
 */

const EventEmitter = require('events');
const {getSkillName} = require('./skill_names');

const RECENT_TARGET_WINDOW_MS = 15000;

// --- Class detection from skill code (port of A2Tools job_class.rs) ----------
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
  if (
    (skillCode >= 100510 && skillCode <= 103500) ||
    (skillCode >= 109300 && skillCode <= 109362)
  ) {
    return 'Elementalist';
  }
  if (skillCode >= 10_000_000 && skillCode <= 19_999_999) {
    const prefix = Math.floor(skillCode / 1_000_000);
    return CLASS_NAMES[prefix] || null;
  }
  return null;
}

function isResolvedPlayer(player) {
  return player.class_name !== '';
}

class DpsCalculator extends EventEmitter {
  constructor() {
    super();
    this._players = {};
    this._nicknameCache = {}; // actorId -> name (pre-cache before first damage)
    this._startTime = Date.now();
    this._history = {}; // actorId -> [{t, dps, hps}]
    this._histInterval = setInterval(() => this._recordHistory(), 1000);
  }

  _recordHistory() {
    const now = Date.now();
    const elapsed = (now - this._startTime) / 1000;
    for (const [id, p] of Object.entries(this._players)) {
      const encounterStart = p._firstHit || now;
      const encounterSec = Math.max((now - encounterStart) / 1000, 0.1);
      const dps = p.totalDamage / encounterSec;
      if (!this._history[id]) this._history[id] = [];
      this._history[id].push({
        t: Math.round(elapsed),
        dps: Math.round(dps),
        hps: 0,
      });
      if (this._history[id].length > 300) this._history[id].shift();
    }
  }

  /**
   * @param {{ actorId, targetId, damage, isCrit?, isDot?, skillCode?,
   *           isBackAttack?, isParry?, isPerfect?, isDouble? }} event
   */
  addEvent(event) {
    const id = event.actorId;
    if (!this._players[id]) {
      this._players[id] = {
        id,
        name: this._nicknameCache[id] || `Player_${id}`,
        class_name: '',
        totalDamage: 0,
        hits: 0,
        crits: 0,
        misses: 0,
        backAttacks: 0,
        perfects: 0,
        doubles: 0,
        parries: 0,
        maxHit: 0,
        _window: [], // [{t, dmg, targetId}]
        _lastEventAt: Date.now(),
        _firstHit: Date.now(),
        _targetDmg: {}, // {targetId: totalDmg}
        _targetHits: {}, // {targetId: hitCount}
        _targetFirstHit: {}, // {targetId: ms timestamp}
        skills: {}, // skillCode -> SkillStats
      };
    }
    const p = this._players[id];

    // Detect class from first resolved skill code
    if (!p.class_name && event.skillCode) {
      const cls = detectClass(event.skillCode);
      if (cls) p.class_name = cls;
    }

    const dmg = event.damage || 0;
    const tId = event.targetId;
    p.totalDamage += dmg;
    p.hits += 1;
    if (event.isCrit) p.crits += 1;
    if (event.isBackAttack) p.backAttacks += 1;
    if (event.isPerfect) p.perfects += 1;
    if (event.isDouble) p.doubles += 1;
    if (event.isParry) p.parries += 1;
    if (dmg > p.maxHit) p.maxHit = dmg;
    p._lastEventAt = Date.now();
    p._window.push({t: p._lastEventAt, dmg, targetId: tId});
    p._window = p._window.filter((e) => p._lastEventAt - e.t <= RECENT_TARGET_WINDOW_MS);

    // Per-target totals (for 'target' filter mode)
    if (tId) {
      p._targetDmg[tId] = (p._targetDmg[tId] || 0) + dmg;
      p._targetHits[tId] = (p._targetHits[tId] || 0) + 1;
      if (!p._targetFirstHit[tId]) p._targetFirstHit[tId] = Date.now();
    }

    // Per-skill tracking
    if (event.skillCode) {
      const sc = event.skillCode;
      if (!p.skills[sc]) {
        p.skills[sc] = {
          code: sc,
          name: getSkillName(sc),
          hits: 0,
          crits: 0,
          totalDmg: 0,
          maxDmg: 0,
        };
      }
      const sk = p.skills[sc];
      sk.hits += 1;
      if (event.isCrit) sk.crits += 1;
      sk.totalDmg += dmg;
      if (dmg > sk.maxDmg) sk.maxDmg = dmg;
    }
  }

  /**
   * Returns the targetId most hit across all players (for auto-target detection).
   */
  getTopTarget() {
    const now = Date.now();
    const counts = {};
    const damages = {};
    for (const p of Object.values(this._players)) {
      for (const ev of p._window) {
        if (!ev.targetId || now - ev.t > RECENT_TARGET_WINDOW_MS) continue;
        counts[ev.targetId] = (counts[ev.targetId] || 0) + 1;
        damages[ev.targetId] = (damages[ev.targetId] || 0) + ev.dmg;
      }
    }
    const entries = Object.entries(counts);
    if (!entries.length) return null;
    return Number(
      entries.sort((a, b) => {
        const cnt = b[1] - a[1];
        if (cnt !== 0) return cnt;
        return (damages[b[0]] || 0) - (damages[a[0]] || 0);
      })[0][0],
    );
  }

  /**
   * Returns snapshot filtered by filterMode.
   * @param {{ filterMode?: 'all'|'party'|'target', filterTargetId?: number|null }} options
   */
  getSnapshot(options = {}) {
    const {filterMode = 'all', filterTargetId = null} = options;
    const now = Date.now();
    const elapsed = (now - this._startTime) / 1000;

    // Auto-detect top target when mode is 'target'
    const activeTarget =
      filterMode === 'target' ? filterTargetId || this.getTopTarget() : null;

    let allPlayers = Object.values(this._players);

    // 'party' mode: prefer real players by detected class or resolved nickname.
    // This avoids hiding party members before their first class-resolving skill.
    if (filterMode === 'party') {
      allPlayers = allPlayers.filter((p) => isResolvedPlayer(p));
    }

    const players = allPlayers
      .map((p) => {
        let totalDmg = p.totalDamage;
        let totalHits = p.hits;
        let encounterStart = p._firstHit || now;

        if (activeTarget) {
          totalDmg = p._targetDmg[activeTarget] || 0;
          totalHits = p._targetHits[activeTarget] || 0;
          if (totalDmg === 0) return null; // skip actors that never hit this target
          encounterStart = p._targetFirstHit[activeTarget] || now;
        }

        const encounterSec = Math.max((now - encounterStart) / 1000, 0.1);
        const currentDps = totalDmg / encounterSec;
        const critRate = p.hits > 0 ? p.crits / p.hits : 0;

        const skills = Object.values(p.skills)
          .sort((a, b) => b.totalDmg - a.totalDmg)
          .map((sk) => ({
            code: sk.code,
            name: sk.name,
            hits: sk.hits,
            crits: sk.crits,
            total_dmg: sk.totalDmg,
            max_dmg: sk.maxDmg,
            crit_rate:
              sk.hits > 0 ? parseFloat((sk.crits / sk.hits).toFixed(4)) : 0,
          }));

        return {
          id: p.id,
          name: p.name,
          class_name: p.class_name,
          total_damage: totalDmg,
          total_heal: 0,
          total_hits: totalHits,
          total_crits: p.crits,
          total_misses: p.misses,
          back_attacks: p.backAttacks,
          perfects: p.perfects,
          doubles: p.doubles,
          parries: p.parries,
          current_dps: Math.round(currentDps),
          current_hps: 0,
          max_hit: p.maxHit,
          crit_rate: parseFloat(critRate.toFixed(4)),
          skills,
        };
      })
      .filter(Boolean);

    players.sort((a, b) => b.total_damage - a.total_damage);

    const totalDamage = players.reduce((s, p) => s + p.total_damage, 0);

    return {
      type: 'snapshot',
      data: {
        session_duration: elapsed,
        total_damage: totalDamage,
        filter_mode: filterMode,
        filter_target_id: activeTarget,
        players,
        dps_history: Object.fromEntries(
          Object.entries(this._history).map(([id, pts]) => [id, pts]),
        ),
      },
    };
  }

  /**
   * Update or pre-cache the display name of a player.
   * AION 2 uses two separate IDs: a display/entity ID (in nickname packets)
   * and a combat session ID (in damage packets). When a nickname arrives for
   * an actorId not seen in combat, we auto-alias it to any unnamed combat
   * player — this bridges the dual-ID gap for solo play.
   */
  setNickname(actorId, nickname, className = null) {
    this._nicknameCache[actorId] = nickname;
    if (this._players[actorId]) {
      // Direct match: combat ID == display ID
      this._players[actorId].name = nickname;
      if (!this._players[actorId].class_name && className) {
        this._players[actorId].class_name = className;
      }
      this.emit('nameUpdated', actorId);
      return;
    }

    // Auto-alias: find combat players still using the default name
    const unnamed = Object.values(this._players).filter((p) =>
      p.name.startsWith('Player_'),
    );
    if (unnamed.length === 1) {
      // Only one unnamed combat player → assume this nickname is theirs
      unnamed[0].name = nickname;
      if (!unnamed[0].class_name && className) {
        unnamed[0].class_name = className;
      }
      this._nicknameCache[unnamed[0].id] = nickname;
      this.emit('nameUpdated', unnamed[0].id);
    }
  }

  reset() {
    this._players = {};
    this._nicknameCache = {};
    this._history = {};
    this._startTime = Date.now();
  }
}

module.exports = DpsCalculator;
