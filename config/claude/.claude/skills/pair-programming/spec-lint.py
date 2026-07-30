#!/usr/bin/env python3
"""Structural checks on a pair-programming spec.

Everything here is mechanically decidable — no judgement, no model. Run it
before spending a critic on the spec, and again with --verify once the code
exists.

    python3 spec-lint.py .specs/2026-07-29-week-templates/spec.md
    python3 spec-lint.py --verify .specs/2026-07-29-week-templates/spec.md

Exit 0 when clean, 1 when it found something. Stdlib only.
"""

import argparse
import re
import sys
from pathlib import Path

REQUIRED_SECTIONS = ("Problem", "Non-goals", "Decisions", "Requirements", "Verification")
VERIFY_METHODS = {"test", "inspection", "analysis", "demonstration"}
STATUS_VALUES = {"drafted", "critiqued", "approved", "implemented", "reviewed", "abandoned"}
LANE_VALUES = {"small", "standard"}
# From `approved` on there is a recorded branch point to diff against and
# reset to; before that the spec has nothing to abort.
BASE_REQUIRED_STATUSES = {"approved", "implemented", "reviewed"}
# Deliberate unknowns live in Open questions, and the Review Log quotes
# findings verbatim — neither should fail the placeholder check.
PLACEHOLDER_EXEMPT_SECTIONS = ("Open questions", "Review Log")

# EARS requires exactly one `shall` per requirement — one behaviour per row.
# The other modals are the ambiguity this notation exists to remove.
HEDGES = re.compile(r"\b(should|will|may|might|could|can)\b", re.IGNORECASE)
SHALL = re.compile(r"\bshall\b", re.IGNORECASE)
# Unfilled template slots: `<system>`, `<trigger>`, and friends.
UNFILLED = re.compile(r"<[a-z][a-z0-9 _/-]*>", re.IGNORECASE)
PLACEHOLDER = re.compile(r"\b(TBD|TODO|FIXME|XXX)\b|\?\?\?", re.IGNORECASE)
REQ_REF = re.compile(r"\bR(\d+)\b")
LANE = re.compile(r"\*\*Lane:\*\*\s*(\S+)")
BASE = re.compile(r"\*\*Base:\*\*\s*(\S+)")
SHA = re.compile(r"[0-9a-fA-F]{7,40}")


def parse_sections(lines):
    """Map heading text -> (start, end) line span, exclusive end."""
    heads = []
    for i, line in enumerate(lines):
        m = re.match(r"^#{2,3}\s+(.*?)\s*$", line)
        if m:
            # "## Problem — REQUIRED" and "## Problem" are the same section.
            heads.append((i, re.split(r"\s+[—-]\s+", m.group(1))[0].strip()))
    spans = {}
    for idx, (line_no, title) in enumerate(heads):
        end = heads[idx + 1][0] if idx + 1 < len(heads) else len(lines)
        spans.setdefault(title, (line_no, end))
    return spans


def table_rows(lines, span, id_pattern):
    """Rows of a markdown table whose first cell matches id_pattern.

    Filtering on the id skips header and separator rows without guessing at
    their shape.
    """
    rows = []
    for i in range(*span):
        stripped = lines[i].strip()
        if not stripped.startswith("|"):
            continue
        cells = [c.strip() for c in stripped.strip("|").split("|")]
        if cells and re.fullmatch(id_pattern, cells[0]):
            rows.append((i + 1, cells))
    return rows


def check_structure(text, lines, spans, problems):
    for name in REQUIRED_SECTIONS:
        if name not in spans:
            problems.append((0, f"missing required section: ## {name}"))
        elif name not in ("Decisions", "Requirements"):
            # Those two have content checks of their own.
            start, end = spans[name]
            if not any(line.strip() for line in lines[start + 1:end]):
                problems.append((
                    start + 1,
                    f"## {name} is required and empty — an empty section reads "
                    "as looked-at when nobody looked",
                ))

    status = None
    found = re.search(r"^\*\*Status:\*\*\s*(.+?)\s*$", text, re.MULTILINE)
    if not found:
        problems.append((0, "no **Status:** line in the header"))
    elif found.group(1) not in STATUS_VALUES:
        problems.append((
            0,
            f"Status is {found.group(1)!r}; expected one of "
            + ", ".join(sorted(STATUS_VALUES)),
        ))
    else:
        status = found.group(1)

    lane = None
    found = LANE.search(text)
    if not found:
        problems.append((0, "no **Lane:** in the header — small or standard"))
    elif found.group(1) not in LANE_VALUES:
        problems.append((
            0,
            f"Lane is {found.group(1)!r}; expected one of "
            + ", ".join(sorted(LANE_VALUES)),
        ))
    else:
        lane = found.group(1)

    base = BASE.search(text)
    if base and not SHA.fullmatch(base.group(1)):
        problems.append((0, f"Base {base.group(1)!r} does not look like a commit sha"))
        base = None
    if status in BASE_REQUIRED_STATUSES and not base:
        problems.append((
            0,
            f"Status is {status} but the header has no **Base:** sha — the "
            "review diff and the abort path both start there",
        ))

    if lane == "standard":
        if "Files" not in spans:
            problems.append((
                0,
                "Lane is standard but there is no ### Files table — the "
                "critic's false-premise check is anchored on it",
            ))
        elif not table_rows(lines, spans["Files"], r"`.+`"):
            problems.append((
                spans["Files"][0] + 1,
                "### Files has no rows — the standard lane needs the touched "
                "paths listed",
            ))

    if "Decisions" in spans:
        rows = table_rows(lines, spans["Decisions"], r"D\d+")
        body = "\n".join(lines[slice(*spans["Decisions"])])
        if not rows and "none contested" not in body.lower():
            problems.append((
                spans["Decisions"][0] + 1,
                "Decisions is empty — add a D-row, or state 'None contested.' "
                "so the implementer knows nothing was argued rather than that "
                "nobody looked",
            ))
        for line_no, cells in rows:
            if len(cells) < 4 or not cells[3]:
                problems.append((
                    line_no,
                    f"{cells[0]} has no rejected alternative — a decision with "
                    "no road not taken is a preference, not a decision",
                ))


def check_requirements(lines, spans, problems):
    if "Requirements" not in spans:
        return []
    rows = table_rows(lines, spans["Requirements"], r"R\d+")
    if not rows:
        problems.append((spans["Requirements"][0] + 1, "no requirements found"))
        return []

    seen = []
    for line_no, cells in rows:
        rid = cells[0]
        if len(cells) < 3:
            problems.append((line_no, f"{rid} row needs: | # | Requirement | Verify by |"))
            continue
        text, verify = cells[1], cells[2]
        seen.append(int(rid[1:]))

        shalls = len(SHALL.findall(text))
        if shalls == 0:
            problems.append((line_no, f"{rid} has no 'shall' — EARS requires it"))
        elif shalls > 1:
            problems.append((
                line_no,
                f"{rid} has {shalls} 'shall's — one behaviour per requirement, split it",
            ))

        hedge = HEDGES.search(text)
        if hedge:
            problems.append((
                line_no,
                f"{rid} uses {hedge.group(1)!r} — a requirement is binding or it is "
                "not; use 'shall' or move it to Non-goals",
            ))

        slot = UNFILLED.search(text)
        if slot:
            problems.append((line_no, f"{rid} still has an unfilled slot: {slot.group(0)}"))

        base = verify.split(":", 1)[0].strip()
        if base not in VERIFY_METHODS:
            problems.append((
                line_no,
                f"{rid} verify method {verify!r} is not one of "
                + ", ".join(sorted(VERIFY_METHODS)),
            ))

    dupes = sorted({n for n in seen if seen.count(n) > 1})
    if dupes:
        problems.append((
            spans["Requirements"][0] + 1,
            "duplicate requirement ids: " + ", ".join(f"R{n}" for n in dupes)
            + " — ids must be unique; gaps left by deleted requirements are fine",
        ))
    return rows


def check_references(lines, spans, req_ids, problems):
    """Every R<n> cited anywhere must exist in the Requirements table."""
    req_span = spans.get("Requirements", (-1, -1))
    for i, line in enumerate(lines):
        if req_span[0] <= i < req_span[1]:
            continue
        for ref in REQ_REF.finditer(line):
            if int(ref.group(1)) not in req_ids:
                problems.append((i + 1, f"cites R{ref.group(1)}, which no requirement defines"))


def check_placeholders(lines, spans, problems):
    """Placeholders outside the exempt sections mean the spec is not finished."""
    exempt = [spans[n] for n in PLACEHOLDER_EXEMPT_SECTIONS if n in spans]
    for i, line in enumerate(lines):
        if any(start <= i < end for start, end in exempt):
            continue
        hit = PLACEHOLDER.search(line)
        if hit:
            problems.append((i + 1, f"placeholder {hit.group(0)!r} — resolve it or move it to Open questions"))


def check_files(lines, spans, root, verify_mode, problems):
    if "Files" not in spans:
        return
    for line_no, cells in table_rows(lines, spans["Files"], r"`.+`"):
        if len(cells) < 2:
            continue
        path = root / cells[0].strip("`")
        action = cells[1].lower()
        if "modify" in action and not path.exists():
            problems.append((
                line_no,
                f"{cells[0]} is marked modify but does not exist — false premise "
                "about the codebase",
            ))
        if verify_mode and "create" in action and not path.exists():
            problems.append((line_no, f"{cells[0]} was to be created and does not exist"))


def check_test_coverage(lines, spans, root, problems):
    """--verify: every `test:` target names a test that actually exists."""
    for line_no, cells in table_rows(lines, spans.get("Requirements", (0, 0)), r"R\d+"):
        if len(cells) < 3 or not cells[2].startswith("test:"):
            continue
        target = cells[2][len("test:"):].strip().strip("`")
        file_part, _, name = target.partition("::")
        path = root / file_part
        if not path.exists():
            problems.append((line_no, f"{cells[0]}: test file {file_part} does not exist"))
            continue
        # Word-bounded so test_foo does not pass on the strength of test_foo_bar.
        if name and not re.search(
            rf"\b{re.escape(name)}\b",
            path.read_text(encoding="utf-8", errors="replace"),
        ):
            problems.append((line_no, f"{cells[0]}: {path.name} has no test named {name!r}"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("spec", type=Path)
    parser.add_argument(
        "--verify",
        action="store_true",
        help="post-implementation: also check that named tests and created files exist",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path.cwd(),
        help="repo root that paths in the spec are relative to (default: cwd)",
    )
    args = parser.parse_args()

    if not args.spec.exists():
        print(f"spec-lint: no such spec: {args.spec}", file=sys.stderr)
        return 2

    text = args.spec.read_text(encoding="utf-8")
    lines = text.splitlines()
    spans = parse_sections(lines)
    problems = []

    check_structure(text, lines, spans, problems)
    rows = check_requirements(lines, spans, problems)
    req_ids = {int(cells[0][1:]) for _, cells in rows}
    check_references(lines, spans, req_ids, problems)
    check_placeholders(lines, spans, problems)
    check_files(lines, spans, args.root, args.verify, problems)
    if args.verify:
        check_test_coverage(lines, spans, args.root, problems)

    if not problems:
        scope = "structure + coverage" if args.verify else "structure"
        print(f"spec-lint: clean ({scope}, {len(req_ids)} requirements)")
        return 0

    for line_no, message in sorted(problems):
        where = f"{args.spec}:{line_no}" if line_no else str(args.spec)
        print(f"{where}: {message}")
    print(f"spec-lint: {len(problems)} problem(s)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
