# Anima — Makefile
#
# Build and tooling targets for the Anima PDF reader.
# Swift UI + Python annotation backend (fitz/PyMuPDF).

# --- Variables ---
VENV_DIR = .venv
VENV_ACTIVATE = $(VENV_DIR)/bin/activate
ACTIVATE = . $(VENV_ACTIVATE)
PIP = $(ACTIVATE) && pip
SETUP_STAMP = $(VENV_DIR)/.setup_stamp

# Swift source files
SWIFT_SRC = Anima/main.swift Anima/AppDelegate.swift Anima/AnimaPDFView.swift Anima/FitzBridge.swift
SWIFT_OUT = anima
SWIFT_FRAMEWORKS = -framework Cocoa -framework Quartz

# --- Phony targets ---
.PHONY: all setup build run clean showtree gentree filesdump help

# Default target
all: setup build

# --- Python Virtual Environment ---

$(VENV_ACTIVATE):
	python3 -m venv $(VENV_DIR)

$(SETUP_STAMP): $(VENV_ACTIVATE) tools/requirements.txt
	@echo "--- Installing Python dependencies ---"
	$(PIP) install -r tools/requirements.txt
	@echo "--- Setup complete ---"
	@touch $(SETUP_STAMP)

setup: $(SETUP_STAMP) ## Create venv and install Python dependencies

# --- Swift Build ---

build: $(SWIFT_SRC) ## Compile Swift sources into ./anima binary
	@echo "--- Building Anima ---"
	swiftc -o $(SWIFT_OUT) $(SWIFT_FRAMEWORKS) $(SWIFT_SRC)
	@echo "--- Build complete: ./$(SWIFT_OUT) ---"

run: build setup ## Build and run Anima (PDF must be at ./data/input.pdf)
	./$(SWIFT_OUT)

# --- Testing ---

test: $(SETUP_STAMP) ## Run Python tests (quiet mode)
	$(ACTIVATE) && pytest -q

test-verbose: $(SETUP_STAMP) ## Run Python tests with verbose output
	$(ACTIVATE) && pytest -v -s

# --- Utility Targets ---

clean: ## Remove build output, venv, cache, and tmp files
	rm -f $(SWIFT_OUT)
	rm -rf $(VENV_DIR) .pytest_cache tmp
	find . -name "__pycache__" -type d -prune -exec rm -rf {} +

showtree: ## Show project directory structure
	@tree -I "node_modules|dist|build|.git|.idea|.vscode|.venv|__pycache__|tmp|cache|*egg-info" -L 3

gentree: ## Save tree structure to tmp/project-tree.txt
	@mkdir -p tmp
	@tree -I "node_modules|dist|build|.git|.idea|.vscode|.venv|__pycache__|tmp|cache|*egg-info" > tmp/project-tree.txt
	@echo "Project tree saved to tmp/project-tree.txt"

filesdump: gentree ## Create context dump for LLMs
	@echo "--- Generating filesdump ---"
	$(ACTIVATE) && python tools/concat_files.py manifest.lst > tmp/filesdump.txt
	@echo "Filesdump created at tmp/filesdump.txt"

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
