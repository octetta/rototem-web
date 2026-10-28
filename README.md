# rototem-web ⬡

> **Modern Web-First Audio Workstation**: Control the **Skred** audio engine directly in the browser with **Gleam** and **Lustre** (The Elm Architecture), featuring 8 stereo track voice pairs, hybrid grid/floating draggable cards, directory bulk audio loading (.wav, .mp3, .flac), project ZIP persistence, and real-time audio recording.

[![Gleam](https://img.shields.io/badge/Gleam-v1.1.0+-ffaff3?logo=gleam)](https://gleam.run)
[![Lustre](https://img.shields.io/badge/Lustre-TEA-8b5cf6)](https://github.com/hayleigh-dot-dev/lustre)
[![API Documentation](https://img.shields.io/badge/docs-Gleam%20API-2ea44f?logo=readme)](https://octetta.github.io/rototem-web/docs/)
[![Live Demo](https://img.shields.io/badge/demo-GitHub%20Pages-blue?logo=github)](https://octetta.github.io/rototem-web/)

---

## 🌟 Highlights & Architecture

- **100% Standalone & Vendored**: Zero dependency on local sibling directories.
- **Skred Audio Engine (WASM + Web Audio)**:
  - 8 Stereo Track Voice Pairs (16 voices: Voice 0/1 through Voice 14/15).
  - Stereo synchronization for volume, playback speed, run/stop, mute, and direction flip (`b`).
  - High-performance Emscripten VFS `/waves` audio streaming.
  - Interactive REPL console (`Ctrl-~`) with command history and live stdout capture.
  - **Real-Time Control Plane Event Bus**: 60 FPS polling of Skred's C lock-free event ring buffer (`skred_control_event_t`) with typed Gleam event decoding (`VoiceFinished`, `VoiceTrigger`, `VoiceRelease`, `PatternStep`, etc.) providing true two-way audio engine reactive feedback.
- **Idiomatic Gleam & Lustre Architecture**:
  - **Decomposed TEA Update Cycle**: Clean domain sub-handlers (`update_track_msg`, `update_master_msg`, `update_console_msg`, `update_ffi_msg`) eliminating monolithic boilerplate.
  - **Componentized Views**: Monolithic UI decomposed into modular subviews under `src/rototem/views/` (`master_bar`, `track_card`, `console`, `library_modal`, `common`).
  - **Bi-Directional Skode & ANDS AST & Parser**: Complete AST compiler and tokenizer/parser (`src/rototem/skode.gleam`) supporting parsing (`parse`, `parse_command`), AST validation, and serialization.
- **High-Performance Frontend & Lustre Best Practices**:
  - **GPU-Composited Transforms**: Floating cards and console windows use CSS custom properties (`--card-x`, `--card-y`, `--track-color`) and `translate3d` transforms with `will-change: transform`, bypassing browser layout reflows during dragging.
  - **Native Pointer Capture**: Touch, pen, and mouse gestures use unified Pointer Events (`pointerdown`, `pointermove`, `pointerup`) with `setPointerCapture(event.pointerId)` decoded in Lustre, eliminating lost events when dragging past viewport boundaries.
  - **Audio Slider Throttling via `requestAnimationFrame`**: High-frequency slider dragging coalesces continuous parameter updates (volume, pitch) to at most one WASM dispatch per display frame while preserving instant execution for discrete transport commands.
- **Sound Management, VFS & Persistence**:
  - **Generic Emscripten VFS File Mounting**: Mount `.zip`, `.sk` (Skode), `.ks` (k-synth), `.wav`, `.mp3`, and `.flac` files directly into VFS with console management chips (`[file.zip] %z`, `[file.sk] /ls`, `[file.ks] /ks`, `[file.wav] /w`).
  - Bulk directory picker supporting `.wav`, `.mp3`, and `.flac`.
  - Individual track sound pickers + quick `🎲 Random` sample assignment.
  - Master `🎲 Random All` button to randomize sounds across all 8 tracks simultaneously.
  - Project ZIP export and import packaging `settings.json` and mounted audio files via `fflate`.
  - **Integrated Interactive API Documentation**: Built-in Gleam HTML docs served directly in development, preview, and GitHub Pages.

---

## 🎼 Skode & ANDS Audio Command Language AST

`rototem-web` includes a complete, type-safe Abstract Syntax Tree and lowering compiler for **Skode** (`src/rototem/skode.gleam`), modeled directly on Skred's C engine (`ands.c` and `skode.c`):

### Language Syntax & Features

| Construct | Syntax | Purpose |
|---|---|---|
| **String Literals** | `[path/to/wave.wav]` | Bracketed file paths and macro text buffers |
| **Numeric Arrays** | `( 60 64 67 . - )` | Pitch sequences, chords, ties (`.`), and rests (`-`) |
| **Named Macros** | `[name] : body ;` | Global named macro definitions (up to 4 chars) |
| **Macro Placeholders** | `$$0` .. `$$7` | Positional argument replacement inside macro bodies |
| **Macro Invocation** | `name arg0 arg1` | Macro call with argument expansion |
| **Variables** | `$0` .. `$127` | Register read and provenance tracking |
| **Streams** | `&0` .. `&127` | Real-time modulation stream routing (LFO, envelope) |
| **Return Registers** | `@0` .. `@9` | Return value register reads |
| **Time Deferrals** | `+0.25 ... ;` | Relative delay in seconds |
| **Beat Deferrals** | `~4 ... ;` | Tempo-relative duration in ticks/steps |
| **Comments** | `# comment text` | In-band documentation comments |
| **Macro Buffers** | `eR`, `eRR`, `e!`, `e?`, `e>` | Numeric indexed macro loops and buffer storage |
| **Note Notation (`n>d`)** | `[ C3 . - ~E3 - ] n>d` | Music notation string compiler into active data buffer |
| **Stream Note Assignment** | `[ notes ] n>d /SS 1` | Compiles note string directly into sequencer/modulation stream |
| **K-Synth Array Evaluation** | `[ 1 2 3 ] ks` or `k!` | Evaluates embedded k-synth vector array language expressions |
| **K-Synth to Data / Wave** | `k>d`, `k>w <slot>` | Copies k-synth vector to data array or renders to wavetable |
| **Data / Wave to K-Synth** | `d>k`, `w>k` | Bi-directional bridge feeding Skred data or wavetable into k-synth |

### Example Usage in Gleam

```gleam
import rototem/skode

// 1. Defining and calling a named ANDS macro:
let define = skode.define_macro("ar", skode.Raw("t $$0 0 $$1 0"))
// Compiles to: "[ar] : t $$0 0 $$1 0 ;"

let call = skode.call_macro("ar", [skode.Num(0.01), skode.Num(0.4)])
// Compiles to: "ar 0.01 0.4"

// 2. Composing data arrays with variables ($) and streams (&):
let array_cmd = skode.DataArray([
  skode.Num(60.0),    // Note pitch
  skode.Variable(0),  // $0 (variable)
  skode.Stream(1),    // &1 (stream modulation)
  skode.ReturnRef(2), // @2 (return register)
  skode.Tie,          // .  (tie sentinel)
  skode.Rest,         // -  (rest / NaN keep sentinel)
])
// Compiles to: "(60.0 $0 &1 @2 . -)"

// 3. Stereo track controls:
let cmd = skode.track_control(
  left_voice: 0,
  right_voice: 1,
  volume: -6.0,
  speed: 69.0,
  muted: False,
  reversed: False,
  run: True,
)

// 4. Music notation mini-language (n>d):
let melody = skode.note_stream("Bb1 Bb1 Bb2 Bb1  Ab1 - Ab1 -", 1)
// Compiles to: "[ Bb1 Bb1 Bb2 Bb1  Ab1 - Ab1 - ] n>d /SS 1"

// 5. K-synth vector array language:
let wavetable = skode.ksynth_to_wavetable("P: ~4096; W: s P", 50)
// Compiles to: "[ P: ~4096; W: s P ] ks 50 k>w"

// 6. Parsing Skode text back into typed AST:
let assert Ok(script) = skode.parse("v0 a-3.5 f440 T; [beat.wav] /w; +0.25 v0l0")

// 7. Lowering text directly into high-level domain commands:
let assert Ok(commands) = skode.parse_command("v0 a-6.0; [snare.wav] /w")
```

---

## 📡 Real-Time Control Plane Event Bus (Two-Way Reactivity)

In standard WebAssembly audio wrappers, communication is often strictly one-way: the UI fires commands into the engine, but has no visibility into voice lifecycle events (such as one-shot samples finishing playback or sequencer steps advancing).

`rototem-web` implements a two-way reactive control plane bridge modeled on Skred's low-latency C event ring buffer (`skred_control_event_t` in `api.h`):

1. **Lock-Free Binary Polling**: `skred_ffi.mjs` polls `_skred_control_event_poll` on each animation frame (`requestAnimationFrame`) into a reusable WASM heap buffer, reading 72-byte event structs via `DataView`.
2. **Gleam Dynamic Decoding**: Batched events are passed into Lustre via `skred.subscribe_control_plane(types.ControlEventsReceived)`, where `decode.Decoder` deserializes raw event records into typed `SkredEvent` variants.
3. **Reactive UI State Sync**: When a sample finishes playing naturally (`VoiceFinished`), or when note-off occurs (`VoiceRelease`), `rototem_web.gleam` automatically updates the corresponding track card's `playing: False` state, keeping UI controls, wave animations, and play toggles in lockstep with the DSP engine without brittle frontend timers.

### Event Types

| Event Variant | Skred C Event | Description |
|---|---|---|
| `VoiceTrigger(voice, velocity)` | `SKRED_CONTROL_EVENT_VOICE_TRIGGER` (1) | Voice triggered by UI button, keyboard, or sequencer |
| `VoiceRelease(voice)` | `SKRED_CONTROL_EVENT_VOICE_RELEASE` (2) | Voice envelope entered release phase or note-off |
| `VoiceFinished(voice)` | `SKRED_CONTROL_EVENT_VOICE_FINISHED` (3) | Sample playback finished naturally or envelope completed |
| `UserEvent(id, a, b, c)` | `SKRED_CONTROL_EVENT_USER` (4) | Custom telemetry marker fired via `ce <id>, <a>, <b>, <c>` |
| `PatternStart(pattern)` | `SKRED_CONTROL_EVENT_PATTERN_START` (5) | Sequencer pattern playback initiated |
| `PatternEnd(pattern)` | `SKRED_CONTROL_EVENT_PATTERN_END` (6) | Sequencer pattern playback reached end |
| `PatternStep(pattern, step)` | `SKRED_CONTROL_EVENT_PATTERN_STEP` (9) | Sequencer step advanced (0–15) |
| `TempoChange(bpm)` | `SKRED_CONTROL_EVENT_TEMPO_CHANGE` (11) | Engine global tempo modified |
| `MuteChange(pattern, muted)` | `SKRED_CONTROL_EVENT_MUTE_CHANGE` (13) | Pattern mute state changed |
| `OtherEvent(type_id)` | Catch-all | Forward-compatible handler for newer engine opcodes |

---

## 🚀 Quick Start

### 1. Launch in Browser (Dev Mode)
```bash
make run
# or: make dev
```
Automatically installs dependencies (if needed), compiles Gleam to JavaScript, and starts the Vite development server with Cross-Origin Isolation headers for WebAssembly.

### 2. Run Tests & Quality Checks
```bash
make test    # Run full unit test suite (16 tests)
make check   # Verify Gleam compilation and formatting
make format  # Auto-format all Gleam files
```
Executes the comprehensive test suite (`test/rototem_web_test.gleam`), validating AST compilation, ANDS syntax lowering, settings serialization round-trips, theme decoders, and real-time control plane event handling.

### 3. Generate HTML Documentation & GitHub Pages Hosting
```bash
make docs
# or: gleam docs build
```
Renders complete, hyperlinked documentation with type signatures, module guides, and full-text search from all in-code `////` and `///` comments to `build/dev/docs/rototem_web/index.html`.

In production builds, documentation is automatically compiled into `dist/docs/` and deployed to GitHub Pages alongside the application:
👉 **[Interactive API Documentation](https://octetta.github.io/rototem-web/docs/)**

### 4. Build for Production
```bash
make build
```
Compiles Gleam to JS and bundles assets via Vite into a standalone `dist/` distribution.

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
├── styles.css             # External stylesheet (dark/light themes, GPU transforms)
├── src/
│   ├── rototem_web.gleam  # Main application entry & Lustre TEA update loop
│   ├── skred_ffi.mjs      # JS FFI bridge (WASM engine, rAF coalescing, pointer capture)
│   └── rototem/
│       ├── types.gleam    # Gleam domain models, Track, CardMode, Msg types
│       ├── skode.gleam    # Typed Skode / ANDS AST, macro words, and lowering compiler
│       ├── skred.gleam    # Typed Skred command effects & FFI wrappers
│       ├── settings.gleam # Project settings serialization & JSON decoder
│       ├── ui.gleam       # Top-level Lustre view orchestrator
│       └── views/
│           ├── common.gleam        # Shared decoders, pointer capture, theme palettes
│           ├── console.gleam       # Floating & resizable Skred REPL drawer
│           ├── library_modal.gleam # Sound sample library browser modal
│           ├── master_bar.gleam    # Top workstation control bar & transport
│           └── track_card.gleam    # Grid & floating GPU-composited track cards
├── test/
│   └── rototem_web_test.gleam # Unit test suite (Skode AST, formatting, settings)
├── gleam.toml             # Gleam configuration (target: javascript)
├── package.json           # Node scripts and subpath import mappings
└── vite.config.js         # Vite server configuration with COOP/COEP headers
```

---

## 🔮 Future Vision & Aspirational Roadmap: From Playground to Ecosystem

While `rototem-web` currently serves as the **R&D proving ground and integration playground** for Skred, Gleam, and Lustre, the long-term architectural goal is to decouple the foundational pieces into clean, reusable packages and explore live-coding workflows inspired by environments like **Strudel**.

```text
                ┌────────────────────────────────────────┐
                │          Live Coding / Strudel         │
                │        Interactive Canvas & UI         │
                └───────────────────┬────────────────────┘
                                    │
                                    ▼
       ┌────────────────────────────────────────────────────────┐
       │                      skred_lustre                      │
       │    Reusable Lustre TEA Audio Components & Widgets       │
       │  (Faders, Knobs, Visualizers, Sequencers, Event Bus)   │
       └────────────────────────────┬───────────────────────────┘
                                    │
                                    ▼
       ┌────────────────────────────────────────────────────────┐
       │                      skred_gleam                       │
       │      Headless Core SDK: Skode AST & ANDS Compiler,     │
       │     Typed Event Decoders, Native/WASM FFI Engine       │
       └────────────────────────────┬───────────────────────────┘
                                    │
                                    ▼
       ┌────────────────────────────────────────────────────────┐
       │                   Skred Audio Engine                   │
       │              (C DSP / WebAssembly / VFS)               │
       └────────────────────────────────────────────────────────┘
```

### 1. Ecosystem Decoupling & Clean Packaging

1. **`skred_gleam` (Headless Core Engine SDK)**:
   - Completely decoupled from DOM, Lustre, and browser specifics.
   - Houses the type-safe **Skode AST & ANDS Lowering Compiler** (`src/rototem/skode.gleam`).
   - Pure Gleam data models for voice allocation, wavetable slots, and sequencer opcodes.
   - Typed binary decoders for the 60 FPS lock-free **Control Plane Event Ring Buffer** (`skred_control_event_t`).
   - Cross-platform bindings: WASM in the browser, C-ABI dynamic library (`libapi.so` / `libapi.dylib`) on native BEAM or native binaries via Gleam Erlang/JavaScript.

2. **`skred_lustre` (Reactive Audio Component Library)**:
   - A dedicated component and subscription toolkit for building reactive sound applications with The Elm Architecture.
   - Built-in Lustre subscriptions:
     - `subscribe_control_plane`: continuous telemetry streaming with zero audio thread blocking.
     - `subscribe_animation_frame`: throttled slider and modulation dispatching.
   - High-performance UI primitives:
     - GPU-composited floating canvas layers with native Pointer Capture.
     - Virtualized multi-channel fader banks, logarithmic volume/pan sliders, and detented pitch pickers.
     - Real-time oscilloscope, spectrogram (`?ws`), and voice graph (`_skred_voice_graph`) canvas/WebGL renderers.

---

### 2. Live Coding UI: A Strudel-Inspired Future for Skred

**The Ambition**: Give Skred an expressive, browser-first live coding environment where sound sculptors and live performers can compose rhythms, sculpt wavetables, and modulate parameters in real time through concise, rhythmic code that updates seamlessly without breaking musical flow.

Inspired by **Strudel** (the browser-based TidalCycles live coding environment), we envision bringing live coding to Skred by combining the mathematical elegance of pattern mini-notations with Skred's low-latency DSP engine.

Crucially, **Skred already contains two powerful embedded domain-specific languages** waiting to be connected to this reactive UI:

1. 🎼 **The `n>d` Music Notation Mini-Language**:
   - Rather than having to invent a note parser from scratch in JavaScript or Gleam, Skred embeds an internal music notation compiler via `[ ... ] n>d`.
   - Natively parses space-delimited note names (`C4`, `F#2`, `Bb1`, `Db-1`), octave indicators, ties (`.`, `_`), rests (`-`, `~`, `R`), and slurs/legato (`~E3`).
   - Outputs directly into the active ANDS data buffer and routes instantly to sequencer pitch streams via `/SS` (e.g. `[ Bb1 Bb1 Bb2 Bb1 - Ab1 - ] n>d /SS 1`).
   - A Strudel-like pattern compiler in Gleam can lower melodic and chordal cycles directly into `n>d` strings.

2. 🧮 **The `k-synth` Vector Array Language Engine**:
   - Skred embeds an entire vector/array language subsystem (**k-synth**), capable of evaluating expressive array expressions (`[ ... ] ks` and `k!`).
   - Results can be transferred directly into the audio pipeline:
     - `k>d`: Copies k-synth evaluation vectors into Skred's data array buffer.
     - `k>w <slot>`: Synthesizes array evaluation vectors directly into playable wavetable slots (e.g. `[ P: ~4096; W: s P ] ks 50 k>w` to synthesize a pure 4096-sample sine wave).
     - `d>k` and `w>k`: Bi-directional bridge feeding Skred data buffers or wavetables back into k-synth for algorithmic manipulation.
   - This gives live coders native APL/k-style vector math directly in the C engine for sculpting wavetables, dynamic waveshapers, and generative harmonic spectra on the fly.

#### Architectural Building Blocks to Explore

- 🧩 **Pattern Mini-Notation Lowering**:
  - Designing a concise, rhythmic mini-notation in Gleam (e.g., `"[bd*4, ~ cp] [hh*8]"`, Euclidean patterns `(3, 8)`, polyrhythms, and polymeters).
  - Compiling pattern cycles directly into Skred beat deferrals (`~ticks`), time deferrals (`+seconds`), embedded `n>d` note strings, and `ks` array expressions.

- ⚡ **Hot Macro Re-Evaluation**:
  - Leveraging Skred's in-engine named macro system (`[macro_name] : body ;`) and dynamic numeric macro loop buffers (`eR`, `e!`, `e>`) to re-bind patterns and phrases on the fly.
  - Hot-swapping macro bodies in real time without restarting voices, dropping frames, or losing global transport phase.

- 🎛️ **Reactive In-Editor UI & Step Flashing**:
  - Embedding a modern web code editor (such as CodeMirror 6 or a custom Lustre editor) with real-time Skode syntax highlighting and diagnostics.
  - Using the **Real-Time Control Plane Event Bus** (`PatternStep`, `VoiceTrigger`, `VoiceFinished`) to illuminate running code inline—flashing pattern elements, highlighting active notes, and scrubbing visual playheads directly over the code as it sounds.

- 🌊 **Live Continuous Modulation Streams (`&0`..`&127`)**:
  - Exposing Skred's stream registers to interactive UI widgets (XY pads, mouse trajectories, MIDI controllers, Web MIDI) for live continuous modulation over discrete rhythmic patterns.

> [!NOTE]
> This roadmap represents aspirational exploration. `rototem-web` remains our primary laboratory to prove and battle-test these abstractions before extracting them into independent, production-grade packages.
