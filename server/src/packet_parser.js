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
    if (av.length < 0 || av.value < 100) return null;
    off += av.length;
    if (off + 4 > pkt.length) return null;
    const skillCode = pkt.readUInt32LE(off);
    off += 4;
    // Skip 7-digit NPC/mob skills (1M–9.9M) — A2Tools Rust parity
    if (skillCode >= 1_000_000 && skillCode <= 9_999_999) return null;
    if (off < pkt.length) off++; // skip UID byte
    const dtv = readVarInt(pkt, off);
    if (dtv.length < 0) return null;
    off += dtv.length;
    const isCrit = dtv.value === 3;
    const specSz = {4: 8, 5: 12, 6: 10, 7: 14}[andRes];
    off += specSz;
    if (off >= pkt.length) return null;
    const first = readVarInt(pkt, off);
    if (first.length < 0) return null;
    off += first.length;
    const second = readVarInt(pkt, off);
    if (second.length < 0) return null;
    const dmg = second.value <= 25 ? first.value : second.value;
    if (dmg <= 0 || dmg > 99999999) return null;

    return {
      type: 'damage',
      actorId: av.value,
      targetId: tv.value,
      skillCode,
      damage: dmg,
      isCrit,
      isDot: false,
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
  if (!bytes || bytes.length < 2 || bytes.length > 36) return null;
  // Must not contain control characters (< 0x20)
  if (bytes.some((b) => b < 0x20)) return null;
  try {
    const s = bytes.toString('utf8');
    // Must start with an alphanumeric or non-ASCII (CJK) character
    if (!/^[\w\u00C0-\uFFFF]/.test(s)) return null;
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
        if (nameLen < 2 || nameLen > 36 || nameOff + 1 + nameLen > buf.length)
          continue;
        const nameBytes = buf.slice(nameOff + 1, nameOff + 1 + nameLen);
        const name = tryDecodeNickname(nameBytes);
        if (!name) continue;
        // Read actor_id varint going backward from the byte just before the anchor
        for (let vLen = 1; vLen <= 3; vLen++) {
          if (i < vLen) continue;
          const vStart = i - vLen;
          const v = readVarInt(buf, vStart);
          if (v.length === vLen && v.value >= 100 && v.value <= 9_999_999) {
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
            if (nameLen < 2 || nameLen > 36 || j + 2 + nameLen > buf.length)
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
 * Scans a 04 8D packet for nickname patterns.
 * Also used inside the consume() loop for framed 04 8D packets.
 */
function parseNickname(pkt, oo) {
  const hits = scanNicknamesInBuffer(pkt, oo);
  if (hits.length > 0) return {type: 'nickname', ...hits[0]};
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
          // DoT — same structure as damage
          const ev = parseDamage(pkt, oo);
          if (ev) events.push({...ev, isDot: true});
        } else if (op0 === 0x04 && op1 === 0x8d) {
          // Nickname packet — scan for E2/E0 07 anchor pattern
          const ev = parseNickname(pkt, oo);
          if (ev) events.push(ev);
        } else if (op0 === 0x44 && op1 === 0x36) {
          // Player spawn — extract name from 07 anchor within 40 bytes
          const hits = scanNicknamesInBuffer(pkt, oo);
          hits.forEach((h) => events.push({type: 'nickname', ...h}));
        }
      }

      offset += total;
    }

    this._streams.set(connKey, buf.slice(offset));

    // Raw scan of the new TCP segment for nickname patterns (mirrors Rust scan_for_embedded_04_8d)
    // This catches names embedded in compressed bundles or non-framed positions
    const rawNicknames = scanNicknamesInBuffer(bytes);
    rawNicknames.forEach((h) => {
      // Deduplicate: only emit if not already found via framed parsing
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
