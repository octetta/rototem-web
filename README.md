# rototem-web ⬡

> **Modern Web-First Audio Workstation**: Control the **Skred** audio engine directly in the browser with **Gleam** and **Lustre** (The Elm Architecture), featuring 8 stereo track voice pairs, hybrid grid/floating draggable cards, directory bulk audio loading (.wav, .mp3, .flac), project ZIP persistence, and real-time audio recording.

---

## 🌟 Features

- **100% Standalone & Vendored**: Zero dependency on local sibling directories.
- **Skred Audio Engine (WASM + Web Audio)**:
  - 8 Stereo Track Voice Pairs (16 voices: Voice 0/1 through Voice 14/15).
  - Stereo synchronization for volume, playback speed, run/stop, mute, and direction flip (`b-`).
  - High-performance Emscripten VFS `/waves` audio streaming.
- **Easy Skred WASM Updates**:
  - `SKRED_VERSION` pinned to upstream releases.
  - One-command updater (`./scripts/fetch-skred.sh`) fetching `skred_api.js` and `skred_api.wasm` directly from `octetta/pulp` GitHub releases.
- **Hybrid Card Positioning (Grid + Free Float)**:
  - **Grid Layout**: Clean, responsive CSS grid displaying up to 8 track cards.
  - **Free-Drag Overlay**: Click **`↗ Float`** to pop any card out of the grid into a floating layer with arbitrary $(x, y)$ coordinates and elevated z-index, allowing free dragging over the grid.
  - **One-Click Re-Dock**: Click **`↙ Dock`** on any floating card to return it to the natural grid flow.
  - **Minimize & Restore**: Collapse any card (`_`) into a space-efficient compact bar, or restore (`□`) to full parameter controls.
- **Sound Management & Library**:
  - Bulk directory picker supporting `.wav`, `.mp3`, and `.flac`.
  - Individual track sound pickers + quick `🎲 Random` sample assignment.
  - Master `🎲 Random All` button to randomize sounds across all 8 tracks simultaneously.
- **Project Persistence (ZIP)**:
  - **Save ZIP**: Packages `settings.json` + all used audio files via `fflate` into a portable `.zip` download.
  - **Load ZIP**: Restores configuration, extracts/mounts audio files, and re-establishes voice assignments, volumes, speeds, and layout positions.
- **Master Controls**:
  - Master volume slider.
  - Master transport (Start All / Stop All active tracks).
  - Audio output device selector (`AudioContext.setSinkId`).
  - Master mix audio recorder with WebM/WAV export.

---

## 🚀 Quick Start

You can use standard `make` targets or npm:

### 1. Launch in Browser (Dev Mode)
```bash
make run
# or: make dev
```
This compiles the Gleam code, starts the local server, and automatically opens your web browser.

### 2. Build / Bundle for Production
```bash
make build
# or: make bundle
```
Produces an optimized, standalone production bundle in `dist/`.

### 3. Preview Production Build
```bash
make preview
```
Serves the `dist/` directory and opens your browser.

### 4. Run Tests
```bash
make test
```

### 5. Other Helpful Make Targets
- `make deps`: Downloads Gleam and npm dependencies.
- `make update-skred`: Refetches the latest pinned WASM assets from upstream releases.
- `make clean`: Cleans build and cache directories.
- `make help`: Displays all available targets.

---

## 🔄 Updating Skred WASM

To update to a newer version of the Skred audio engine:
1. Update the version string in `SKRED_VERSION` (e.g. `0.80.0`).
2. Run the updater script:
   ```bash
   ./scripts/fetch-skred.sh
   ```
   This automatically downloads the latest WASM release from `octetta/pulp`, extracts `skred_api.js` and `skred_api.wasm` into `vendor/skred/`, and syncs them to `public/vendor/`.

---

## 📁 Repository Structure

```text
rototem-web/
├── SKRED_VERSION          # Pinned version of Skred audio engine
├── scripts/
│   └── fetch-skred.sh     # Upstream asset fetcher from octetta/pulp releases
├── vendor/                # Vendored dependencies (standalone)
│   ├── fflate.mjs         # Fast browser ZIP compression & decompression
│   └── skred/             # Pinned skred_api.js and skred_api.wasm
├── public/                # Static public assets served by dev/preview server
├── src/
│   ├── rototem_web.gleam  # Main application entry & Lustre TEA update loop
│   ├── skred_ffi.mjs      # JS FFI bridge (WASM engine, Web Audio, VFS, fflate)
│   └── rototem/
│       ├── types.gleam    # Gleam domain models, Track, CardMode, Msg types
│       ├── skred.gleam    # Typed Skred command effects & formatting helpers
│       ├── settings.gleam # Project settings serialization & JSON decoder
│       └── ui.gleam       # Space-efficient Lustre UI views & drag decoders
├── test/
│   └── rototem_web_test.gleam # Test suite (Skred formatting, settings round-trip)
├── gleam.toml             # Gleam configuration (target: javascript)
├── package.json           # Node scripts and subpath import mappings
└── vite.config.js         # Vite server configuration with COOP/COEP headers
```
