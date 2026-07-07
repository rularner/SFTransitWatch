import { describe, it, expect } from "vitest";
import { Reader, writeVarint, writeStringField, writeField, writeLenField } from "../../src/gtfsrt/protobuf";

describe("protobuf Reader", () => {
  it("round-trips a varint", () => {
    const r = new Reader(new Uint8Array(writeVarint(1783321088)));
    expect(r.varint()).toBe(1783321088);
  });

  it("reads a tag into field number and wire type", () => {
    // field 2, wire 2 => tag = (2<<3)|2 = 18
    const r = new Reader(new Uint8Array(writeVarint(18)));
    expect(r.tag()).toEqual({ field: 2, wire: 2 });
  });

  it("reads a length-delimited string field", () => {
    const bytes = writeStringField(2, "16393");
    const r = new Reader(new Uint8Array(bytes));
    const t = r.tag();
    expect(t).toEqual({ field: 2, wire: 2 });
    expect(r.string()).toBe("16393");
    expect(r.eof()).toBe(true);
  });

  it("skips unknown fields by wire type", () => {
    // varint field 1 = 5, then string field 2 = "x"
    const bytes = [...writeField(1, 0, writeVarint(5)), ...writeStringField(2, "x")];
    const r = new Reader(new Uint8Array(bytes));
    const t1 = r.tag(); expect(t1.field).toBe(1); r.skip(t1.wire);
    const t2 = r.tag(); expect(t2.field).toBe(2); expect(r.string()).toBe("x");
  });
});
