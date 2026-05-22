#!/usr/bin/env python3
"""
Probe 511.org StopTimetable and Route Timetable endpoints.

Usage:
    python3 bin/probe-schedule-endpoints.py <api_key>

Output files written to /tmp/:
    probe-stoptimetable-SF-15725.json  (or .xml)
    probe-stoptimetable-CT-70021.json  (or .xml)
    probe-timetable-SF-38.json         (or .xml)
    probe-timetable-CT-Local.json      (or .xml)
"""

import sys
import json
import urllib.request
import urllib.parse

BASE = "https://api.511.org/transit"


def fetch(path: str, params: dict) -> tuple:
    url = f"{BASE}/{path}?" + urllib.parse.urlencode(params)
    print(f"\nGET {url}")
    with urllib.request.urlopen(url, timeout=20) as resp:
        data = resp.read()
        ct = resp.headers.get("Content-Type", "?")
    print(f"  HTTP 200  Content-Type: {ct}  Size: {len(data):,} bytes")
    return data, ct


def summarize(obj, depth=0):
    if depth > 2:
        return
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, list):
                print(f"{'  ' * depth}{k}: list[{len(v)}]")
                if v and isinstance(v[0], dict):
                    summarize(v[0], depth + 1)
            elif isinstance(v, dict):
                print(f"{'  ' * depth}{k}: dict")
                summarize(v, depth + 1)
            else:
                print(f"{'  ' * depth}{k}: {type(v).__name__} = {repr(v)[:80]}")
    elif isinstance(obj, list) and obj:
        summarize(obj[0], depth)


def probe(path: str, params: dict, label: str, out_base: str):
    print(f"\n{'='*60}")
    print(f"  {label}")
    print(f"{'='*60}")
    try:
        data, ct = fetch(path, params)
    except Exception as e:
        print(f"  ERROR: {e}")
        return

    stripped = data.lstrip(b"\xef\xbb\xbf")  # strip BOM

    if "json" in ct.lower():
        try:
            parsed = json.loads(stripped)
        except Exception as e:
            print(f"  JSON parse failed: {e}")
            out_path = f"/tmp/{out_base}.raw"
            with open(out_path, "wb") as f:
                f.write(data)
            print(f"  Saved raw to {out_path}")
            return
        print("\n  Structure (2 levels deep):")
        summarize(parsed)
        out_path = f"/tmp/{out_base}.json"
        with open(out_path, "w") as f:
            json.dump(parsed, f, indent=2)
        print(f"\n  Saved pretty JSON to {out_path}")
    else:
        lines = stripped.decode("utf-8", errors="replace").splitlines()
        print(f"\n  First 60 lines:")
        for line in lines[:60]:
            print(f"  {line}")
        out_path = f"/tmp/{out_base}.xml"
        with open(out_path, "wb") as f:
            f.write(data)
        print(f"\n  Saved XML to {out_path}")


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 bin/probe-schedule-endpoints.py <api_key>")
        sys.exit(1)

    api_key = sys.argv[1]

    print("\n===== STOP TIMETABLE ENDPOINT =====")
    probe("stoptimetable",
          {"operatorref": "SF", "monitoringref": "15725", "api_key": api_key},
          "SF stop 15725 (Market & 4th St)", "probe-stoptimetable-SF-15725")
    probe("stoptimetable",
          {"operatorref": "CT", "monitoringref": "70021", "api_key": api_key},
          "CT stop 70021 (Bayshore)", "probe-stoptimetable-CT-70021")

    print("\n===== ROUTE TIMETABLE ENDPOINT =====")
    probe("timetable",
          {"operator_id": "SF", "line_id": "38", "api_key": api_key},
          "SF route 38 (Geary)", "probe-timetable-SF-38")
    probe("timetable",
          {"operator_id": "CT", "line_id": "Local", "api_key": api_key},
          "CT route Local", "probe-timetable-CT-Local")


if __name__ == "__main__":
    main()
