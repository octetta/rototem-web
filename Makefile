.DEFAULT_GOAL := help

# ------------------------------------------------------------------------------
# Configuration & Binaries
# ------------------------------------------------------------------------------
SHELL := /bin/bash
GLEAM ?= gleam
NPM   ?= npm
PORT  ?= 3000
HOST  ?= 0.0.0.0

.PHONY: help build bundle dev run start preview test update-skred deps setup clean format check docs

help:
	@echo "rototem-web Makefile targets:"
	@echo "  make dev          Start Vite dev server and open browser (network enabled)"
	@echo "  make run          Alias for 'make dev'"
	@echo "  make build        Compile Gleam and build production bundle into dist/"
	@echo "  make bundle       Alias for 'make build'"
	@echo "  make preview      Preview production build in dist/ (network enabled)"
	@echo "  make test         Run test suite via Gleam JavaScript target"
	@echo "  make check        Verify compilation and Gleam formatting"
	@echo "  make format       Format all Gleam source and test files"
	@echo "  make docs         Build HTML documentation in build/dev/docs/"
	@echo "  make update-skred Fetch latest pinned Skred WASM from GitHub releases"
	@echo "  make deps         Install Gleam and npm dependencies"
	@echo "  make clean        Remove build, dist, and cache artifacts"

deps:
	@echo "==> Downloading Gleam dependencies..."
	$(GLEAM) deps download
	@echo "==> Installing npm packages..."
	$(NPM) install

setup: deps update-skred

node_modules: package.json package-lock.json
	@echo "==> Installing npm packages..."
	$(NPM) install
	@touch -c node_modules

build: node_modules
	@echo "==> Compiling Gleam code to JavaScript..."
	$(GLEAM) build --target javascript
	@echo "==> Bundling with Vite for production..."
	$(NPM) run build

bundle: build

dev: node_modules
	@echo "==> Compiling Gleam, building docs, and launching browser..."
	$(GLEAM) build --target javascript
	$(GLEAM) docs build
	npx vite --host $(HOST) --open --port $(PORT)

run: dev
start: dev

preview: build
	@echo "==> Launching production preview on network..."
	npx vite preview --host $(HOST) --open --port $(PORT)

test:
	@echo "==> Running Gleam unit tests..."
	$(GLEAM) test --target javascript

check:
	@echo "==> Verifying compilation and formatting..."
	$(GLEAM) check
	$(GLEAM) format --check src test

format:
	@echo "==> Formatting Gleam source and test files..."
	$(GLEAM) format src test

docs:
	@echo "==> Building Gleam documentation..."
	$(GLEAM) docs build

update-skred:
	@echo "==> Fetching vendored Skred WASM assets..."
	./scripts/fetch-skred.sh

clean:
	@echo "==> Cleaning build artifacts..."
	rm -rf build dist dev erl_crash.dump
