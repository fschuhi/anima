"""
Shared pytest fixtures for anima_helper.py tests.

Fixtures:
    test_pdf    — fresh copy of data/input_original.pdf per test (in tmp_path).
                  Optionally copies to tmp/tests/ after the test when
                  ANIMA_KEEP_TEST_OUTPUT=1 is set.
    run_helper  — subprocess wrapper that calls anima_helper.py via the venv
                  Python, returning a CompletedProcess with stdout/stderr/returncode.
"""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

# --- Path resolution ---
# conftest.py lives in tests/, project root is one level up.
PROJECT_ROOT = Path(__file__).resolve().parent.parent
HELPER_PATH = PROJECT_ROOT / "tools" / "anima_helper.py"
PYTHON_PATH = PROJECT_ROOT / ".venv" / "bin" / "python3"
SOURCE_PDF = PROJECT_ROOT / "data" / "input_original.pdf"
KEEP_OUTPUT_DIR = PROJECT_ROOT / "tmp" / "tests"


@pytest.fixture
def test_pdf(tmp_path, request):
    """
    Copy input_original.pdf to a per-test temporary directory.

    Returns the Path to the copy. The original is never modified.

    When the environment variable ANIMA_KEEP_TEST_OUTPUT=1 is set,
    the (possibly modified) PDF is copied to tmp/tests/<test_name>.pdf
    after the test completes — useful for manual inspection with a
    PDF viewer.
    """
    assert SOURCE_PDF.exists(), f"Test fixture not found: {SOURCE_PDF}"

    dest = tmp_path / "input_original.pdf"
    shutil.copy2(SOURCE_PDF, dest)

    yield dest

    # --- Optional: copy result to tmp/tests/ for inspection ---
    if os.environ.get("ANIMA_KEEP_TEST_OUTPUT") == "1" and dest.exists():
        KEEP_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        test_name = request.node.name
        shutil.copy2(dest, KEEP_OUTPUT_DIR / f"{test_name}.pdf")


@pytest.fixture
def run_helper():
    """
    Subprocess wrapper for anima_helper.py.

    Usage:
        result = run_helper("add-highlight", "--file", str(pdf), ...)
        assert result.returncode == 0

    Returns subprocess.CompletedProcess with .stdout, .stderr, .returncode.
    """
    assert PYTHON_PATH.exists(), f"Python venv not found at {PYTHON_PATH}. Run 'make setup' first."
    assert HELPER_PATH.exists(), f"Helper script not found: {HELPER_PATH}"

    def _run(*args: str) -> subprocess.CompletedProcess:
        cmd = [str(PYTHON_PATH), str(HELPER_PATH)] + list(args)
        return subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
        )

    return _run
