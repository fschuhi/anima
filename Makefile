# Anima — Makefile
#
# Build and tooling targets for the Anima PDF reader.
# Swift UI + Python annotation backend (fitz/PyMuPDF).
#
# Note on macOS app copies:
# Having multiple Anima.app copies with the same bundle identifier
# (for example on Desktop, in Downloads, or from older builds) can confuse
# Launch Services / Finder "Open With" behavior.
#
# If PDF opening via Finder behaves strangely, inspect Launch Services with:
#   make ls-anima
# or manually:
#   /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | grep -A 6 -B 6 "com.fschuhi.Anima"

# --- Variables ---
VENV_DIR = .venv
VENV_ACTIVATE = $(VENV_DIR)/bin/activate
ACTIVATE = . $(VENV_ACTIVATE)
PIP = $(ACTIVATE) && pip
SETUP_STAMP = $(VENV_DIR)/.setup_stamp

PROJECT = Anima/Anima.xcodeproj
SCHEME = Anima
CONFIGURATION = Debug
APP_NAME = Anima.app
BUNDLE_ID = com.fschuhi.Anima

# --- Phony targets ---
.PHONY: all setup build run clean format showtree gentree filesdump help test test-verbose print-app-path open-app open-pdf ls-anima

# Default target
all: setup

# --- Python Virtual Environment ---

$(VENV_ACTIVATE):
	python3 -m venv $(VENV_DIR)

$(SETUP_STAMP): $(VENV_ACTIVATE) tools/requirements.txt
	@echo "--- Installing Python dependencies ---"
	$(PIP) install -r tools/requirements.txt
	@echo "--- Setup complete ---"
	@touch $(SETUP_STAMP)

setup: $(SETUP_STAMP) ## Create venv and install Python dependencies

# --- Swift Build (command-line, without Xcode) ---
# Note: swiftc builds won't work with @main AppDelegate (needs Xcode).
# These targets are kept for reference but Xcode (Cmd+R) is the normal build path.

# --- Testing ---

test: $(SETUP_STAMP) ## Run Python tests (quiet mode)
	$(ACTIVATE) && pytest -q

test-verbose: $(SETUP_STAMP) ## Run Python tests with verbose output
	$(ACTIVATE) && pytest -v -s

# --- Code Formatting ---

format: ## Format Swift (SwiftFormat) and Python (black) files
	@echo "--- Formatting Swift ---"
	swiftformat Anima/Anima/ --swiftversion 6.0
	@echo "--- Formatting Python ---"
	$(ACTIVATE) && black tools/ tests/

# --- App helpers ---

print-app-path: ## Print the current Xcode-built app path
	@TARGET_BUILD_DIR=$$(xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -showBuildSettings 2>/dev/null | sed -n 's/^[[:space:]]*TARGET_BUILD_DIR = //p' | head -n 1); \
	if [ -z "$$TARGET_BUILD_DIR" ]; then \
		echo "Could not determine TARGET_BUILD_DIR."; \
		echo "Check PROJECT and SCHEME in the Makefile."; \
		exit 1; \
	fi; \
	echo "$$TARGET_BUILD_DIR/$(APP_NAME)"

open-app: ## Open the current Xcode-built Anima.app
	@TARGET_BUILD_DIR=$$(xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -showBuildSettings 2>/dev/null | sed -n 's/^[[:space:]]*TARGET_BUILD_DIR = //p' | head -n 1); \
	if [ -z "$$TARGET_BUILD_DIR" ]; then \
		echo "Could not determine TARGET_BUILD_DIR."; \
		echo "Check PROJECT and SCHEME in the Makefile."; \
		exit 1; \
	fi; \
	APP_PATH="$$TARGET_BUILD_DIR/$(APP_NAME)"; \
	if [ ! -d "$$APP_PATH" ]; then \
		echo "App not found at: $$APP_PATH"; \
		echo "Build and run Anima once in Xcode first."; \
		exit 1; \
	fi; \
	open "$$APP_PATH"

open-pdf: ## Open the dev PDF with the current Xcode-built app
	@TARGET_BUILD_DIR=$$(xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -showBuildSettings 2>/dev/null | sed -n 's/^[[:space:]]*TARGET_BUILD_DIR = //p' | head -n 1); \
	if [ -z "$$TARGET_BUILD_DIR" ]; then \
		echo "Could not determine TARGET_BUILD_DIR."; \
		echo "Check PROJECT and SCHEME in the Makefile."; \
		exit 1; \
	fi; \
	APP_PATH="$$TARGET_BUILD_DIR/$(APP_NAME)"; \
	if [ ! -d "$$APP_PATH" ]; then \
		echo "App not found at: $$APP_PATH"; \
		echo "Build and run Anima once in Xcode first."; \
		exit 1; \
	fi; \
	open -a "$$APP_PATH" "data/input.pdf"

ls-anima: ## Show Launch Services registrations for Anima
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | grep -A 6 -B 6 "$(BUNDLE_ID)" || true

# --- Utility Targets ---

clean: ## Remove venv, cache, and tmp files
	rm -rf $(VENV_DIR) .pytest_cache tmp
	find . -name "__pycache__" -type d -prune -exec rm -rf {} +

showtree: ## Show project directory structure
	@tree -I "node_modules|dist|build|.git|.idea|.vscode|.venv|__pycache__|tmp|cache|*egg-info|DerivedData|xcuserdata" -L 3

gentree: ## Save tree structure to tmp/project_tree.txt
	@mkdir -p tmp
	@tree -I "node_modules|dist|build|.git|.idea|.vscode|.venv|__pycache__|tmp|cache|*egg-info|DerivedData|xcuserdata" > tmp/project_tree.txt
	@echo "Project tree saved to tmp/project_tree.txt"

filesdump: gentree ## Create context dump for LLMs
	@echo "--- Generating filesdump ---"
	$(ACTIVATE) && python tools/concat_files.py manifest.lst > tmp/filesdump.txt
	@echo "Filesdump created at tmp/filesdump.txt"

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
