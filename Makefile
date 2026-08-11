# AppleNotestoX — fresh-machine entry points.
# Everything here works with Xcode Command Line Tools only (no full Xcode).

SHELL := /bin/bash
VAULT ?=

.DEFAULT_GOAL := help

.PHONY: help doctor build run study notion check clean

help: ## Show this help
	@echo "AppleNotestoX"
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "  VAULT=<path> is required by 'study' and 'notion'."
	@echo "  e.g. make study VAULT=~/Projects/Personal_LLM_Wiki"

doctor: ## Check this machine has everything needed
	@bin/doctor

build: ## Build the app (Command Line Tools are sufficient)
	swift build

run: build ## Launch the app
	swift run AppleNotestoX

study: ## Regenerate review/study-data.js from a vault, then open the study app
	@if [ -z "$(VAULT)" ]; then \
	  echo "error: VAULT is required — make study VAULT=~/Projects/Personal_LLM_Wiki"; exit 1; fi
	node review/generate.mjs --vault "$(VAULT)"
	open review/index.html

notion: ## List Notion pages visible to the integration
	@if [ -z "$(VAULT)" ]; then \
	  echo "error: VAULT is required — make notion VAULT=~/Projects/Personal_LLM_Wiki"; exit 1; fi
	node tools/notion-import.mjs --vault "$(VAULT)" --list

check: build ## Run every gate that works without full Xcode
	node --check review/generate.mjs
	node --check tools/notion-import.mjs
	node tools/notion-import-safety.test.mjs
	@echo "OK — build green, node tools parse, safety tests pass."
	@echo "note: 'swift test' needs full Xcode; see README 'Tests'."

clean: ## Remove build artifacts
	rm -rf .build
