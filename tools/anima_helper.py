#!/usr/bin/env python3
"""
anima_helper.py — CLI tool for managing PDF highlight annotations and bookmarks via fitz.

Called by the Anima Swift app (or manually from Terminal) to create, edit,
and delete highlight annotations using fitz's incremental save, which
preserves existing annotations intact.

Coordinate contract:
    All coordinates are in fitz space (origin top-left, y increases downward).
    Callers using PDFKit must flip y before calling:
        y_fitz = page_height - y_pdfkit

Examples:
    # Add a highlight (two lines of selected text):
    python3 anima_helper.py add-highlight \
        --file paper.pdf --page 2 --uuid "abc-123" \
        --quads '[{"x0":72,"y0":120,"x1":510,"y1":135},{"x0":72,"y0":136,"x1":410,"y1":151}]'

    # Add a highlight with a comment:
    python3 anima_helper.py add-highlight \
        --file paper.pdf --page 2 --uuid "abc-123" \
        --quads '[{"x0":72,"y0":120,"x1":510,"y1":135}]' \
        --comment "Important finding"

    # Edit an existing highlight's comment:
    python3 anima_helper.py edit-comment \
        --file paper.pdf --uuid "abc-123" --comment "Updated comment"

    # Remove the comment but keep the highlight:
    python3 anima_helper.py edit-comment \
        --file paper.pdf --uuid "abc-123" --comment ""

    # Delete a highlight entirely:
    python3 anima_helper.py delete-highlight \
        --file paper.pdf --uuid "abc-123"

    # List bookmarks stored in Anima's private PDF catalog key:
    python3 anima_helper.py list-bookmarks --file paper.pdf

    # Add or move a bookmark. Page is fitz-native and 0-based:
    python3 anima_helper.py set-bookmark \
        --file paper.pdf --name "Endnotes Start" --page 141

    # Delete a bookmark by case-insensitive name:
    python3 anima_helper.py delete-bookmark \
        --file paper.pdf --name "Endnotes Start"
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import fitz

# ===============================================================
#  Anima highlight defaults
# ===============================================================
HIGHLIGHT_COLOR = [1.0, 0.75, 0.80]  # light pink
HIGHLIGHT_OPACITY = 0.4
DEFAULT_AUTHOR = "fschuhi"

# Popup dimensions (placed off-page right margin; visible in other viewers)
POPUP_WIDTH = 200
POPUP_HEIGHT = 100

# Private PDF catalog key for Anima's named page bookmarks. This deliberately
# does not use the document's native /Outlines tree, which belongs to the PDF's
# own table of contents when one exists.
BOOKMARKS_CATALOG_KEY = "AnimaBookmarks"


# ===============================================================
#  Helpers
# ===============================================================
def _pdf_date_now() -> str:
    """Return current UTC time as PDF date string: D:YYYYMMDDHHmmSS+00'00'"""
    now = datetime.now(timezone.utc)
    return now.strftime("D:%Y%m%d%H%M%S+00'00'")


def _find_annot_by_uuid(doc: fitz.Document, uuid: str):
    """
    Search all pages for an annotation with NM (unique name) matching uuid.
    Returns (page, annot) tuple or (None, None) if not found.
    """
    for page in doc:
        for annot in page.annots():
            if annot.info.get("id") == uuid:
                return page, annot
    return None, None


def _quads_from_json(quads_json: str):
    """
    Parse quads JSON array into list of fitz.Quad objects.

    Each element: {"x0": float, "y0": float, "x1": float, "y1": float}
    These represent bounding rectangles per selection line (fitz coordinates).
    Converted to fitz.Quad with four corners:
        top-left, top-right, bottom-left, bottom-right
    """
    items = json.loads(quads_json)
    quads = []
    for q in items:
        x0, y0, x1, y1 = q["x0"], q["y0"], q["x1"], q["y1"]
        quads.append(
            fitz.Quad(
                fitz.Point(x0, y0),  # top-left
                fitz.Point(x1, y0),  # top-right
                fitz.Point(x0, y1),  # bottom-left
                fitz.Point(x1, y1),  # bottom-right
            )
        )
    return quads


def _read_bookmarks(doc: fitz.Document) -> list[dict[str, object]]:
    """
    Read Anima's bookmark array from the PDF catalog.

    The catalog always exists, unlike an optional /Info dictionary. A missing
    private key simply means this PDF has no Anima bookmarks yet.
    """
    value_type, value = doc.xref_get_key(doc.pdf_catalog(), BOOKMARKS_CATALOG_KEY)

    if value_type == "null":
        return []

    if value_type != "string":
        raise ValueError(
            f"invalid /{BOOKMARKS_CATALOG_KEY} value: expected PDF string, got {value_type}"
        )

    bookmarks = json.loads(value)

    if not isinstance(bookmarks, list):
        raise ValueError(f"invalid /{BOOKMARKS_CATALOG_KEY} value: expected JSON array")

    for bookmark in bookmarks:
        if not isinstance(bookmark, dict):
            raise ValueError(f"invalid /{BOOKMARKS_CATALOG_KEY} entry: expected object")

        name = bookmark.get("name")
        page = bookmark.get("page")

        if not isinstance(name, str) or not isinstance(page, int):
            raise ValueError(
                f"invalid /{BOOKMARKS_CATALOG_KEY} entry: expected string name and integer page"
            )

    return bookmarks


def _write_bookmarks(doc: fitz.Document, bookmarks: list[dict[str, object]]) -> None:
    """Write the complete bookmark array to Anima's private PDF catalog key."""
    serialized_bookmarks = json.dumps(bookmarks, ensure_ascii=False)
    doc.xref_set_key(
        doc.pdf_catalog(),
        BOOKMARKS_CATALOG_KEY,
        fitz.get_pdf_str(serialized_bookmarks),
    )


def _validate_bookmark_page(doc: fitz.Document, page: int) -> None:
    """Reject pages outside fitz's native 0-based page-index range."""
    if page < 0 or page >= doc.page_count:
        raise ValueError(
            f"page {page} out of range (document has {doc.page_count} pages, indexed from 0)"
        )


# ===============================================================
#  Subcommands
# ===============================================================
def cmd_add_highlight(args):
    """Create a new highlight annotation."""
    pdf_path = Path(args.file)
    if not pdf_path.exists():
        print(f"Error: file not found: {pdf_path}", file=sys.stderr)
        return 1

    doc = fitz.open(pdf_path)

    if args.page < 0 or args.page >= doc.page_count:
        print(
            f"Error: page {args.page} out of range (document has {doc.page_count} pages)",
            file=sys.stderr,
        )
        return 1

    page = doc[args.page]
    quads = _quads_from_json(args.quads)

    if not quads:
        print("Error: no quads provided", file=sys.stderr)
        return 1

    # Create the highlight annotation
    annot = page.add_highlight_annot(quads=quads)
    annot.set_colors(stroke=HIGHLIGHT_COLOR)
    annot.set_opacity(HIGHLIGHT_OPACITY)

    # Set annotation metadata
    now = _pdf_date_now()
    info = annot.info
    info["title"] = args.author
    info["subject"] = "Highlight"
    info["creationDate"] = now
    info["modDate"] = now
    if args.comment:
        info["content"] = args.comment
    annot.set_info(info)
    annot.update()

    # Set the UUID via xref (fitz ignores 'id' in set_info)
    doc.xref_set_key(annot.xref, "NM", f"({args.uuid})")

    # Add popup for comment visibility in other PDF viewers
    annot_rect = annot.rect
    popup_rect = fitz.Rect(
        annot_rect.x1,
        annot_rect.y0,
        annot_rect.x1 + POPUP_WIDTH,
        annot_rect.y0 + POPUP_HEIGHT,
    )
    annot.set_popup(popup_rect)
    annot.update()

    # Incremental save — preserves all existing annotations
    doc.save(str(pdf_path), incremental=True, encryption=fitz.PDF_ENCRYPT_KEEP)
    doc.close()

    print(args.uuid)
    return 0


def cmd_edit_comment(args):
    """Edit the comment on an existing highlight (identified by UUID)."""
    pdf_path = Path(args.file)
    if not pdf_path.exists():
        print(f"Error: file not found: {pdf_path}", file=sys.stderr)
        return 1

    doc = fitz.open(pdf_path)
    page, annot = _find_annot_by_uuid(doc, args.uuid)

    if annot is None:
        print(f"Error: annotation not found: {args.uuid}", file=sys.stderr)
        return 1

    # Preserve the original opacity before update() potentially resets it
    original_opacity = annot.opacity

    info = annot.info
    info["content"] = args.comment
    info["modDate"] = _pdf_date_now()
    annot.set_info(info)

    # Re-apply opacity so update() doesn't reset it
    annot.set_opacity(original_opacity)
    annot.update()

    # fitz's set_info() silently ignores empty strings for "content" —
    # the old value survives both in memory and after save. To actually
    # clear a comment, we must write an empty PDF string "()" directly
    # to the /Contents key via xref. This is the mechanism that makes
    # "clear comment = remove from sidebar" work in Anima's UX.
    if not args.comment:
        doc.xref_set_key(annot.xref, "Contents", "()")

    # Ensure a popup exists (for comment visibility in other viewers)
    if not annot.has_popup:
        annot_rect = annot.rect
        popup_rect = fitz.Rect(
            annot_rect.x1,
            annot_rect.y0,
            annot_rect.x1 + POPUP_WIDTH,
            annot_rect.y0 + POPUP_HEIGHT,
        )
        annot.set_popup(popup_rect)
        annot.update()

    doc.save(str(pdf_path), incremental=True, encryption=fitz.PDF_ENCRYPT_KEEP)
    doc.close()

    print(args.uuid)
    return 0


def cmd_delete_highlight(args):
    """Delete a highlight annotation entirely (identified by UUID)."""
    pdf_path = Path(args.file)
    if not pdf_path.exists():
        print(f"Error: file not found: {pdf_path}", file=sys.stderr)
        return 1

    doc = fitz.open(pdf_path)
    page, annot = _find_annot_by_uuid(doc, args.uuid)

    if annot is None:
        print(f"Error: annotation not found: {args.uuid}", file=sys.stderr)
        return 1

    page.delete_annot(annot)

    doc.save(str(pdf_path), incremental=True, encryption=fitz.PDF_ENCRYPT_KEEP)
    doc.close()

    print(args.uuid)
    return 0


def cmd_list_bookmarks(args):
    """Print Anima's bookmark array as JSON, or [] when no key exists."""
    pdf_path = Path(args.file)
    if not pdf_path.exists():
        print(f"Error: file not found: {pdf_path}", file=sys.stderr)
        return 1

    doc = fitz.open(pdf_path)

    try:
        bookmarks = _read_bookmarks(doc)
    except (json.JSONDecodeError, ValueError) as error:
        doc.close()
        print(f"Error: {error}", file=sys.stderr)
        return 1

    doc.close()

    print(json.dumps(bookmarks, ensure_ascii=False))
    return 0


def cmd_set_bookmark(args):
    """
    Add or update a named page bookmark.

    Names are unique case-insensitively. A matching existing entry is removed
    before the supplied entry is appended, so the supplied spelling and page
    are the authoritative last write.
    """
    pdf_path = Path(args.file)
    if not pdf_path.exists():
        print(f"Error: file not found: {pdf_path}", file=sys.stderr)
        return 1

    doc = fitz.open(pdf_path)

    try:
        _validate_bookmark_page(doc, args.page)
        bookmarks = _read_bookmarks(doc)
    except (json.JSONDecodeError, ValueError) as error:
        doc.close()
        print(f"Error: {error}", file=sys.stderr)
        return 1

    normalized_name = args.name.casefold()
    bookmarks = [
        bookmark for bookmark in bookmarks if str(bookmark["name"]).casefold() != normalized_name
    ]
    bookmarks.append({"name": args.name, "page": args.page})

    _write_bookmarks(doc, bookmarks)
    doc.save(str(pdf_path), incremental=True, encryption=fitz.PDF_ENCRYPT_KEEP)
    doc.close()

    print(args.name)
    return 0


def cmd_delete_bookmark(args):
    """Delete one bookmark by case-insensitive name."""
    pdf_path = Path(args.file)
    if not pdf_path.exists():
        print(f"Error: file not found: {pdf_path}", file=sys.stderr)
        return 1

    doc = fitz.open(pdf_path)

    try:
        bookmarks = _read_bookmarks(doc)
    except (json.JSONDecodeError, ValueError) as error:
        doc.close()
        print(f"Error: {error}", file=sys.stderr)
        return 1

    normalized_name = args.name.casefold()
    updated_bookmarks = [
        bookmark for bookmark in bookmarks if str(bookmark["name"]).casefold() != normalized_name
    ]

    if len(updated_bookmarks) == len(bookmarks):
        doc.close()
        print(f"Error: bookmark not found: {args.name}", file=sys.stderr)
        return 1

    _write_bookmarks(doc, updated_bookmarks)
    doc.save(str(pdf_path), incremental=True, encryption=fitz.PDF_ENCRYPT_KEEP)
    doc.close()

    print(args.name)
    return 0


# ===============================================================
#  CLI setup
# ===============================================================
def main():
    parser = argparse.ArgumentParser(
        description="Anima — PDF highlight annotation and bookmark helper (fitz backend)",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # --- add-highlight ---
    p_add = subparsers.add_parser(
        "add-highlight",
        help="Create a new highlight annotation",
    )
    p_add.add_argument("--file", required=True, help="Path to the PDF file")
    p_add.add_argument("--page", type=int, required=True, help="Page number (0-indexed)")
    p_add.add_argument("--uuid", required=True, help="UUID for the annotation (NM field)")
    p_add.add_argument(
        "--quads",
        required=True,
        help='JSON array of quads: [{"x0":.."y0":.."x1":.."y1":..}, ...]  (fitz coordinates)',
    )
    p_add.add_argument("--comment", default="", help="Optional comment text")
    p_add.add_argument(
        "--author", default=DEFAULT_AUTHOR, help=f"Author (default: {DEFAULT_AUTHOR})"
    )

    # --- edit-comment ---
    p_edit = subparsers.add_parser(
        "edit-comment",
        help="Edit the comment on an existing highlight",
    )
    p_edit.add_argument("--file", required=True, help="Path to the PDF file")
    p_edit.add_argument("--uuid", required=True, help="UUID of the annotation to edit")
    p_edit.add_argument(
        "--comment", required=True, help="New comment text (empty string to remove comment)"
    )

    # --- delete-highlight ---
    p_del = subparsers.add_parser(
        "delete-highlight",
        help="Delete a highlight annotation entirely",
    )
    p_del.add_argument("--file", required=True, help="Path to the PDF file")
    p_del.add_argument("--uuid", required=True, help="UUID of the annotation to delete")

    # --- list-bookmarks ---
    p_list_bookmarks = subparsers.add_parser(
        "list-bookmarks",
        help="List Anima bookmarks stored in the PDF catalog",
    )
    p_list_bookmarks.add_argument("--file", required=True, help="Path to the PDF file")

    # --- set-bookmark ---
    p_set_bookmark = subparsers.add_parser(
        "set-bookmark",
        help="Add or update an Anima bookmark",
    )
    p_set_bookmark.add_argument("--file", required=True, help="Path to the PDF file")
    p_set_bookmark.add_argument("--name", required=True, help="Bookmark name")
    p_set_bookmark.add_argument(
        "--page",
        type=int,
        required=True,
        help="Page number (0-indexed)",
    )

    # --- delete-bookmark ---
    p_delete_bookmark = subparsers.add_parser(
        "delete-bookmark",
        help="Delete an Anima bookmark by name",
    )
    p_delete_bookmark.add_argument("--file", required=True, help="Path to the PDF file")
    p_delete_bookmark.add_argument("--name", required=True, help="Bookmark name")

    args = parser.parse_args()

    if args.command == "add-highlight":
        sys.exit(cmd_add_highlight(args))
    elif args.command == "edit-comment":
        sys.exit(cmd_edit_comment(args))
    elif args.command == "delete-highlight":
        sys.exit(cmd_delete_highlight(args))
    elif args.command == "list-bookmarks":
        sys.exit(cmd_list_bookmarks(args))
    elif args.command == "set-bookmark":
        sys.exit(cmd_set_bookmark(args))
    elif args.command == "delete-bookmark":
        sys.exit(cmd_delete_bookmark(args))


if __name__ == "__main__":
    main()
