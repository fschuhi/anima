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


def list_bookmarks(run_helper, pdf_path):
    """Call list-bookmarks and decode its JSON stdout."""
    result = run_helper(
        "list-bookmarks",
        "--file",
        str(pdf_path),
    )
    assert result.returncode == 0, f"Helper failed: {result.stderr}"
    return json.loads(result.stdout)


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

    def test_clear_comment_on_popupless_annotation(self, test_pdf, run_helper):
        """Clearing a comment on a popup-less annotation must not resurrect it.

        Companion to test_clear_comment, which covers the popup-HAVING path:
        add-highlight always creates a popup, so cmd_edit_comment's
        popup-creation branch (and its second annot.update()) is skipped there.
        This test covers the gap. With no popup, cmd_edit_comment runs a SECOND
        annot.update() AFTER the xref-level /Contents clear. We pin that this
        second update() does not rewrite the old comment back from the
        still-in-memory info dict.

        The precondition -- a highlight that carries a comment but has no popup
        -- cannot be produced by add-highlight, so we build it with fitz.
        """
        test_uuid = fresh_uuid()

        # --- Setup: build a popup-less highlight WITH a comment, via fitz ---
        # add-highlight always sets a popup, so the helper cannot create this
        # precondition; we build it directly and deliberately skip set_popup().
        quad = QUAD_WITH_COMMENT
        doc = fitz.open(test_pdf)
        page = doc[TEST_PAGE]
        annot = page.add_highlight_annot(
            quads=[
                fitz.Quad(
                    fitz.Point(quad["x0"], quad["y0"]),  # top-left
                    fitz.Point(quad["x1"], quad["y0"]),  # top-right
                    fitz.Point(quad["x0"], quad["y1"]),  # bottom-left
                    fitz.Point(quad["x1"], quad["y1"]),  # bottom-right
                )
            ]
        )
        info = annot.info
        info["content"] = "Temporary comment"
        annot.set_info(info)
        annot.update()  # no set_popup() -- a popup-less fixture is the point
        doc.xref_set_key(annot.xref, "NM", f"({test_uuid})")
        doc.save(str(test_pdf), incremental=True, encryption=fitz.PDF_ENCRYPT_KEEP)
        doc.close()

        # --- Guard the precondition: comment present, and no popup ---
        doc = fitz.open(test_pdf)
        _, annot = find_annot_by_uuid(doc, test_uuid)
        assert annot is not None, "Setup failed: fixture annotation not found"
        assert annot.info.get("content") == "Temporary comment"
        assert not annot.has_popup, "Setup failed: fixture must have no popup"
        doc.close()

        # --- Clear the comment via the helper (the popup-less edit path) ---
        result = run_helper(
            "edit-comment",
            "--file",
            str(test_pdf),
            "--uuid",
            test_uuid,
            "--comment",
            "",
        )
        assert result.returncode == 0, f"Helper failed: {result.stderr}"

        # --- Verify: highlight survives, comment is gone (not resurrected) ---
        doc = fitz.open(test_pdf)
        _, annot = find_annot_by_uuid(doc, test_uuid)
        assert annot is not None, "Highlight should still exist after clearing comment"
        assert annot.info.get("content", "") == ""

        # Pin the xref-clear ordering: the second annot.update() in the
        # popup-creation branch must not rewrite /Contents from stale text.
        contents_type, contents_value = doc.xref_get_key(annot.xref, "Contents")
        assert (
            contents_value == ""
        ), f"/Contents not empty at xref level: ({contents_type!r}, {contents_value!r})"
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
#  Bookmark persistence
# ---------------------------------------------------------------------------


class TestBookmarks:
    """Tests for catalog-backed bookmark persistence and CLI behavior."""

    def test_list_missing_bookmarks_returns_empty_array(self, test_pdf, run_helper):
        """A PDF without Anima's private catalog key lists no bookmarks."""
        assert list_bookmarks(run_helper, test_pdf) == []

    def test_set_bookmark_roundtrip_and_case_insensitive_upsert(self, test_pdf, run_helper):
        """Setting the same name with different casing updates one stored entry."""
        first_result = run_helper(
            "set-bookmark",
            "--file",
            str(test_pdf),
            "--name",
            "Endnotes Start",
            "--page",
            "1",
        )
        assert first_result.returncode == 0, f"Helper failed: {first_result.stderr}"

        assert list_bookmarks(run_helper, test_pdf) == [{"name": "Endnotes Start", "page": 1}]

        # This is a UI-independent helper contract: the newer spelling and
        # page win, while uniqueness remains case-insensitive.
        update_result = run_helper(
            "set-bookmark",
            "--file",
            str(test_pdf),
            "--name",
            "ENDNOTES start",
            "--page",
            "0",
        )
        assert update_result.returncode == 0, f"Helper failed: {update_result.stderr}"

        assert list_bookmarks(run_helper, test_pdf) == [{"name": "ENDNOTES start", "page": 0}]

    def test_delete_bookmark_roundtrip(self, test_pdf, run_helper):
        """Deleting by a differently cased name removes the matching bookmark."""
        set_result = run_helper(
            "set-bookmark",
            "--file",
            str(test_pdf),
            "--name",
            "Important Figure",
            "--page",
            "1",
        )
        assert set_result.returncode == 0, f"Helper failed: {set_result.stderr}"

        delete_result = run_helper(
            "delete-bookmark",
            "--file",
            str(test_pdf),
            "--name",
            "important figure",
        )
        assert delete_result.returncode == 0, f"Helper failed: {delete_result.stderr}"

        assert list_bookmarks(run_helper, test_pdf) == []

    def test_delete_nonexistent_bookmark_fails(self, test_pdf, run_helper):
        """Deleting a name that has no stored bookmark must fail clearly."""
        result = run_helper(
            "delete-bookmark",
            "--file",
            str(test_pdf),
            "--name",
            "No Such Bookmark",
        )

        assert result.returncode != 0
        assert "not found" in result.stderr.lower()

    def test_set_bookmark_rejects_page_outside_zero_based_range(self, test_pdf, run_helper):
        """Bookmark persistence uses fitz-native 0-based page indices."""
        doc = fitz.open(test_pdf)
        page_count = doc.page_count
        doc.close()

        result = run_helper(
            "set-bookmark",
            "--file",
            str(test_pdf),
            "--name",
            "Invalid Page",
            "--page",
            str(page_count),
        )

        assert result.returncode != 0
        assert "out of range" in result.stderr.lower()

    def test_bookmarks_leave_existing_native_toc_intact(self, tmp_path, run_helper):
        """Writing /AnimaBookmarks must not alter the PDF's native outline."""
        pdf_path = tmp_path / "document_with_toc.pdf"

        # Build a small, ordinary PDF with its own native outline. This avoids
        # relying on whether the shared annotation fixture happens to have one.
        doc = fitz.open()
        doc.new_page()
        doc.new_page()
        original_toc = [
            [1, "Existing Chapter", 1],
            [2, "Existing Section", 2],
        ]
        doc.set_toc(original_toc)
        doc.save(pdf_path)
        doc.close()

        set_result = run_helper(
            "set-bookmark",
            "--file",
            str(pdf_path),
            "--name",
            "Endnotes Start",
            "--page",
            "1",
        )
        assert set_result.returncode == 0, f"Helper failed: {set_result.stderr}"

        doc = fitz.open(pdf_path)
        assert doc.get_toc() == original_toc
        catalog_value_type, catalog_value = doc.xref_get_key(
            doc.pdf_catalog(),
            "AnimaBookmarks",
        )
        doc.close()

        assert catalog_value_type == "string"
        assert json.loads(catalog_value) == [{"name": "Endnotes Start", "page": 1}]


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
