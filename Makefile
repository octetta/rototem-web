.DEFAULT_GOAL := help

# ------------------------------------------------------------------------------
# Configuration & Binaries
# ------------------------------------------------------------------------------
SHELL := /bin/bash
GLEAM ?= gleam
NPM   ?= npm
PORT  ?= 3000
HOST  ?= 0.0.0.0

.PHONY: help build bundle dev run start preview test update-skred deps setup clean

help:
	@echo "rototem-web Makefile targets:"
	@echo "  make dev          Start Vite dev server and open browser (network enabled)"
	@echo "  make run          Alias for 'make dev'"
	@echo "  make build        Compile Gleam and build production bundle into dist/"
	@echo "  make bundle       Alias for 'make build'"
	@echo "  make preview      Preview production build in dist/ (network enabled)"
	@echo "  make test         Run test suite via Gleam JavaScript target"
	@echo "  make update-skred Fetch latest pinned Skred WASM from GitHub releases"
	@echo "  make deps         Install Gleam and npm dependencies"
	@echo "  make clean        Remove build, dist, and cache artifacts"

deps:
	@echo "==> Downloading Gleam dependencies..."
	$(GLEAM) deps download
	@echo "==> Installing npm packages..."
	$(NPM) install

setup: deps update-skred

build:
	@echo "==> Compiling Gleam code to JavaScript..."
	$(GLEAM) build --target javascript
	@echo "==> Bundling with Vite for production..."
	$(NPM) run build

bundle: build

dev:
	@echo "==> Compiling Gleam and launching browser..."
	$(GLEAM) build --target javascript
	npx vite --host $(HOST) --open --port $(PORT)

run: dev
start: dev

preview: build
	@echo "==> Launching production preview on network..."
	npx vite preview --host $(HOST) --open --port $(PORT)

test:
	@echo "==> Running Gleam unit tests..."
	$(GLEAM) test --target javascript

update-skred:
	@echo "==> Fetching vendored Skred WASM assets..."
	./scripts/fetch-skred.sh

clean:
	@echo "==> Cleaning build artifacts..."
	rm -rf build dist dev erl_crash.dump
