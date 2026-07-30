#!/usr/bin/env python3
"""Tests for spec-lint.py. Stdlib only:

    python3 test_spec_lint.py
"""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

LINT = Path(__file__).with_name("spec-lint.py")

R1 = "| R1 | When the user clicks the toggle, the widget shall change state. | test:tests/test_widget.py::test_toggle |"

FILES_SECTION = (
    "## Architecture\n\n### Files\n\n"
    "| Path | Change | Responsibility |\n|---|---|---|\n"
    "| `src/widget.py` | create | Toggle handler |"
)


def make_spec(
    status="drafted",
    lane="small",
    base=None,
    problem="The widget cannot be toggled from the dashboard.",
    non_goals="- Persisting toggle state across sessions.",
    decisions="None contested.",
    requirements=(R1,),
    verification="Run the widget suite end to end.",
    extra="",
):
    """A minimal spec that lints clean; None omits a section entirely."""
    header = ["# Widget toggle", "", "**Date:** 2026-07-29"]
    lane_part = f" · **Lane:** {lane}" if lane is not None else ""
    header.append(f"**Repo:** demo · **Branch:** main{lane_part}")
    header.append(f"**Status:** {status}")
    if base:
        header.append(f"**Base:** {base}")

    parts = ["\n".join(header)]
    if problem is not None:
        parts.append("## Problem — REQUIRED\n\n" + problem)
    if non_goals is not None:
        parts.append("## Non-goals — REQUIRED\n\n" + non_goals)
    if decisions is not None:
        parts.append("## Decisions — REQUIRED\n\n" + decisions)
    if requirements is not None:
        parts.append(
            "## Requirements — REQUIRED\n\n| # | Requirement | Verify by |\n|---|---|---|\n"
            + "\n".join(requirements)
        )
    if verification is not None:
        parts.append("## Verification — REQUIRED\n\n" + verification)
    if extra:
        parts.append(extra)
    return "\n\n".join(parts) + "\n"


def lint(spec_text, files=None, verify=False):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "spec.md").write_text(spec_text, encoding="utf-8")
        for rel, content in (files or {}).items():
            target = root / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
        cmd = [sys.executable, str(LINT), str(root / "spec.md"), "--root", str(root)]
        if verify:
            cmd.append("--verify")
        run = subprocess.run(cmd, capture_output=True, text=True)
        return run.returncode, run.stdout + run.stderr


class CleanSpecs(unittest.TestCase):
    def test_minimal_small_lane_spec(self):
        code, out = lint(make_spec())
        self.assertEqual(code, 0, out)

    def test_standard_lane_with_files(self):
        code, out = lint(make_spec(lane="standard", extra=FILES_SECTION))
        self.assertEqual(code, 0, out)

    def test_abandoned_is_a_valid_status(self):
        code, out = lint(make_spec(status="abandoned"))
        self.assertEqual(code, 0, out)

    def test_approved_with_base_is_clean(self):
        code, out = lint(make_spec(status="approved", base="abc1234"))
        self.assertEqual(code, 0, out)


class HeaderChecks(unittest.TestCase):
    def test_unknown_status(self):
        code, out = lint(make_spec(status="wip"))
        self.assertEqual(code, 1)
        self.assertIn("Status is 'wip'", out)

    def test_missing_lane(self):
        code, out = lint(make_spec(lane=None))
        self.assertEqual(code, 1)
        self.assertIn("no **Lane:**", out)

    def test_invalid_lane(self):
        code, out = lint(make_spec(lane="medium"))
        self.assertEqual(code, 1)
        self.assertIn("Lane is 'medium'", out)

    def test_approved_requires_base(self):
        code, out = lint(make_spec(status="approved"))
        self.assertEqual(code, 1)
        self.assertIn("no **Base:** sha", out)

    def test_malformed_base(self):
        code, out = lint(make_spec(status="approved", base="feature-branch"))
        self.assertEqual(code, 1)
        self.assertIn("does not look like a commit sha", out)

    def test_drafted_does_not_require_base(self):
        code, out = lint(make_spec(status="drafted"))
        self.assertEqual(code, 0, out)


class SectionChecks(unittest.TestCase):
    def test_missing_required_section(self):
        code, out = lint(make_spec(non_goals=None))
        self.assertEqual(code, 1)
        self.assertIn("missing required section: ## Non-goals", out)

    def test_empty_required_section(self):
        code, out = lint(make_spec(problem=""))
        self.assertEqual(code, 1)
        self.assertIn("## Problem is required and empty", out)

    def test_standard_lane_requires_files(self):
        code, out = lint(make_spec(lane="standard"))
        self.assertEqual(code, 1)
        self.assertIn("no ### Files table", out)

    def test_standard_lane_files_needs_rows(self):
        headers_only = "## Architecture\n\n### Files\n\n| Path | Change | Responsibility |\n|---|---|---|"
        code, out = lint(make_spec(lane="standard", extra=headers_only))
        self.assertEqual(code, 1)
        self.assertIn("### Files has no rows", out)

    def test_empty_decisions_flagged(self):
        code, out = lint(make_spec(decisions="(see notes)"))
        self.assertEqual(code, 1)
        self.assertIn("Decisions is empty", out)

    def test_decision_without_rejected_alternative(self):
        table = (
            "| # | Decision | Why | Rejected alternative |\n|---|---|---|---|\n"
            "| D1 | Snapshot titles | rename safety |"
        )
        code, out = lint(make_spec(decisions=table))
        self.assertEqual(code, 1)
        self.assertIn("no rejected alternative", out)


class RequirementChecks(unittest.TestCase):
    def test_no_shall(self):
        code, out = lint(make_spec(requirements=("| R1 | The widget toggles. | inspection |",)))
        self.assertEqual(code, 1)
        self.assertIn("has no 'shall'", out)

    def test_two_shalls(self):
        row = "| R1 | The widget shall toggle and shall log. | inspection |"
        code, out = lint(make_spec(requirements=(row,)))
        self.assertEqual(code, 1)
        self.assertIn("2 'shall's", out)

    def test_hedge_flagged(self):
        row = "| R1 | When clicked, the widget shall change state and should log. | inspection |"
        code, out = lint(make_spec(requirements=(row,)))
        self.assertEqual(code, 1)
        self.assertIn("'should'", out)

    def test_unfilled_slot(self):
        row = "| R1 | When <trigger>, the widget shall change state. | inspection |"
        code, out = lint(make_spec(requirements=(row,)))
        self.assertEqual(code, 1)
        self.assertIn("unfilled slot", out)

    def test_bad_verify_method(self):
        row = "| R1 | The widget shall toggle. | vibes |"
        code, out = lint(make_spec(requirements=(row,)))
        self.assertEqual(code, 1)
        self.assertIn("not one of", out)

    def test_duplicate_ids_flagged(self):
        code, out = lint(make_spec(requirements=(R1, R1)))
        self.assertEqual(code, 1)
        self.assertIn("duplicate requirement ids: R1", out)

    def test_id_gaps_are_allowed(self):
        r3 = R1.replace("R1", "R3", 1)
        code, out = lint(make_spec(requirements=(R1, r3)))
        self.assertEqual(code, 0, out)

    def test_dangling_reference(self):
        code, out = lint(make_spec(verification="Covers R9 end to end."))
        self.assertEqual(code, 1)
        self.assertIn("cites R9", out)


class PlaceholderChecks(unittest.TestCase):
    def test_placeholder_flagged(self):
        code, out = lint(make_spec(problem="TODO describe the problem."))
        self.assertEqual(code, 1)
        self.assertIn("placeholder 'TODO'", out)

    def test_open_questions_exempt(self):
        oq = (
            "## Open questions\n\n| # | Question | Decider | Blocks |\n|---|---|---|---|\n"
            "| Q1 | TBD which cache backend | partner | R1 |"
        )
        code, out = lint(make_spec(extra=oq))
        self.assertEqual(code, 0, out)

    def test_review_log_exempt(self):
        log = (
            "## Review Log\n\n| Finding | Source | Severity | Ruling |\n|---|---|---|---|\n"
            "| F1 code has TODO markers | critic | Advisory | parked: nothing depends on it |"
        )
        code, out = lint(make_spec(extra=log))
        self.assertEqual(code, 0, out)


class FilesChecks(unittest.TestCase):
    def test_modify_missing_file(self):
        code, out = lint(make_spec(extra=FILES_SECTION.replace("create", "modify")))
        self.assertEqual(code, 1)
        self.assertIn("marked modify but does not exist", out)


class VerifyMode(unittest.TestCase):
    def _spec(self, **kwargs):
        return make_spec(status="implemented", base="abc1234", **kwargs)

    def test_missing_test_file(self):
        code, out = lint(self._spec(), verify=True)
        self.assertEqual(code, 1)
        self.assertIn("test file tests/test_widget.py does not exist", out)

    def test_test_name_needs_word_boundary(self):
        files = {"tests/test_widget.py": "def test_toggle_extra():\n    pass\n"}
        code, out = lint(self._spec(), files=files, verify=True)
        self.assertEqual(code, 1)
        self.assertIn("has no test named 'test_toggle'", out)

    def test_exact_test_name_passes(self):
        files = {"tests/test_widget.py": "def test_toggle():\n    pass\n"}
        code, out = lint(self._spec(), files=files, verify=True)
        self.assertEqual(code, 0, out)

    def test_created_file_must_exist(self):
        files = {"tests/test_widget.py": "def test_toggle():\n    pass\n"}
        code, out = lint(
            self._spec(lane="standard", extra=FILES_SECTION), files=files, verify=True
        )
        self.assertEqual(code, 1)
        self.assertIn("was to be created and does not exist", out)


if __name__ == "__main__":
    unittest.main()
