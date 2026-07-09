#!/usr/bin/env python3
from pathlib import Path
import sys

# XML Template for each file
FILE_TEMPLATE = """<document path="{path}">
{content}
</document>
"""

# XML Template for error markers (unreadable or missing files)
ERROR_TEMPLATE = """<error path="{path}">{reason}</error>
"""

# Rough heuristic: ~4 characters per token for typical code/prose mixes
CHARS_PER_TOKEN = 4


def concat(list_file: Path, out):
    if not list_file.exists():
        out.write(f"Error: Cannot read file '{list_file}'\n")
        return 1

    try:
        # utf-8-sig handles potential BOMs
        lines = list_file.read_text(encoding="utf-8-sig").splitlines()
    except (OSError, UnicodeDecodeError) as e:
        out.write(f"Error: Cannot read file '{list_file}': {e}\n")
        return 1

    included = 0
    errors = []  # (path, reason) tuples
    total_chars = 0

    # Write the opening root tag
    out.write("<documents>\n")

    for raw in lines:
        name = raw.strip()

        # Skip empty lines and comments
        if not name or name.startswith("#"):
            continue

        p = Path(name)
        if p.exists() and p.is_file():
            try:
                content = p.read_text(encoding="utf-8")
                # Optional: Escape XML special characters if necessary,
                # though LLMs are usually robust enough with raw code in these tags.
                # For strict correctness, one might wrap content in CDATA,
                # but simple tag wrapping is the current standard for prompts.
                out.write(FILE_TEMPLATE.format(path=name, content=content))
                included += 1
                total_chars += len(content)
            except (OSError, UnicodeDecodeError) as e:
                reason = f"Cannot read file: {e}"
                out.write(ERROR_TEMPLATE.format(path=name, reason=reason))
                errors.append((name, reason))
        else:
            reason = "File not found"
            out.write(ERROR_TEMPLATE.format(path=name, reason=reason))
            errors.append((name, reason))

    # Write the closing root tag
    out.write("</documents>\n")

    # Summary to stderr (keeps stdout clean for redirection)
    est_tokens = total_chars // CHARS_PER_TOKEN
    sys.stderr.write(
        f"concat_files: {included} file(s) included, "
        f"{len(errors)} error(s), "
        f"~{est_tokens:,} tokens ({total_chars:,} chars)\n"
    )
    for path, reason in errors:
        sys.stderr.write(f"  ERROR {path}: {reason}\n")

    return 0


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]

    if len(argv) != 1 or argv[0] in {"-h", "--help"}:
        sys.stderr.write("Usage: python tools/concat_files.py <filelist>\n")
        return 2

    list_file = Path(argv[0])
    return concat(list_file, sys.stdout)


if __name__ == "__main__":
    sys.exit(main())
