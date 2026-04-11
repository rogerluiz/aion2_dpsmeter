'use strict';
/**
 * skill_names.js — AION 2 skill code → name lookup
 * Primary source: skills_en.json (nousx/aion2-dps-meter i18n/skills/en.json, 391 entries)
 * Extras: skills not in en.json (specials, passives, old-style codes)
 */

const _EN = require('./skills_en.json');

// Build map from all authoritative en.json entries (all 391, string → int key)
const SKILL_NAMES = new Map(
  Object.entries(_EN).map(([k, v]) => [parseInt(k, 10), v]),
);

// ── Base-code aliases for variant-only entries in en.json ─────────────────────
// Some skills only appear as ranked variants (e.g. 11800008); add base alias so
// the normalizeSkillCode fallback chain can find them.
const _VARIANT_ALIASES = [
  [11800000, 'Murderous Burst'], // en only has 11800008
  [12730000, 'Punishing Benediction'], // en only has 12730001
  [13800000, 'Determination'], // en only has 13800007
  [14720000, 'Concentrated Fire'], // en only has 14720007
  [14770000, 'Rooting Eye'], // en only has 14770007
  [14780000, 'Melee Fire'], // en only has 14780008
  [14800000, "Hunter's Soul"], // en only has 14800007
  [15320000, 'Delayed Explosion'], // en only has 15320007
  [18800000, "Wind's Promise"], // en only has 18800001
];
for (const [code, name] of _VARIANT_ALIASES) {
  if (!SKILL_NAMES.has(code)) SKILL_NAMES.set(code, name);
}

// ── Skills absent from en.json ────────────────────────────────────────────────
const _EXTRAS = new Map([
  // Gladiator
  [12470000, "Empyrean Lord's Fury"],
  // Ranger specials (not tracked by reference impl)
  [14220000, 'Blessing of the Bow'],
  [14310000, "Baizar's Authority"],
  [14380000, 'Support Fire'],
  // Ranger passives (icons: ICON_RA_SKILL_Passive_XXX)
  [14710000, 'RA Passive 4'],
  [14730000, 'RA Passive 6'],
  [14740000, 'RA Passive 1'],
  [14750000, 'RA Passive 11'],
  [14760000, 'RA Passive 12'],
  [14790000, 'AS Passive 9'],
  // Elementalist legacy codes
  [100510, 'Stone Skin (Ancient Spirit)'],
  [109300, 'Elemental Smash (Ancient Spirit)'],
]);
for (const [code, name] of _EXTRAS) {
  if (!SKILL_NAMES.has(code)) SKILL_NAMES.set(code, name);
}

// ─────────────────────────────────────────────────────────────────────────────

/**
 * @param {number} code
 * @returns {number}
 */
function normalizeSkillCode(code) {
  if (!Number.isInteger(code) || code <= 0) return code;
  if (SKILL_NAMES.has(code)) return code;

  // Skill variants encode level/rank in lower digits; try progressively coarser rounding
  for (const div of [10, 100, 1000, 10000]) {
    const rounded = Math.trunc(code / div) * div;
    if (SKILL_NAMES.has(rounded)) return rounded;
  }

  return code;
}

/**
 * @param {number} code
 * @returns {string}
 */
function getSkillName(code) {
  const normalized = normalizeSkillCode(code);
  return SKILL_NAMES.get(normalized) || `Skill_${normalized}`;
}

module.exports = {getSkillName, normalizeSkillCode, SKILL_NAMES};
