'use strict';
/**
 * discover_icons.js
 * Probes PlayNC CDN to build a COMPLETE skill_icon_map.json.
 *
 * Strategy:
 *  1. For each class, probe ICON_{PREFIX}_SKILL_001 … ICON_{PREFIX}_SKILL_100
 *     and ICON_{PREFIX}_SKILL_Passive_001 … _030  to discover every valid URL.
 *  2. Match normal skills to codes via formula:
 *       iconNum = (skillCode - classBase) / 10000
 *  3. Match passive skills to codes by sorted order of passive codes vs icons.
 *  4. Write frontend/assets/backend/skill_icon_map.json
 *
 * Run from project root:  node scripts/discover_icons.js
 */

const https = require('https');
const fs = require('fs');
const path = require('path');

const CDN = 'https://assets.playnccdn.com/static-aion2-gamedata/resources';

const CLASS_MAP = {
  11: 'GL',
  12: 'TE',
  13: 'AS',
  14: 'RA',
  15: 'SO',
  16: 'EL',
  17: 'CL',
  18: 'CH',
};

const CONCURRENCY = 8; // parallel HEAD requests

// ─── HEAD probe ────────────────────────────────────────────────────────────────
function probe(url) {
  return new Promise((resolve) => {
    const req = https.request(url, {method: 'HEAD'}, (res) => {
      resolve(res.statusCode === 200 ? url : null);
    });
    req.on('error', () => resolve(null));
    req.setTimeout(6000, () => {
      req.destroy();
      resolve(null);
    });
    req.end();
  });
}

// Run promises in batches of `size`
async function batch(tasks, size) {
  const results = [];
  for (let i = 0; i < tasks.length; i += size) {
    const slice = await Promise.all(tasks.slice(i, i + size).map((fn) => fn()));
    results.push(...slice);
  }
  return results;
}

// ─── Discover all valid URLs for a class ──────────────────────────────────────
async function discoverClass(prefix) {
  const normal = [];
  const passive = [];

  // Normal: 001 – 100
  for (let n = 1; n <= 100; n++) {
    const num = n.toString().padStart(3, '0');
    normal.push(() => probe(`${CDN}/ICON_${prefix}_SKILL_${num}.png`));
  }
  // Passive: 001 – 030
  for (let n = 1; n <= 30; n++) {
    const num = n.toString().padStart(3, '0');
    passive.push(() => probe(`${CDN}/ICON_${prefix}_SKILL_Passive_${num}.png`));
  }

  process.stdout.write(`  ${prefix} normal ...`);
  const normalResults = (await batch(normal, CONCURRENCY)).filter(Boolean);
  process.stdout.write(` ${normalResults.length} icons | passive ...`);
  const passiveResults = (await batch(passive, CONCURRENCY)).filter(Boolean);
  console.log(` ${passiveResults.length} passives`);

  return {normal: normalResults, passive: passiveResults};
}

// ─── Discover CO (Common) icons ────────────────────────────────────────────────
async function discoverCO() {
  const tasks = [];
  for (let n = 1; n <= 20; n++) {
    const num = n.toString().padStart(3, '0');
    tasks.push(() => probe(`${CDN}/ICON_CO_SKILL_${num}.png`));
  }
  process.stdout.write('  CO normal ...');
  const results = (await batch(tasks, CONCURRENCY)).filter(Boolean);
  console.log(` ${results.length} icons`);
  return results;
}

// ─── Match discovered URLs to skill codes ─────────────────────────────────────
function buildClassMap(classDigit, prefix, discovered, skillCodes, existing) {
  const result = {};
  const classBase = classDigit * 1_000_000;

  const normalCodes = skillCodes.filter((c) => {
    const part = (c - classBase) / 10_000;
    return part >= 1 && part <= 69;
  });
  const passiveCodes = skillCodes.filter((c) => {
    const part = (c - classBase) / 10_000;
    return part >= 70;
  });

  // ── Normal skills: formula + nearest-available fallback ─────────────────────
  // Build a set of taken URLs to avoid double-assigning
  const takenNormal = new Set(Object.values(existing));

  // First pass: exact formula matches
  const unmatched = [];
  for (const code of normalCodes) {
    const part = (code - classBase) / 10_000;
    const iconNum = part.toString().padStart(3, '0');
    const url = `${CDN}/ICON_${prefix}_SKILL_${iconNum}.png`;
    if (discovered.normal.includes(url)) {
      result[code.toString()] = url;
      takenNormal.add(url);
    } else {
      unmatched.push(code);
    }
  }

  // Second pass: try ±5 for unmatched
  const availableNormal = discovered.normal.filter((u) => !takenNormal.has(u));
  for (const code of unmatched) {
    const part = (code - classBase) / 10_000;
    let best = null;
    let bestDist = 6;
    for (const url of availableNormal) {
      const m = url.match(/_SKILL_(\d+)\.png$/);
      if (!m) continue;
      const dist = Math.abs(parseInt(m[1]) - part);
      if (dist < bestDist) {
        bestDist = dist;
        best = url;
      }
    }
    if (best) {
      result[code.toString()] = best;
      takenNormal.delete(best);
      availableNormal.splice(availableNormal.indexOf(best), 1);
    }
  }

  // ── Passive skills: map sorted passive codes → sorted discovered passive URLs ─
  const sortedPassiveCodes = [...passiveCodes].sort((a, b) => a - b);
  const sortedPassiveUrls = [...discovered.passive].sort();
  for (
    let i = 0;
    i < sortedPassiveCodes.length && i < sortedPassiveUrls.length;
    i++
  ) {
    result[sortedPassiveCodes[i].toString()] = sortedPassiveUrls[i];
  }

  return result;
}

// ─── Main ─────────────────────────────────────────────────────────────────────
(async () => {
  const skillsPath = path.join(__dirname, '../server/src/skills_en.json');
  const existingPath = path.join(
    __dirname,
    '../frontend/assets/backend/skill_icon_map.json',
  );
  const outPath = path.join(
    __dirname,
    '../frontend/assets/backend/skill_icon_map.json',
  );

  if (!fs.existsSync(skillsPath)) {
    console.error('skills_en.json not found at', skillsPath);
    process.exit(1);
  }

  const skillsEn = JSON.parse(fs.readFileSync(skillsPath, 'utf8'));
  const existing = fs.existsSync(existingPath)
    ? JSON.parse(fs.readFileSync(existingPath, 'utf8'))
    : {};

  // All known skill codes (base codes from en.json, 8-digit)
  const allCodes = Object.keys(skillsEn)
    .map(Number)
    .filter((c) => c > 1_000_000);

  const finalMap = {};

  for (const [classDigit, prefix] of Object.entries(CLASS_MAP)) {
    const cd = parseInt(classDigit);
    console.log(`\nDiscovering ${prefix} (class ${cd})...`);
    const discovered = await discoverClass(prefix);

    const classCodes = allCodes.filter((c) => Math.floor(c / 1_000_000) === cd);
    console.log(`  Skill codes in class: ${classCodes.length}`);

    const mapped = buildClassMap(cd, prefix, discovered, classCodes, existing);
    Object.assign(finalMap, mapped);
    console.log(`  Mapped: ${Object.keys(mapped).length}`);
  }

  // CO (Common) — map to known common skill codes
  console.log('\nDiscovering CO (Common)...');
  const coUrls = await discoverCO();
  const coCodes = allCodes.filter((c) => {
    // Common skills: codes like 14260000, 14700000, or sub-1M codes
    const part = (c - Math.floor(c / 1_000_000) * 1_000_000) / 10_000;
    return false; // Will handle via existing map
  });
  // Carry over existing CO entries
  for (const [code, url] of Object.entries(existing)) {
    if (url.includes('ICON_CO_')) finalMap[code] = url;
  }

  // Merge: preserve existing entries where new map has no entry
  for (const [code, url] of Object.entries(existing)) {
    if (!finalMap[code]) finalMap[code] = url;
  }

  const sorted = Object.fromEntries(
    Object.entries(finalMap).sort(([a], [b]) => parseInt(a) - parseInt(b)),
  );

  fs.writeFileSync(outPath, JSON.stringify(sorted, null, 2));
  console.log(
    `\n✓ skill_icon_map.json written: ${Object.keys(sorted).length} entries`,
  );
  console.log(`  Path: ${outPath}`);
})();
