"""
Tests for anima_helper.py — the fitz-based annotation backend.

These tests call anima_helper.py via subprocess (same as the Swift app does),
then open the resulting PDF with fitz to verify what was written. This tests
the actual CLI contract, not internal Python functions.

Quad coordinates used here come from real annotations created in Anima on
page 2 (fitz page index 1) of input_original.pdf:
    - QUAD_NO_COMMENT: "The teachings of Buddha,..." (no comment)
    - QUAD_WITH_COMMENT: "The purpose of these teachings..." (with comment)
"""

import json
import uuid

import fitz
import pytest

# ---------------------------------------------------------------------------
#  Test constants — real coordinates from input_original_also_page2.pdf
# ---------------------------------------------------------------------------

# Page index 1 (fitz 0-indexed) = "page 2" of the Albini paper.
TEST_PAGE = 1

# Quad for "The teachings of Buddha,..." — single-line highlight, no comment.
QUAD_NO_COMMENT = {"x0": 64.08, "y0": 154.97, "x1": 184.87, "y1": 168.26}

# Quad for "The purpose of these teachings..." — single-line highlight.
QUAD_WITH_COMMENT = {"x0": 238.98, "y0": 205.91, "x1": 403.43, "y1": 219.20}

# Expected highlight appearance (must match anima_helper.py constants)
EXPECTED_COLOR = [1.0, 0.75, 0.80]
EXPECTED_OPACITY = 0.4
EXPECTED_AUTHOR = "fschuhi"

# Pre-existing annotations on page 0 of input_original.pdf
PREEXISTING_UUIDS = [
    "f6680769-4b50-46e2-af936dd7f77ed53b",
    "29a6dc38-2486-403f-ac209eb42164897f",
]


# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------


def make_quads_json(*quads: dict) -> str:
    """Serialize quad dicts to the JSON string format expected by --quads."""
    return json.dumps(list(quads))


def fresh_uuid() -> str:
    """Generate a new UUID in the same format the Swift app uses."""
    return str(uuid.uuid4()).lower()


def find_annot_by_uuid(doc: fitz.Document, target_uuid: str):
    """Find an annotation by its /NM field across all pages. Returns (page, annot) or (None, None)."""
    for page in doc:
        for annot in page.annots():
            if annot.info.get("id") == target_uuid:
                return page, annot
    return None, None


# ---------------------------------------------------------------------------
#  Round-trip tests
# ---------------------------------------------------------------------------


class TestAddHighlight:
    """Tests for the add-highlight subcommand."""

    def test_basic_roundtrip(self, test_pdf, run_helper):
        """Create a highlight on page 2, verify all fields with fitz."""
        test_uuid = fresh_uuid()
        quads_json = make_quads_json(QUAD_NO_COMMENT)

        result = run_helper(
            "add-highlight",
            "--file",
            str(test_pdf),
            "--page",
            str(TEST_PAGE),
            "--uuid",
            test_uuid,
            "--quads",
            quads_json,
        )
        assert result.returncode == 0, f"Helper failed: {result.stderr}"
        assert test_uuid in result.stdout

        # Verify with fitz
        doc = fitz.open(test_pdf)
        page, annot = find_annot_by_uuid(doc, test_uuid)

        assert annot is not None, f"Annotation {test_uuid} not found in PDF"
        assert page.number == TEST_PAGE

        # Color (tolerance for float rounding)
        stroke = annot.colors.get("stroke", [])
        assert len(stroke) == 3
        for actual, expected in zip(stroke, EXPECTED_COLOR):
            assert abs(actual - expected) < 0.01, f"Color mismatch: {stroke} vs {EXPECTED_COLOR}"

        # Opacity
        assert abs(annot.opacity - EXPECTED_OPACITY) < 0.01

        # Author
        assert annot.info.get("title") == EXPECTED_AUTHOR

        # Comment should be empty (no --comment flag)
        assert annot.info.get("content", "") == ""

        # Dates should be set
        assert annot.info.get("creationDate", "") != ""
        assert annot.info.get("modDate", "") != ""

        doc.close()

    def test_with_comment(self, test_pdf, run_helper):
        """Create a highlight with a comment in one step."""
        test_uuid = fresh_uuid()
        comment = "Here is a comment on page 2"
        quads_json = make_quads_json(QUAD_WITH_COMMENT)

        result = run_helper(
            "add-highlight",
            "--file",
            str(test_pdf),
            "--page",
            str(TEST_PAGE),
            "--uuid",
            test_uuid,
            "--quads",
            quads_json,
            "--comment",
            comment,
        )
        assert result.returncode == 0, f"Helper failed: {result.stderr}"

        doc = fitz.open(test_pdf)
        _, annot = find_annot_by_uuid(doc, test_uuid)
        assert annot is not None

        assert annot.info.get("content") == comment
        doc.close()

    def test_multi_quad(self, test_pdf, run_helper):
        """Create a highlight spanning two quads (two lines of text)."""
        test_uuid = fresh_uuid()
        quads_json = make_quads_json(QUAD_NO_COMMENT, QUAD_WITH_COMMENT)

        result = run_helper(
            "add-highlight",
            "--file",
            str(test_pdf),
            "--page",
            str(TEST_PAGE),
            "--uuid",
            test_uuid,
            "--quads",
            quads_json,
        )
        assert result.returncode == 0, f"Helper failed: {result.stderr}"

        doc = fitz.open(test_pdf)
        _, annot = find_annot_by_uuid(doc, test_uuid)
        assert annot is not None

        # Should have 2 quads = 8 vertices
        verts = annot.vertices
        assert len(verts) == 8, f"Expected 8 vertices (2 quads), got {len(verts)}"

        doc.close()


class TestEditComment:
    """Tests for the edit-comment subcommand."""

    def test_add_then_edit(self, test_pdf, run_helper):
        """Create a highlight, then edit its comment. Verify content update and opacity survival."""
        test_uuid = fresh_uuid()
        quads_json = make_quads_json(QUAD_NO_COMMENT)

        # Step 1: Create highlight (no comment)
        result = run_helper(
            "add-highlight",
            "--file",
            str(test_pdf),
            "--page",
            str(TEST_PAGE),
            "--uuid",
            test_uuid,
            "--quads",
            quads_json,
        )
        assert result.returncode == 0

        # Step 2: Edit comment
        new_comment = "Updated comment text"
        result = run_helper(
            "edit-comment",
            "--file",
            str(test_pdf),
            "--uuid",
            test_uuid,
            "--comment",
            new_comment,
        )
        assert result.returncode == 0, f"Helper failed: {result.stderr}"

        # Step 3: Verify
        doc = fitz.open(test_pdf)
        _, annot = find_annot_by_uuid(doc, test_uuid)
        assert annot is not None
        assert annot.info.get("content") == new_comment

        # Note: modDate assertion removed — create and edit can happen within
        # the same second (PDF dates have only second-level resolution), making
        # a "date changed" check a timing race. The content update above is
        # the meaningful verification.

        # Opacity must survive the edit (this was a real bug — annot.update() can reset it)
        assert (
            abs(annot.opacity - EXPECTED_OPACITY) < 0.01
        ), f"Opacity changed after edit: {annot.opacity} (expected ~{EXPECTED_OPACITY})"

        doc.close()

    def test_clear_comment(self, test_pdf, run_helper):
        """Edit with empty string should clear the comment but keep the highlight.

        This is load-bearing for the Anima UX: clearing a comment removes the
        card from the sidebar (SidebarExtractor skips empty comments), which
        is the mechanism for "remove comment, keep highlight".

        Bug discovered by this test: fitz's set_info() silently ignores empty
        strings for "content". The fix uses xref_set_key to write an empty
        PDF string "()" directly to /Contents.
        """
        test_uuid = fresh_uuid()
        quads_json = make_quads_json(QUAD_WITH_COMMENT)

        # Create with comment
        run_helper(
            "add-highlight",
            "--file",
            str(test_pdf),
            "--page",
            str(TEST_PAGE),
            "--uuid",
            test_uuid,
            "--quads",
            quads_json,
            "--comment",
            "Temporary comment",
        )

        # Clear it
        result = run_helper(
            "edit-comment",
            "--file",
            str(test_pdf),
            "--uuid",
            test_uuid,
            "--comment",
            "",
        )
        assert result.returncode == 0

        # Verify: annotation exists, comment is empty
        doc = fitz.open(test_pdf)
        _, annot = find_annot_by_uuid(doc, test_uuid)
        assert annot is not None, "Highlight should still exist after clearing comment"
        assert annot.info.get("content", "") == ""
        doc.close()


class TestDeleteHighlight:
    """Tests for the delete-highlight subcommand."""

    def test_delete_roundtrip(self, test_pdf, run_helper):
        """Create a highlight, delete it, verify it's gone."""
        test_uuid = fresh_uuid()
        quads_json = make_quads_json(QUAD_NO_COMMENT)

        # Create
        run_helper(
            "add-highlight",
            "--file",
            str(test_pdf),
            "--page",
            str(TEST_PAGE),
            "--uuid",
            test_uuid,
            "--quads",
            quads_json,
        )

        # Delete
        result = run_helper(
            "delete-highlight",
            "--file",
            str(test_pdf),
            "--uuid",
            test_uuid,
        )
        assert result.returncode == 0, f"Helper failed: {result.stderr}"

        # Verify gone
        doc = fitz.open(test_pdf)
        _, annot = find_annot_by_uuid(doc, test_uuid)
        assert annot is None, f"Annotation {test_uuid} should have been deleted"
        doc.close()


# ---------------------------------------------------------------------------
#  Contract verification
# ---------------------------------------------------------------------------


class TestUUIDContract:
    """Verify the UUID is correctly written to the /NM field via xref."""

    def test_uuid_in_nm_field(self, test_pdf, run_helper):
        """
        The Swift app depends on /NM containing the UUID. anima_helper.py
        writes this via doc.xref_set_key(). Verify at the xref level.
        """
        test_uuid = fresh_uuid()
        quads_json = make_quads_json(QUAD_NO_COMMENT)

        run_helper(
            "add-highlight",
            "--file",
            str(test_pdf),
            "--page",
            str(TEST_PAGE),
            "--uuid",
            test_uuid,
            "--quads",
            quads_json,
        )

        doc = fitz.open(test_pdf)
        _, annot = find_annot_by_uuid(doc, test_uuid)
        assert annot is not None

        # Read /NM directly from the xref (low-level verification)
        nm_value = doc.xref_get_key(annot.xref, "NM")
        # xref_get_key returns a tuple: (type_str, value_str)
        # For a string, type_str is "string" and value_str is the content.
        assert nm_value[0] == "string", f"Expected /NM to be a string, got {nm_value}"
        assert nm_value[1] == test_uuid, f"/NM mismatch: {nm_value[1]} != {test_uuid}"

        doc.close()


class TestIncrementalSavePreservation:
    """Verify that incremental save doesn't damage existing annotations."""

    def test_preserves_existing_annotations(self, test_pdf, run_helper):
        """
        input_original.pdf has 2 pre-existing annotations on page 0.
        After adding a new highlight on page 1, both must still be intact.
        """
        test_uuid = fresh_uuid()
        quads_json = make_quads_json(QUAD_NO_COMMENT)

        # Add a new highlight on page 1 (page 2 of the paper)
        result = run_helper(
            "add-highlight",
            "--file",
            str(test_pdf),
            "--page",
            str(TEST_PAGE),
            "--uuid",
            test_uuid,
            "--quads",
            quads_json,
        )
        assert result.returncode == 0

        # Verify pre-existing annotations on page 0 are untouched
        doc = fitz.open(test_pdf)
        page0 = doc[0]
        page0_annots = list(page0.annots())

        assert (
            len(page0_annots) == 2
        ), f"Expected 2 pre-existing annotations on page 0, got {len(page0_annots)}"

        found_uuids = {a.info.get("id") for a in page0_annots}
        for expected_uuid in PREEXISTING_UUIDS:
            assert (
                expected_uuid in found_uuids
            ), f"Pre-existing annotation {expected_uuid} missing after incremental save"

        # Verify content of the first annotation survived
        for annot in page0_annots:
            if annot.info.get("id") == PREEXISTING_UUIDS[0]:
                assert annot.info.get("content") == "original highlight"
                assert annot.info.get("title") == "fschuhi"
                assert abs(annot.opacity - 0.4) < 0.01

        # And our new annotation is also there
        _, new_annot = find_annot_by_uuid(doc, test_uuid)
        assert new_annot is not None

        doc.close()


# ---------------------------------------------------------------------------
#  Error handling / edge cases
# ---------------------------------------------------------------------------


class TestErrorHandling:
    """Verify that invalid inputs produce non-zero exit codes and stderr messages."""

    def test_invalid_page(self, test_pdf, run_helper):
        """Page number out of range should fail."""
        result = run_helper(
            "add-highlight",
            "--file",
            str(test_pdf),
            "--page",
            "999",
            "--uuid",
            fresh_uuid(),
            "--quads",
            make_quads_json(QUAD_NO_COMMENT),
        )
        assert result.returncode != 0
        assert "out of range" in result.stderr.lower()

    def test_missing_file(self, run_helper):
        """Nonexistent PDF path should fail."""
        result = run_helper(
            "add-highlight",
            "--file",
            "/nonexistent/path/fake.pdf",
            "--page",
            "0",
            "--uuid",
            fresh_uuid(),
            "--quads",
            make_quads_json(QUAD_NO_COMMENT),
        )
        assert result.returncode != 0
        assert "not found" in result.stderr.lower()

    def test_delete_nonexistent_uuid(self, test_pdf, run_helper):
        """Deleting a UUID that doesn't exist should fail."""
        result = run_helper(
            "delete-highlight",
            "--file",
            str(test_pdf),
            "--uuid",
            "00000000-0000-0000-0000-000000000000",
        )
        assert result.returncode != 0
        assert "not found" in result.stderr.lower()

    def test_edit_nonexistent_uuid(self, test_pdf, run_helper):
        """Editing a comment on a nonexistent UUID should fail."""
        result = run_helper(
            "edit-comment",
            "--file",
            str(test_pdf),
            "--uuid",
            "00000000-0000-0000-0000-000000000000",
            "--comment",
            "This should fail",
        )
        assert result.returncode != 0
        assert "not found" in result.stderr.lower()
