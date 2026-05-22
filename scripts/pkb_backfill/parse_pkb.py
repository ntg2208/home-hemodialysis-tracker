# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Parse PKB blood test pastes into a long-format CSV.

Drop one paste per marker into ./pastes/<marker>.txt (filename stem = canonical
marker name), then run `uv run parse_pkb.py`. Outputs ./blood_tests.csv and
prints a sanity report.

Pre/post timing is intentionally left blank — assign manually during CSV review.
The sanity report flags same-day pairs as candidates.
"""
from __future__ import annotations

import csv
import re
from dataclasses import dataclass, asdict
from datetime import date, datetime
from pathlib import Path

ROOT = Path(__file__).parent
PASTES_DIR = ROOT / "pastes"
OUTPUT_CSV = ROOT / "blood_tests.csv"

ADMISSION_END = date(2023, 10, 15)
IN_CENTER_END = date(2026, 1, 31)

RE_VALUE_PERCENT_UNIT = re.compile(r"^([\d,]+(?:\.\d+)?)\%\s+([\d,]+(?:\.\d+)?)\s+(.+?)\s*$")
RE_VALUE_UNIT = re.compile(r"^([\d,]+(?:\.\d+)?)\s+(.+?)\s*$")
RE_VALUE_LT = re.compile(r"^<([\d,]+(?:\.\d+)?)\s+(.+?)\s*$")
RE_VALUE_GT = re.compile(r"^>([\d,]+(?:\.\d+)?)\s+(.+?)\s*$")
RE_VALUE_BARE = re.compile(r"^([\d,]+(?:\.\d+)?)\s*$")
RE_RANGE = re.compile(r"^Range:\s*([\d,.]+)\s*-\s*([\d,.]+)\s+.+$")
RE_RANGE_GT = re.compile(r"^Range:\s*>\s*([\d,.]+)\s+.+$")
RE_RANGE_LT = re.compile(r"^Range:\s*<\s*([\d,.]+)\s+.+$")
RE_DATE = re.compile(r"^Date:\s*(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s*$")
RE_LAB_ID = re.compile(r"^Lab Id:\s*(\S+)\s*$")
RE_LAB_TYPE = re.compile(r"^Lab type:")
RE_COMMENTS_HEADER = re.compile(r"^Comments:\s*$")

SOURCE_PATTERNS = [
    ("London North West", "london-north-west-pkb"),
    ("Imperial College Healthcare", "imperial-pkb"),
]

# Maps paste-file stem → canonical marker name. London North West and Imperial
# PKBs use different display names for the same clinical test; merge them so
# trend analysis sees one series. The `source` column still distinguishes
# Imperial vs LNW; the original stem is preserved in `note` for audit.
MARKER_ALIASES: dict[str, str] = {
    # _lnw suffix variants (chemistry / immunology)
    "albumin_lnw": "albumin",
    "alp_lnw": "alkaline_phosphatase",
    "bicarbonate_lnw": "bicarbonate",
    "calcium_lnw": "calcium",
    "calcium_corrected_lnw": "adjusted_calcium",
    "creatinine_lnw": "creatinine",
    "crp_lnw": "crp",
    "egfr_ckd_epi_lnw": "egfr",
    "ferritin_lnw": "ferritin",
    "hbv_surface_ab_lnw": "hbv_surface_ab",
    "mpv_lnw": "mpv",
    "phosphate_lnw": "phosphate",
    "potassium_lnw": "potassium",
    "rbc_lnw": "rbc",
    "rdw_lnw": "rdw",
    "sodium_lnw": "sodium",
    "total_bilirubin_lnw": "bilirubin",
    "total_protein_lnw": "total_protein",
    "urea_nitrogen_lnw": "urea",
    "wbc_lnw": "wbc",
    # PKB descriptive-name variants (haematology)
    "basophils_in_blood": "basophils",
    "eosinophils_in_blood": "eosinophils",
    "haemoglobin_g_l": "haemoglobin",
    "lymphocyte_count_in_blood": "lymphocytes",
    "monocytes_in_blood": "monocytes",
    "neutrophils_in_blood": "neutrophils",
    "platelets_in_blood": "platelets",
    "pcv": "haematocrit",
}


def detect_source(block_text: str) -> str:
    for pattern, src in SOURCE_PATTERNS:
        if pattern in block_text:
            return src
    return "unknown"

MONTHS = {
    "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
    "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12,
}


@dataclass
class Row:
    marker: str
    datetime: str
    value: float
    unit: str
    ref_low: float | None
    ref_high: float | None
    timing: str
    note: str
    source: str
    lab_id: str
    phase: str


def phase_for(dt_iso: str) -> str:
    d = date.fromisoformat(dt_iso[:10])
    if d <= ADMISSION_END:
        return "admission"
    if d <= IN_CENTER_END:
        return "in-center-hd"
    return "home-hd"


def split_blocks(text: str) -> list[str]:
    """Each PKB block ends with a `Lab type:` line. Material before the first
    Lab type: (marker header, table headings) becomes a non-matching first block
    that parse_one_block() rejects — harmless."""
    blocks: list[str] = []
    current: list[str] = []
    for line in text.splitlines():
        current.append(line)
        if RE_LAB_TYPE.match(line.strip()):
            blocks.append("\n".join(current))
            current = []
    return blocks


def parse_one_block(block_text: str) -> dict | None:
    value: float | None = None
    value_text: str | None = None
    unit: str | None = None
    ref_low: float | None = None
    ref_high: float | None = None
    dt_iso: str | None = None
    lab_id: str | None = None
    note_lines: list[str] = []
    detection_limit_text: str | None = None
    in_comments = False

    for line in block_text.splitlines():
        s = line.strip()
        if not s:
            continue

        if in_comments:
            if s.startswith("Date:") or s.startswith("Lab Id:"):
                in_comments = False
                # fall through to process this line
            else:
                note_lines.append(s)
                continue

        if RE_COMMENTS_HEADER.match(s):
            in_comments = True
            continue

        if value is None:
            m = RE_VALUE_PERCENT_UNIT.match(s)
            if m:
                value = float(m.group(2).replace(",", ""))
                unit = m.group(3)
                continue
            m = RE_VALUE_UNIT.match(s)
            if m:
                value = float(m.group(1).replace(",", ""))
                unit = m.group(2)
                continue
            m = RE_VALUE_LT.match(s)
            if m:
                value = float(m.group(1).replace(",", ""))
                unit = m.group(2)
                detection_limit_text = f"below detection limit (<{m.group(1)})"
                continue
            m = RE_VALUE_GT.match(s)
            if m:
                value = float(m.group(1).replace(",", ""))
                unit = m.group(2)
                detection_limit_text = f"above detection limit (>{m.group(1)})"
                continue
            m = RE_VALUE_BARE.match(s)
            if m:
                value = float(m.group(1).replace(",", ""))
                unit = ""
                continue
            # For serology/qualitative results: "Not detected" or similar text
            if s and not s.startswith("Lab") and not s.startswith("Date") and not s.startswith("Range"):
                if any(kw in s for kw in ["Not detected", "Detected", "Negative", "Positive", "Present", "Absent"]):
                    value_text = s
                    continue

        if ref_low is None and ref_high is None:
            m = RE_RANGE.match(s)
            if m:
                ref_low = float(m.group(1).replace(",", ""))
                ref_high = float(m.group(2).replace(",", ""))
                continue
            m = RE_RANGE_GT.match(s)
            if m:
                ref_low = float(m.group(1).replace(",", ""))
                continue
            m = RE_RANGE_LT.match(s)
            if m:
                ref_high = float(m.group(1).replace(",", ""))
                continue

        if dt_iso is None:
            m = RE_DATE.match(s)
            if m:
                day, mon, year, hh, mm, ss = m.groups()
                if mon not in MONTHS:
                    continue
                dt_iso = f"{year}-{MONTHS[mon]:02d}-{int(day):02d}T{hh}:{mm}:{ss}"
                continue

        if lab_id is None:
            m = RE_LAB_ID.match(s)
            if m:
                lab_id = m.group(1)
                continue

    # For qualitative markers (e.g., MRSA Screen, HBV serology), try to extract result from comments
    if value is None and note_lines:
        for note in note_lines:
            if note.startswith("CULTURE"):
                parts = note.split(None, 1)
                if len(parts) > 1:
                    value_text = parts[1]
                    break
            # HBV Surface Ab: extract ">1000.00 mIU/mL" from "HBV Surface Ab                          >1000.00 mIU/mL"
            if note.startswith("HBV Surface Ab") and not note.startswith("HBV Surface Ab (Comment)"):
                # Extract everything after "HBV Surface Ab" and strip leading whitespace
                parts = note.split(None, 2)
                if len(parts) >= 3:
                    # Take from the 3rd element onwards (skip "HBV" and "Surface", get "Ab" and value)
                    value_text = " ".join(parts[2:])
                    break
            # Final Diagnosis for pathology: extract diagnosis from comments
            if note.startswith("Final Diagnosis"):
                parts = note.split(":", 1)
                if len(parts) > 1:
                    value_text = parts[1].strip()
                    break

    if value is None and value_text is None:
        return None
    if dt_iso is None or lab_id is None:
        return None

    final_notes: list[str] = []
    if detection_limit_text:
        final_notes.append(detection_limit_text)
    final_notes.extend(note_lines)

    # For qualitative results, store text as value (0.0 placeholder), unit as result type
    if value_text is not None:
        return {
            "value": 0.0,
            "unit": value_text,
            "ref_low": None,
            "ref_high": None,
            "datetime": dt_iso,
            "lab_id": lab_id,
            "note": " | ".join(final_notes),
        }

    return {
        "value": value,
        "unit": unit or "",
        "ref_low": ref_low,
        "ref_high": ref_high,
        "datetime": dt_iso,
        "lab_id": lab_id,
        "note": " | ".join(final_notes),
    }


def parse_file(path: Path) -> tuple[list[Row], dict]:
    original_stem = path.stem
    marker = MARKER_ALIASES.get(original_stem, original_stem)
    aliased = marker != original_stem
    text = path.read_text(encoding="utf-8")
    blocks = split_blocks(text)

    parsed: list[Row] = []
    failures: list[str] = []
    for block in blocks:
        result = parse_one_block(block)
        if result is None:
            # Don't count the marker-header / "first" block as a failure
            # (it has no value line so legitimately won't parse).
            if "Lab Id:" in block:
                lab_id_for_fail = None
                for fline in block.splitlines():
                    m = RE_LAB_ID.match(fline.strip())
                    if m:
                        lab_id_for_fail = m.group(1)
                        break
                failures.append(lab_id_for_fail or "<no lab_id>")
            continue
        note = result["note"]
        if aliased:
            alias_note = f"merged_from={original_stem}"
            note = f"{alias_note} | {note}" if note else alias_note
        parsed.append(Row(
            marker=marker,
            datetime=result["datetime"],
            value=result["value"],
            unit=result["unit"],
            ref_low=result["ref_low"],
            ref_high=result["ref_high"],
            timing="",
            note=note,
            source=detect_source(block),
            lab_id=result["lab_id"],
            phase=phase_for(result["datetime"]),
        ))

    # Dedupe by lab_id within file
    seen: set[str] = set()
    deduped: list[Row] = []
    for r in parsed:
        if r.lab_id in seen:
            continue
        seen.add(r.lab_id)
        deduped.append(r)

    phase_counts: dict[str, int] = {}
    for r in deduped:
        phase_counts[r.phase] = phase_counts.get(r.phase, 0) + 1

    date_range = None
    if deduped:
        dates = sorted(r.datetime[:10] for r in deduped)
        date_range = (dates[0], dates[-1])

    sources: dict[str, int] = {}
    for r in deduped:
        sources[r.source] = sources.get(r.source, 0) + 1

    summary = {
        "blocks": len(blocks),
        "parsed": len(parsed),
        "deduped": len(deduped),
        "failed": len(failures),
        "failure_ids": failures,
        "phases": phase_counts,
        "sources": sources,
        "date_range": date_range,
    }
    return deduped, summary


def write_csv(rows: list[Row], path: Path) -> None:
    rows_sorted = sorted(rows, key=lambda r: (r.marker, r.datetime))
    now = datetime.now().isoformat(timespec="seconds")
    fieldnames = list(asdict(rows_sorted[0]).keys()) if rows_sorted else [
        "marker", "datetime", "value", "unit", "ref_low", "ref_high",
        "timing", "note", "source", "lab_id", "phase",
    ]
    fieldnames.append("created_at")
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(fieldnames)
        for r in rows_sorted:
            d = asdict(r)
            row = [
                d["marker"], d["datetime"], d["value"], d["unit"],
                "" if d["ref_low"] is None else d["ref_low"],
                "" if d["ref_high"] is None else d["ref_high"],
                d["timing"], d["note"], d["source"], d["lab_id"], d["phase"],
                now,
            ]
            writer.writerow(row)


def report_same_day_pairs(rows: list[Row]) -> None:
    by_marker_date: dict[tuple[str, str], list[Row]] = {}
    for r in rows:
        key = (r.marker, r.datetime[:10])
        by_marker_date.setdefault(key, []).append(r)

    pairs = [(k, v) for k, v in by_marker_date.items() if len(v) > 1]
    if not pairs:
        print("\nSame-day pairs (pre/post candidates): none")
        return

    print("\nSame-day pairs (pre/post candidates — assign `timing` manually in CSV):")
    for (marker, date_str), group in sorted(pairs):
        times = sorted(r.datetime[11:16] for r in group)
        phases = {r.phase for r in group}
        phase_tag = f" [{', '.join(sorted(phases))}]" if phases else ""
        print(f"  {marker} {date_str}: {len(group)} readings at {', '.join(times)}{phase_tag}")


def main() -> None:
    if not PASTES_DIR.exists():
        print(f"No pastes directory at {PASTES_DIR}")
        return

    paste_files = sorted(PASTES_DIR.glob("*.txt"))
    if not paste_files:
        print(f"No *.txt files in {PASTES_DIR}")
        return

    all_rows: list[Row] = []
    all_failures: list[tuple[str, str]] = []  # (marker, lab_id)
    print("Parsing:")
    for path in paste_files:
        rows, s = parse_file(path)
        all_rows.extend(rows)
        for fid in s["failure_ids"]:
            all_failures.append((path.stem, fid))
        date_range = (
            f"{s['date_range'][0]} → {s['date_range'][1]}"
            if s["date_range"] else "(no rows)"
        )
        phases = ", ".join(f"{k}={v}" for k, v in sorted(s["phases"].items())) or "-"
        sources = ", ".join(f"{k}={v}" for k, v in sorted(s["sources"].items())) or "-"
        print(
            f"  {path.stem:22s}  blocks={s['blocks']:3d}  parsed={s['parsed']:3d}  "
            f"deduped={s['deduped']:3d}  failed={s['failed']:3d}  "
            f"range={date_range}  phases=({phases})  sources=({sources})"
        )

    if all_failures:
        print("\nFailed to parse (lab_ids):")
        for marker, fid in all_failures:
            print(f"  {marker}: {fid}")

    if not all_rows:
        print("\nNo rows produced. Check that pastes contain Imperial PKB blocks.")
        return

    write_csv(all_rows, OUTPUT_CSV)
    print(f"\n→ Wrote {len(all_rows)} rows to {OUTPUT_CSV}")

    report_same_day_pairs(all_rows)


if __name__ == "__main__":
    main()
