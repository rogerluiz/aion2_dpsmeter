'use strict';
/**
 * packet_parser.js — AION 2 stream parser
 *
 * Implementa o protocolo de framing VarInt do AION 2 com estado por conexão.
 * Fórmula confirmada pelo A2Tools Rust: total_packet_bytes = varint_value - 3
 *
 * Opcodes:
 *   04 38 — Dano direto
 *   05 38 — DoT (Damage over Time)
 */

const {normalizeSkillCode} = require('./skill_names');

// ─── VarInt ─────────────────────────────────────────────────────────────────
function readVarInt(buf, offset) {
  let value = 0,
    shift = 0,
    count = 0;
  while (true) {
    if (offset + count >= buf.length) return {value: -1, length: -1};
    const b = buf[offset + count++] & 0xff;
    value |= (b & 0x7f) << shift;
    if ((b & 0x80) === 0) return {value, length: count};
    shift += 7;
    if (shift >= 32) return {value: -1, length: -1};
  }
}

// ─── Damage parser ─────────────────────────────────────────────────────────
// Port of A2Tools Rust parsing_damage_inner (simplified, confirmed working).
function parseDamage(pkt, oo) {
  try {
    let off = oo + 2; // skip opcode 04 38

    const tv = readVarInt(pkt, off);
    if (tv.length < 0) return null;
    off += tv.length;
    const sv = readVarInt(pkt, off);
    if (sv.length < 0) return null;
    off += sv.length;
    const andRes = sv.value & 0x0f;
    if (andRes < 4 || andRes > 7) return null;
    const fv = readVarInt(pkt, off);
    if (fv.length < 0) return null;
    off += fv.length;
    const av = readVarInt(pkt, off);
    if (av.length < 0 || av.value <= 0) return null;
    if (av.value === tv.value) return null; // Kotlin: skip self-hit (actor == target)
    off += av.length;
    if (off + 4 > pkt.length) return null;
    const rawSkillCode = pkt.readUInt32LE(off);
    off += 4;
    // Skip 7-digit NPC/mob skills (1M–9.9M) — A2Tools Rust parity
    if (rawSkillCode >= 1_000_000 && rawSkillCode <= 9_999_999) return null;
    const skillCode = normalizeSkillCode(rawSkillCode);
    if (off < pkt.length) off++; // skip UID byte
    const dtv = readVarInt(pkt, off);
    if (dtv.length < 0) return null;
    off += dtv.length;
    const isCrit = dtv.value === 3;
    // Special combat flags are in the first byte of the specSz block (andRes 5/6/7 only)
    let flags = 0;
    if (andRes >= 5 && off < pkt.length) {
      flags = pkt[off] & 0xff;
    }
    const specSz = {4: 8, 5: 12, 6: 10, 7: 14}[andRes];
    off += specSz;
    if (off >= pkt.length) return null;
    // unknownInfo → damageInfo (matches Kotlin: unknownInfo, damageInfo, loopInfo after flags block)
    const unknownInfo = readVarInt(pkt, off);
    if (unknownInfo.length < 0) return null;
    off += unknownInfo.length;
    const damageInfo = readVarInt(pkt, off);
    if (damageInfo.length < 0) return null;
    const dmg = damageInfo.value; // always use damageInfo (second varint after flags block)
    if (dmg <= 0 || dmg > 99999999) return null;

    return {
      type: 'damage',
      actorId: av.value,
      targetId: tv.value,
      skillCode,
      damage: dmg,
      isCrit,
      isDot: false,
      isBackAttack: (flags & 0x01) !== 0,
      isParry: (flags & 0x04) !== 0,
      isPerfect: (flags & 0x08) !== 0,
      isDouble: (flags & 0x10) !== 0,
    };
  } catch (_) {
    return null;
  }
}

// ─── DoT parser (0x05 0x38) ───────────────────────────────────────────────────
// Matches Kotlin StreamProcessor.parseDoTPacket structure:
//   [varint target] [skip 1] [varint actor] [varint unknown] [uint32le skillCode/100] [varint damage]
function parseDot(pkt, oo) {
  try {
    let off = oo + 2; // skip opcode 05 38

    const tv = readVarInt(pkt, off);
    if (tv.length < 0 || tv.value <= 0) return null;
    off += tv.length;

    if (off >= pkt.length) return null;
    off += 1; // skip unknown byte after target

    const av = readVarInt(pkt, off);
    if (av.length < 0 || av.value <= 0) return null;
    if (av.value === tv.value) return null; // self-hit → skip
    off += av.length;

    const uv = readVarInt(pkt, off);
    if (uv.length < 0) return null;
    off += uv.length;

    if (off + 4 > pkt.length) return null;
    const rawSkillCode = pkt.readUInt32LE(off);
    const skillCode = normalizeSkillCode(Math.trunc(rawSkillCode / 100));
    off += 4;

    const dv = readVarInt(pkt, off);
    if (dv.length < 0) return null;
    const dmg = dv.value;
    if (dmg <= 0 || dmg > 99999999) return null;

    return {
      type: 'damage',
      actorId: av.value,
      targetId: tv.value,
      skillCode,
      damage: dmg,
      isCrit: false,
      isDot: true,
      isBackAttack: false,
      isParry: false,
      isPerfect: false,
      isDouble: false,
    };
  } catch (_) {
    return null;
  }
}

// ─── Nickname parser ─────────────────────────────────────────────────────────
/**
 * Reads a LEB128 varint ending at pkt[endPos] (last byte has bit7 = 0).
 * Returns { start, length, value } or null.
 */
function readVarIntBackward(pkt, endPos) {
  if (endPos < 0 || endPos >= pkt.length) return null;
  if (pkt[endPos] & 0x80) return null; // not a valid terminal byte
  let start = endPos;
  while (start > 0 && (pkt[start - 1] & 0x80) !== 0) {
    start--;
    if (endPos - start >= 4) return null; // varint too long (>4 bytes)
  }
  let value = 0;
  let shift = 0;
  for (let k = start; k <= endPos; k++) {
    value += (pkt[k] & 0x7f) * Math.pow(2, shift);
    shift += 7;
  }
  return {start, length: endPos - start + 1, value};
}

/**
 * Validates and decodes a UTF-8 nickname from raw bytes.
 * Allows ASCII + CJK (Korean / Chinese) characters via UTF-8.
 */
function tryDecodeNickname(bytes) {
  if (!bytes || bytes.length < 2 || bytes.length > 71) return null;
  // Reject control characters (< 0x20)
  if (bytes.some((b) => b < 0x20)) return null;
  try {
    const s = Buffer.from(bytes).toString('utf8');
    // Reject invalid UTF-8 (replacement char)
    if (s.includes('\uFFFD')) return null;
    // Must start with a letter (ASCII or Korean/CJK), NOT a digit or symbol
    if (!/^[A-Za-z\uAC00-\uD7A3\u1100-\u11FF\u4E00-\u9FFF]/.test(s))
      return null;
    // Only allow letters, digits — no symbols (@, %, ., ], etc.)
    if (!/^[A-Za-z0-9\uAC00-\uD7A3\u1100-\u11FF\u4E00-\u9FFF]+$/.test(s))
      return null;
    // Must contain at least one letter
    if (!/[A-Za-z\uAC00-\uD7A3\u1100-\u11FF\u4E00-\u9FFF]/.test(s)) return null;
    if (s.length < 2) return null;
    return s;
  } catch (_) {
    return null;
  }
}

/**
 * Scan a raw byte buffer for E2/E0 07 anchor patterns and extract nicknames.
 * Mirrors A2Tools scan_for_embedded_04_8d / parsing_nickname (Pattern A).
 * @param {Buffer} buf — raw bytes to scan (TCP segment or partial stream)
 * @param {number} [startAt=0] — byte offset to begin scanning
 * @returns {Array<{actorId:number, name:string}>}
 */
function scanNicknamesInBuffer(buf, startAt = 0) {
  const found = [];
  try {
    for (let i = startAt; i < buf.length - 4; i++) {
      // Pattern A: E2/E0 07 anchor
      if ((buf[i] === 0xe2 || buf[i] === 0xe0) && buf[i + 1] === 0x07) {
        const nameOff = i + 2;
        if (nameOff >= buf.length) continue;
        const nameLen = buf[nameOff];
        if (nameLen < 2 || nameLen > 71 || nameOff + 1 + nameLen > buf.length)
          continue;
        const nameBytes = buf.slice(nameOff + 1, nameOff + 1 + nameLen);
        const name = tryDecodeNickname(nameBytes);
        if (!name) continue;
        // Read actor_id varint going backward from the byte just before the anchor
        for (let vLen = 1; vLen <= 3; vLen++) {
          if (i < vLen) continue;
          const vStart = i - vLen;
          const v = readVarInt(buf, vStart);
          if (v.length === vLen && v.value > 0 && v.value <= 9_999_999) {
            found.push({actorId: v.value, name});
            break;
          }
        }
      }
      // Pattern: 44 36 = player spawn — actor [data...] 07 name_len name
      if (
        buf[i] === 0x44 &&
        buf[i + 1] === 0x36 &&
        i > 0 &&
        buf[i - 1] !== 0x00
      ) {
        const av = readVarInt(buf, i + 2);
        if (av.length <= 0 || av.value < 100 || av.value > 99_999) continue;
        const scanEnd = Math.min(buf.length - 2, i + 2 + av.length + 40);
        for (let j = i + 2 + av.length; j < scanEnd; j++) {
          if (buf[j] === 0x07) {
            const nameLen = buf[j + 1];
            if (nameLen < 2 || nameLen > 71 || j + 2 + nameLen > buf.length)
              continue;
            const nameBytes = buf.slice(j + 2, j + 2 + nameLen);
            const name = tryDecodeNickname(nameBytes);
            if (name) {
              found.push({actorId: av.value, name});
              break;
            }
          }
        }
      }
    }
  } catch (_) {
    /* ignore */
  }
  return found;
}

/**
 * Scans for 0xF8 0x03 loot attribution marker pattern.
 * Matches Kotlin NameResolver.parseLootAttributionActorName():
 *   [...varint(actorId) 0xF8 0x03 nameLen name guildNameLen guildName ...]
 * actorId must be 2-byte varint, range 100..99999.
 */
function scanLootAttributionNames(buf) {
  const found = [];
  try {
    for (let i = 2; i < buf.length - 4; i++) {
      if (buf[i] !== 0xf8 || buf[i + 1] !== 0x03) continue;
      const actorOff = i - 2;
      const actorInfo = readVarInt(buf, actorOff);
      // Kotlin: length must be 2 AND it must end right before the marker
      if (actorInfo.length !== 2 || actorOff + actorInfo.length !== i) continue;
      if (actorInfo.value < 100 || actorInfo.value > 99999) continue;
      const lenIdx = i + 2;
      if (lenIdx >= buf.length) continue;
      const nameLength = buf[lenIdx];
      if (nameLength < 2 || nameLength > 71) continue;
      const nameStart = lenIdx + 1;
      const nameEnd = nameStart + nameLength;
      if (nameEnd > buf.length) continue;
      const name = tryDecodeNickname(buf.slice(nameStart, nameEnd));
      if (name) found.push({actorId: actorInfo.value, name});
    }
  } catch (_) {
    /* ignore */
  }
  return found;
}

/**
 * Kotlin-style 0x04 0x8D nickname scan: tries each offset in a 24-byte
 * window after the opcode, looking for [varint actorId][1-byte nameLen][name].
 * Matches NameResolver.parseNickname() from the reference implementation.
 */
function parseNickname04_8D(pkt, oo) {
  if (pkt[oo] !== 0x04 || pkt[oo + 1] !== 0x8d) return null;
  const searchStart = oo + 2;
  const searchEnd = Math.min(pkt.length - 2, searchStart + 24);
  for (let c = searchStart; c <= searchEnd; c++) {
    const playerInfo = readVarInt(pkt, c);
    if (playerInfo.length <= 0 || playerInfo.value <= 0) continue;
    const nameLenOff = c + playerInfo.length;
    if (nameLenOff >= pkt.length) continue;
    const nickLen = pkt[nameLenOff];
    if (nickLen === 0 || nickLen > 72) continue;
    const nameEnd = nameLenOff + 1 + nickLen;
    if (nameEnd > pkt.length) continue;
    const name = tryDecodeNickname(pkt.slice(nameLenOff + 1, nameEnd));
    if (name) return {actorId: playerInfo.value, name};
  }
  return null;
}

/**
 * Scans a buffer for 0x36 anchor + varint actorId (>=1000) + 0x07 + name.
 * Matches Kotlin NameResolver.parseEntityNameBindingRules().
 * Returns array of {actorId, name} found.
 */
function scanEntityNameBindings(buf) {
  const found = [];
  try {
    for (let i = 0; i < buf.length - 2; i++) {
      if (buf[i] !== 0x36) continue;
      const actorInfo = readVarInt(buf, i + 1);
      if (actorInfo.length <= 0 || actorInfo.value < 1000) continue;
      const searchFrom = i + 1 + actorInfo.length;
      // Use a large window (256 bytes) — player spawn packets can be large
      const searchTo = Math.min(buf.length - 2, searchFrom + 256);
      for (let j = searchFrom; j < searchTo; j++) {
        if (buf[j] !== 0x07) continue;
        const nameLen = buf[j + 1];
        if (nameLen < 1 || nameLen > 71 || j + 2 + nameLen > buf.length)
          continue;
        const name = tryDecodeNickname(buf.slice(j + 2, j + 2 + nameLen));
        if (name) {
          found.push({actorId: actorInfo.value, name});
          break;
        }
      }
    }
  } catch (_) {
    /* ignore */
  }
  return found;
}

/**
 * Scans a 04 8D packet for nickname patterns.
 * Tries Kotlin-style window scan first, then falls back to E2/E0 07 pattern.
 */
function parseNickname(pkt, oo) {
  const kt = parseNickname04_8D(pkt, oo);
  if (kt) return {type: 'nickname', ...kt};
  const hits = scanNicknamesInBuffer(pkt, oo);
  if (hits.length > 0) return {type: 'nickname', ...hits[0]};
  return null;
}

function parseOwnNicknamePacket(pkt, oo) {
  try {
    let off = oo;
    if (pkt[off] !== 0x33 || pkt[off + 1] !== 0x36) return null;
    off += 2;

    const actor = readVarInt(pkt, off);
    if (actor.length <= 0 || actor.value < 100) return null;
    off += actor.length;

    // Kotlin parity: own nickname packet scans only a short 10-byte window
    // for the 0x07 anchor, then reads the name length as VarInt.
    const splitter = pkt
      .slice(off, Math.min(pkt.length, off + 10))
      .indexOf(0x07);
    if (splitter < 0) return null;
    off += splitter + 1;

    const nameLenInfo = readVarInt(pkt, off);
    if (nameLenInfo.length <= 0) return null;
    off += nameLenInfo.length;

    if (nameLenInfo.value < 1 || nameLenInfo.value > 71) return null;
    if (pkt.length < off + nameLenInfo.value) return null;
    const name = tryDecodeNickname(pkt.slice(off, off + nameLenInfo.value));
    if (!name) return null;

    return {type: 'nickname', actorId: actor.value, name};
  } catch (_) {
    return null;
  }
}

function parseSpawnNicknamePacket(pkt, oo) {
  try {
    let off = oo;
    if (pkt[off] !== 0x44 || pkt[off + 1] !== 0x36) return null;
    off += 2;

    const actor = readVarInt(pkt, off);
    if (actor.length <= 0 || actor.value < 100) return null;
    off += actor.length;

    const unknown1 = readVarInt(pkt, off);
    if (unknown1.length <= 0) return null;
    off += unknown1.length;

    const unknown2 = readVarInt(pkt, off);
    if (unknown2.length <= 0) return null;
    off += unknown2.length;

    if (pkt.length - off <= 2) return null;
    off += 1;
    const base = off;

    for (let i = 0; i < 5; i++) {
      off = base + i;
      if (pkt.length <= off) continue;

      const nameLen = readVarInt(pkt, off);
      if (nameLen.length <= 0 || nameLen.value < 1 || nameLen.value > 71)
        continue;
      off += nameLen.length;

      if (pkt.length < off + nameLen.value) continue;
      const name = tryDecodeNickname(pkt.slice(off, off + nameLen.value));
      if (name) {
        return {type: 'nickname', actorId: actor.value, name};
      }
    }
  } catch (_) {
    return null;
  }

  return null;
}

// ─── StreamParser ──────────────────────────────────────────────────────────
/**
 * Stateful per-connection stream parser.
 * Call consume(connKey, bytes) on each TCP payload received.
 */
class StreamParser {
  constructor() {
    this._streams = new Map(); // connKey → Buffer
  }

  /**
   * Feed raw game-stream bytes for a connection.
   * @param {string} connKey — e.g. "127.0.0.1:52921"
   * @param {Buffer} bytes
   * @returns {Array<Object>} parsed combat events
   */
  consume(connKey, bytes) {
    const events = [];
    let buf = this._streams.get(connKey) || Buffer.alloc(0);
    buf = Buffer.concat([buf, bytes]);
    let offset = 0;

    while (offset < buf.length) {
      // Skip zero padding (AION 2 quirk)
      if (buf[offset] === 0x00) {
        offset++;
        continue;
      }

      const vi = readVarInt(buf, offset);
      if (vi.length <= 0 || vi.value <= 0) {
        if (offset + 5 > buf.length) break;
        offset++;
        continue;
      }

      const total = vi.value - 3; // AION 2 size formula
      if (total <= 0 || total > 65535) {
        offset++;
        continue;
      }

      if (offset + total > buf.length) {
        // Fragment: anti-stall: if total is unreasonably large, resync
        if (total > 16384) {
          offset++;
          continue;
        }
        break; // legitimately fragmented, wait for more data
      }

      const pkt = buf.slice(offset, offset + total);
      const oo = vi.length; // opcode starts right after VarInt in the packet

      if (oo + 2 <= pkt.length) {
        const op0 = pkt[oo],
          op1 = pkt[oo + 1];

        // FF FF = LZ4 compressed bundle (skip for now - no lz4 dep)
        if (op0 === 0xff && op1 === 0xff) {
          // bundle_size = total + 1 (Rust definition)
          const bundleConsumed = total + 1;
          offset +=
            offset + bundleConsumed <= buf.length ? bundleConsumed : total;
          continue;
        }

        if (op0 === 0x04 && op1 === 0x38) {
          const ev = parseDamage(pkt, oo);
          if (ev) events.push(ev);
        } else if (op0 === 0x05 && op1 === 0x38) {
          // DoT — different structure from damage (Kotlin: parseDoTPacket)
          const ev = parseDot(pkt, oo);
          if (ev) events.push(ev);
        } else if (op0 === 0x04 && op1 === 0x8d) {
          // Nickname packet — emit all found nicknames (Kotlin style: window scan + E2/E0)
          const kt = parseNickname04_8D(pkt, oo);
          if (kt) {
            events.push({type: 'nickname', ...kt});
          } else {
            scanNicknamesInBuffer(pkt, oo).forEach((h) =>
              events.push({type: 'nickname', ...h}),
            );
          }
        } else if (op0 === 0x33 && op1 === 0x36) {
          const ev = parseOwnNicknamePacket(pkt, oo);
          if (ev) events.push(ev);
        } else if (op0 === 0x44 && op1 === 0x36) {
          const ev = parseSpawnNicknamePacket(pkt, oo);
          if (ev) {
            events.push(ev);
          } else {
            const hits = scanNicknamesInBuffer(pkt, oo);
            hits.forEach((h) => events.push({type: 'nickname', ...h}));
          }
        }
      }

      offset += total;
    }

    this._streams.set(connKey, buf.slice(offset));

    // Raw scan of the new TCP segment for nickname patterns.
    // Catches names embedded in compressed bundles or non-framed positions.
    const allRaw = [
      ...scanNicknamesInBuffer(bytes),
      ...scanEntityNameBindings(bytes),
      ...scanLootAttributionNames(bytes),
    ];
    allRaw.forEach((h) => {
      if (
        !events.some((e) => e.type === 'nickname' && e.actorId === h.actorId)
      ) {
        events.push({type: 'nickname', ...h});
      }
    });

    return events;
  }

  /** Reset state for one connection or all. */
  reset(connKey) {
    if (connKey) this._streams.delete(connKey);
    else this._streams.clear();
  }
}

module.exports = {StreamParser, readVarInt};
