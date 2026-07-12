// Minimal protobuf wire-format reader — only what GTFS-RT decoding needs.
// Values used (time ~1.78e9, direction_id, stop_sequence) are all < 2^53,
// so varints are decoded into JS numbers via multiplication (safe past 32 bits).

export class Reader {
  private buf: Uint8Array;
  private pos = 0;
  constructor(buf: Uint8Array) { this.buf = buf; }

  eof(): boolean { return this.pos >= this.buf.length; }

  varint(): number {
    let result = 0;
    let shift = 0;
    for (;;) {
      const b = this.buf[this.pos++];
      result += (b & 0x7f) * Math.pow(2, shift);
      if ((b & 0x80) === 0) break;
      shift += 7;
    }
    return result;
  }

  tag(): { field: number; wire: number } {
    const t = this.varint();
    return { field: Math.floor(t / 8), wire: t % 8 };
  }

  bytes(): Uint8Array {
    const len = this.varint();
    const out = this.buf.subarray(this.pos, this.pos + len);
    this.pos += len;
    return out;
  }

  string(): string {
    return new TextDecoder().decode(this.bytes());
  }

  skip(wire: number): void {
    if (wire === 0) this.varint();
    else if (wire === 2) { const n = this.varint(); this.pos += n; }
    else if (wire === 1) this.pos += 8;
    else if (wire === 5) this.pos += 4;
    else throw new Error(`unsupported wire type ${wire}`);
  }
}

// --- Test-only encoders (kept here so both source and tests share them) ---
export function writeVarint(n: number): number[] {
  const out: number[] = [];
  let v = n;
  for (;;) {
    const byte = v % 128;
    v = Math.floor(v / 128);
    if (v > 0) out.push(byte | 0x80);
    else { out.push(byte); break; }
  }
  return out;
}

export function writeField(field: number, wire: number, payload: number[]): number[] {
  return [...writeVarint(field * 8 + wire), ...payload];
}

export function writeLenField(field: number, payload: number[]): number[] {
  return [...writeVarint(field * 8 + 2), ...writeVarint(payload.length), ...payload];
}

export function writeStringField(field: number, s: string): number[] {
  return writeLenField(field, [...new TextEncoder().encode(s)]);
}
