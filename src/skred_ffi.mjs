// JavaScript FFI Bridge for rototem-web
// Integrates Skred WASM audio engine, fflate ZIP support, and Web Audio APIs

import { zip, unzip, strToU8, strFromU8 } from "#vendor/fflate.mjs";
import { toList } from "./gleam.mjs";
import { AudioFile, AudioDevice, VfsFile } from "./rototem/types.mjs";

const win = typeof window !== "undefined" ? window : globalThis;

let moduleReady = false;
let engineStarted = false;
let commandQueue = [];
let audioContext = null;
let mediaRecorder = null;
let recordedChunks = [];
let consoleCallback = null;
let capturedStdout = [];

// Control Plane Event Subscriptions
let currentEventSubscription = null;
let eventPumpStarted = false;
let wasmEventsBuffer = null;
const EVENT_SIZE = 72; // sizeof(skred_control_event_t)
const MAX_EVENTS_BATCH = 64;

// In-memory store of loaded audio file buffers for ZIP packaging
const fileStore = new Map();

// ---------------------------------------------------------------------------
// 1. Skred WASM Engine Initialization & Stdout Hooking
// ---------------------------------------------------------------------------

function setupStdoutHook(M) {
  if (!M) return;
  const originalPrint = M.print || console.log;
  const originalPrintErr = M.printErr || console.error;

  M.print = function (...args) {
    const line = args.join(" ");
    capturedStdout.push(line);
    if (win.__skredStdout && !win.__skredStdout.includes(line)) {
      win.__skredStdout.push(line);
    }
    originalPrint.apply(console, args);
  };

  M.printErr = function (...args) {
    const line = args.join(" ");
    capturedStdout.push("[ERR] " + line);
    if (win.__skredStdout) {
      win.__skredStdout.push("[ERR] " + line);
    }
    originalPrintErr.apply(console, args);
  };
}

function getWasmModule() {
  if (win.Module && typeof win.Module.ccall === "function") {
    return win.Module;
  }
  return null;
}

export function initEngine(callback) {
  if (moduleReady && engineStarted) {
    if (callback) callback(true);
    return;
  }

  // Pre-configure Emscripten Module
  win.Module = win.Module || {};
  win.Module.locateFile = function (path) {
    if (typeof window !== "undefined") {
      return new URL("vendor/skred/" + path, window.location.href).href;
    }
    return "/vendor/skred/" + path;
  };

  // Setup stdout capture early
  setupStdoutHook(win.Module);

  const prevInit = win.Module.onRuntimeInitialized;
  win.Module.onRuntimeInitialized = function () {
    if (prevInit) prevInit();
    console.log("[rototem-web] Skred WASM runtime initialized.");
    moduleReady = true;

    try {
      setupStdoutHook(win.Module);

      if (win.Module.FS) {
        try { win.Module.FS.mkdir("/waves"); } catch (e) {}
        try { win.Module.FS.mkdir("waves"); } catch (e) {}
      }

      // Enumerate playback devices and select default output (0); disable capture/input (-2)
      if (typeof win.Module._skred_enumerate_devices === "function") {
        win.Module._skred_enumerate_devices(0);
      }
      if (typeof win.Module._skred_audio_select === "function") {
        win.Module._skred_audio_select(0, 0);
        win.Module._skred_audio_select(1, -2);
      }

      // Start engine with 128 buffer size, 256 voices, default port (-1)
      if (typeof win.Module._skred_start === "function") {
        const res = win.Module._skred_start(128, 256, -1);
        console.log("[rototem-web] _skred_start returned:", res);
        engineStarted = (res === 0);
      }

      // Enable logger for status command retrieval
      if (typeof win.Module._skred_logger === "function") {
        win.Module._skred_logger(1);
      }

      // 1. Clear/reset all voices using S-1 (modern Skred syntax)
      executeSkredCommand("S-1");

      // 2. Set master volume: V0 (0 dB unity)
      executeSkredCommand("V0");

      // 3. Initialize voices 0..15 (8 stereo pairs)
      // Pan: -1 for left, +1 for right, unity pitch 69, envelope t1 0 1 1, loop B1, volume a0 (0 dB)
      for (let i = 0; i < 8; i++) {
        const left = i * 2;
        const right = i * 2 + 1;
        executeSkredCommand(`v${left} p-1 n69 B1 t1 0 1 1 a0`);
        executeSkredCommand(`v${right} p1 n69 B1 t1 0 1 1 a0`);
      }

      // 4. Enable voice lifecycle events on voices 0..15 (for real-time feedback)
      if (typeof win.Module._voice_control_events_set === "function") {
        for (let i = 0; i < 16; i++) {
          win.Module._voice_control_events_set(i, 1);
        }
      }
      for (let i = 0; i < 16; i++) {
        executeSkredCommand(`v${i} vc1`);
      }

      startWasmEventPump(win.Module);

      flushCommandQueue();
      if (callback) callback(engineStarted);
    } catch (err) {
      console.error("[rototem-web] Failed to start Skred engine:", err);
      if (callback) callback(false);
    }
  };

  // If Module is already ready
  if (win.Module.calledRun || (win.Module.HEAPU32 && typeof win.Module.ccall === "function")) {
    win.Module.onRuntimeInitialized();
  }
}

function getAudioContext() {
  if (audioContext) return audioContext;
  if (win.miniaudio && Array.isArray(win.miniaudio.devices)) {
    for (const dev of win.miniaudio.devices) {
      if (dev && dev.webaudio) {
        audioContext = dev.webaudio;
        return audioContext;
      }
    }
  }
  if (win.Module && win.Module.audioContext) {
    audioContext = win.Module.audioContext;
    return audioContext;
  }
  return null;
}

function ensureAudioContext() {
  const M = win.Module;
  if (M && M.audioContext && M.audioContext.state === "suspended") {
    M.audioContext.resume().catch(() => {});
  }
  if (win.AL && win.AL.currentCtx && win.AL.currentCtx.audioCtx && win.AL.currentCtx.audioCtx.state === "suspended") {
    win.AL.currentCtx.audioCtx.resume().catch(() => {});
  }
  // Check miniaudio device audio contexts
  if (win.miniaudio && Array.isArray(win.miniaudio.devices)) {
    for (const dev of win.miniaudio.devices) {
      if (dev && dev.webaudio && dev.webaudio.state === "suspended") {
        dev.webaudio.resume().catch(() => {});
      }
    }
  }
}

export function ensureEngineRunning() {
  const M = getWasmModule();
  if (!M) return false;
  ensureAudioContext();
  if (typeof M._skred_audio_running === "function" && M._skred_audio_running()) {
    return true;
  }
  try {
    if (typeof M._skred_enumerate_devices === "function") {
      M._skred_enumerate_devices(0);
    }
    if (typeof M._skred_audio_select === "function") {
      M._skred_audio_select(0, 0);
      M._skred_audio_select(1, -2);
    }
    if (typeof M._skred_start === "function") {
      const res = M._skred_start(128, 256, -1);
      console.log("[rototem-web] ensureEngineRunning _skred_start returned:", res);
      if (res === 0) {
        engineStarted = true;
        if (typeof M._skred_logger === "function") M._skred_logger(1);
        startWasmEventPump(M);
        return true;
      }
    }
  } catch (e) {
    console.warn("[rototem-web] ensureEngineRunning warning:", e);
  }
  return false;
}

// Unlock audio on any initial user pointer or key interaction
if (typeof win.addEventListener === "function") {
  const unlock = () => {
    ensureAudioContext();
    ensureEngineRunning();
  };
  win.addEventListener("pointerdown", unlock, { passive: true });
  win.addEventListener("touchstart", unlock, { passive: true });
  win.addEventListener("keydown", unlock, { passive: true });
  win.addEventListener("click", unlock, { passive: true });
}

function startWasmEventPump(M) {
  if (!M || typeof M._skred_control_event_poll !== "function") return;
  if (!wasmEventsBuffer && typeof M._malloc === "function") {
    wasmEventsBuffer = M._malloc(MAX_EVENTS_BATCH * EVENT_SIZE);
  }
  if (eventPumpStarted) return;
  eventPumpStarted = true;

  function pump() {
    if (
      currentEventSubscription &&
      M &&
      typeof M._skred_control_event_poll === "function" &&
      wasmEventsBuffer &&
      M.HEAPU8
    ) {
      const count = M._skred_control_event_poll(wasmEventsBuffer, MAX_EVENTS_BATCH);
      if (count > 0) {
        const batch = [];
        const dv = new DataView(M.HEAPU8.buffer, wasmEventsBuffer, count * EVENT_SIZE);
        for (let i = 0; i < count; i++) {
          const off = i * EVENT_SIZE;
          const type = dv.getUint32(off, true);
          const seq = dv.getUint32(off + 16, true);
          const voice = dv.getInt32(off + 24, true);
          const pattern = dv.getInt32(off + 28, true);
          const step = dv.getInt32(off + 32, true);
          const id = dv.getInt32(off + 40, true);
          const val0 = dv.getFloat64(off + 48, true);
          const val1 = dv.getFloat64(off + 56, true);
          const val2 = dv.getFloat64(off + 64, true);
          batch.push({
            t: type,
            seq: seq,
            v: voice,
            p: pattern,
            s: step,
            id: id,
            vals: [val0, val1, val2],
          });
        }
        try {
          currentEventSubscription(batch);
        } catch (err) {
          console.error("[rototem-web] Error dispatching event batch to Lustre:", err);
        }
      }
    }
    const schedule =
      typeof requestAnimationFrame !== "undefined"
        ? requestAnimationFrame
        : (cb) => setTimeout(cb, 16);
    schedule(pump);
  }

  const schedule =
    typeof requestAnimationFrame !== "undefined"
      ? requestAnimationFrame
      : (cb) => setTimeout(cb, 16);
  schedule(pump);
}

export function subscribeEvents(onBatch) {
  currentEventSubscription = onBatch;
  const M = getWasmModule();
  if (M) {
    startWasmEventPump(M);
  }
  return () => {
    currentEventSubscription = null;
  };
}

function flushCommandQueue() {
  const M = getWasmModule();
  if (!M) return;
  while (commandQueue.length > 0) {
    const cmd = commandQueue.shift();
    executeSkredCommand(cmd);
  }
}

function executeSkredCommand(cmd) {
  const M = getWasmModule();
  if (!M) return;
  try {
    ensureAudioContext();
    ensureEngineRunning();
    const ret = M.ccall("skred_command", "number", ["string"], [cmd]);
    if (M._skred_log) {
      const log = M.UTF8ToString(M._skred_log());
      if (log && log.trim()) {
        console.log(`[skred] ${cmd} (ret=${ret}):`, log);
      }
    }
  } catch (err) {
    console.error("[rototem-web] Error executing command:", cmd, err);
  }
}

// ---------------------------------------------------------------------------
// Continuous Audio Parameter Throttling via requestAnimationFrame
// ---------------------------------------------------------------------------
const pendingContinuousCommands = new Map();
let continuousRafId = null;

const scheduleRaf =
  typeof requestAnimationFrame === "function"
    ? requestAnimationFrame
    : (fn) => setTimeout(fn, 16);
const cancelRaf =
  typeof cancelAnimationFrame === "function"
    ? cancelAnimationFrame
    : clearTimeout;

function getContinuousKey(cmd) {
  if (typeof cmd !== "string") return null;
  const trimmed = cmd.replace(/\s+/g, "");

  // Master volume parameter: ;V...; or V...
  if (/^;?V[-0-9.]+;?$/.test(trimmed)) {
    return "master_volume";
  }

  // Stereo voice volume parameter: v0a...;v1a...
  const volMatch = /^v(\d+)a([-\d.]+);v(\d+)a([-\d.]+)$/.exec(trimmed);
  if (volMatch) {
    return `vol:${volMatch[1]},${volMatch[3]}`;
  }

  // Stereo voice pitch/speed parameter: v0n...;v1n...
  const pitchMatch = /^v(\d+)n([-\d.]+);v(\d+)n([-\d.]+)$/.exec(trimmed);
  if (pitchMatch) {
    return `pitch:${pitchMatch[1]},${pitchMatch[3]}`;
  }

  return null;
}

export function flushContinuousCommands() {
  if (continuousRafId !== null) {
    cancelRaf(continuousRafId);
    continuousRafId = null;
  }
  if (pendingContinuousCommands.size === 0) return;
  for (const cmd of pendingContinuousCommands.values()) {
    executeSkredCommand(cmd);
  }
  pendingContinuousCommands.clear();
}

export function sendCommand(cmd) {
  const M = getWasmModule();
  if (!M) {
    commandQueue.push(cmd);
    return;
  }

  const key = getContinuousKey(cmd);
  if (key) {
    // Coalesce continuous slider events to at most one update per frame
    pendingContinuousCommands.set(key, cmd);
    if (continuousRafId === null) {
      continuousRafId = scheduleRaf(() => {
        continuousRafId = null;
        for (const c of pendingContinuousCommands.values()) {
          executeSkredCommand(c);
        }
        pendingContinuousCommands.clear();
      });
    }
  } else {
    // Discrete command: immediately flush pending continuous updates first to preserve order
    flushContinuousCommands();
    executeSkredCommand(cmd);
  }
}

// ---------------------------------------------------------------------------
// Pointer Capture FFI Helpers (Prevent event drop during fast dragging)
// ---------------------------------------------------------------------------
export function capturePointer(event) {
  if (!event) return;
  const rawTarget = event.target;
  if (
    rawTarget &&
    (rawTarget.tagName === "BUTTON" ||
      (typeof rawTarget.closest === "function" && rawTarget.closest("button")))
  ) {
    return;
  }
  const target = event.currentTarget || rawTarget;
  if (
    target &&
    typeof target.setPointerCapture === "function" &&
    event.pointerId !== undefined
  ) {
    try {
      target.setPointerCapture(event.pointerId);
    } catch (_) {}
  }
}

export function releasePointer(event) {
  if (!event) return;
  const target = event.currentTarget || event.target;
  if (
    target &&
    typeof target.releasePointerCapture === "function" &&
    event.pointerId !== undefined
  ) {
    try {
      if (typeof target.hasPointerCapture === "function" && target.hasPointerCapture(event.pointerId)) {
        target.releasePointerCapture(event.pointerId);
      }
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Evaluates ASCII command and captures BOTH stdout (printf from ?, ??) & skred_log
// ---------------------------------------------------------------------------
export function evalCommand(cmd, callback) {
  ensureAudioContext();
  ensureEngineRunning();
  flushContinuousCommands();
  const M = getWasmModule();
  if (!M) {
    if (callback) callback(cmd, -1, "Skred WASM engine is not yet initialized.");
    return;
  }
  try {
    capturedStdout = [];
    if (win.__skredStdout) win.__skredStdout.length = 0;

    // Safety intercept on console.log/console.error in case Emscripten output was bound directly to console
    const origLog = console.log;
    const origErr = console.error;
    const directConsoleOut = [];
    console.log = function (...args) {
      directConsoleOut.push(args.join(" "));
      origLog.apply(console, args);
    };
    console.error = function (...args) {
      directConsoleOut.push("[ERR] " + args.join(" "));
      origErr.apply(console, args);
    };

    if (typeof M._skred_logger === "function") M._skred_logger(1);
    const ret = M.ccall("skred_command", "number", ["string"], [cmd]);

    console.log = origLog;
    console.error = origErr;

    // Flush any unbuffered TTY output if Emscripten FS has pending bytes
    if (M.FS && M.FS.streams && M.FS.streams[1] && M.FS.streams[1].tty && M.FS.streams[1].tty.output && M.FS.streams[1].tty.output.length > 0) {
      const remainingBytes = M.FS.streams[1].tty.output;
      let flushText = "";
      if (typeof M.UTF8ArrayToString === "function") {
        flushText = M.UTF8ArrayToString(remainingBytes);
      } else {
        flushText = String.fromCharCode.apply(null, remainingBytes);
      }
      if (flushText) capturedStdout.push(flushText);
      M.FS.streams[1].tty.output = [];
    }

    let logResp = "";
    if (typeof M._skred_log === "function" && typeof M.UTF8ToString === "function") {
      const logPtr = M._skred_log();
      if (logPtr) logResp = M.UTF8ToString(logPtr);
    }

    const combined = [];
    // 1. window.__skredStdout
    if (win.__skredStdout && win.__skredStdout.length > 0) {
      combined.push(...win.__skredStdout);
    }
    // 2. capturedStdout
    for (const line of capturedStdout) {
      if (!combined.includes(line)) combined.push(line);
    }
    // 3. directConsoleOut (exclude internal logs)
    for (const line of directConsoleOut) {
      if (!line.includes("[rototem-web]") && !line.includes("[SKRED OUT]") && !line.includes("[SKRED ERR]") && !combined.includes(line)) {
        combined.push(line);
      }
    }
    // 4. Skred logger response
    if (logResp && logResp.trim() && !combined.includes(logResp.trim())) {
      combined.push(logResp);
    }

    let finalResp = combined.join("\n").trim();
    if (!finalResp) {
      finalResp = `OK (return code: ${ret})`;
    }
    if (callback) callback(cmd, ret, finalResp);
  } catch (err) {
    console.error("[rototem-web] evalCommand exception:", err);
    if (callback) callback(cmd, -1, "Exception: " + err.message);
  }
}

export function registerConsoleToggle(callback) {
  consoleCallback = callback;
  if (typeof win.addEventListener === "function") {
    win.addEventListener("keydown", (e) => {
      // Toggle console on Ctrl+` or Ctrl+~
      if ((e.ctrlKey || e.metaKey) && (e.key === "`" || e.key === "~")) {
        e.preventDefault();
        if (consoleCallback) consoleCallback();
      }
    });
  }
}

// ---------------------------------------------------------------------------
// 2. Track Wave Loading (Stereo Pair /ws Channels)
// ---------------------------------------------------------------------------

let wavePointer = 300;

function allocateWave() {
  const w = wavePointer++;
  if (wavePointer > 1290) {
    wavePointer = 300;
  }
  return w;
}

export function loadTrackWave(leftVoice, rightVoice, path) {
  ensureAudioContext();
  ensureEngineRunning();
  const trackId = Math.floor(leftVoice / 2);

  if (!path || path.trim() === "") {
    // Reset to default internal wave and stop running
    console.log(`[rototem-web] Clearing wave for Track ${trackId + 1}`);
    sendCommand(`v${leftVoice} w82 l0; v${rightVoice} w82 l0`);
    return;
  }

  const fileName = path.split("/").pop().split("\\").pop();

  // If the file data exists in fileStore but missing from VFS, write it now
  const M = getWasmModule();
  if (M && M.FS && fileStore.has(fileName)) {
    try {
      if (!M.FS.analyzePath(`/${fileName}`).exists) {
        writeToEmscriptenVFS(fileName, fileStore.get(fileName));
      }
    } catch (e) {
      writeToEmscriptenVFS(fileName, fileStore.get(fileName));
    }
  }

  // 1. Detach voices to w82 first so the previous wave's refcount drops to 0
  sendCommand(`v${leftVoice} w82; v${rightVoice} w82`);

  // 2. Allocate fresh wave slots so we never collide with existing wave refs
  // (Prevents Skred error: "# cannot write to w<n> ref > 0")
  const waveL = allocateWave();
  const waveR = allocateWave();

  // Load into both channels: channel 0 for Left, channel 1 for Right
  // Resolves directly in Skred VFS current working directory (/)
  const cmdL = `[${fileName}] /ws${waveL} 0 v${leftVoice} p-1 w${waveL} a0 B1 f440 t1 0 1 1`;
  const cmdR = `[${fileName}] /ws${waveR} 1 v${rightVoice} p1 w${waveR} a0 B1 f440 t1 0 1 1`;
  const labelL = `[${fileName}] wt ${waveL}`;
  const labelR = `[${fileName}] wt ${waveR}`;

  console.log(`[rototem-web] Assigning wave for Track ${trackId + 1} (L:${leftVoice}->w${waveL}, R:${rightVoice}->w${waveR}):`);
  console.log("  " + cmdL);
  console.log("  " + cmdR);

  sendCommand(cmdL);
  sendCommand(labelL);
  sendCommand(cmdR);
  sendCommand(labelR);
}

// ---------------------------------------------------------------------------
// 3. Audio File Loading, Directory Picker & VFS Management
// ---------------------------------------------------------------------------

function writeToEmscriptenVFS(fileName, uint8Data) {
  const M = getWasmModule();
  if (M && M.FS) {
    try {
      try { M.FS.mkdir("/waves"); } catch (e) {}
      try { M.FS.mkdir("waves"); } catch (e) {}

      const baseName = fileName.split("/").pop().split("\\").pop();

      // Write directly to root working directory so Skred's %ls shows it immediately
      try { M.FS.writeFile(`/${baseName}`, uint8Data); } catch (e) {}
      try { M.FS.writeFile(baseName, uint8Data); } catch (e) {}

      // Also write into waves/ for dual resolution
      try { M.FS.writeFile(`/waves/${baseName}`, uint8Data); } catch (e) {}
      try { M.FS.writeFile(`waves/${baseName}`, uint8Data); } catch (e) {}

      fileStore.set(baseName, uint8Data);
      console.log(`[rototem-web] Attached file to Skred VFS: ${baseName} (${uint8Data.length} bytes)`);
      return true;
    } catch (err) {
      console.error(`[rototem-web] Error writing ${fileName} to VFS:`, err);
    }
  }
  return false;
}

export function removeAudioFile(fileName) {
  const baseName = fileName.split("/").pop().split("\\").pop();
  fileStore.delete(baseName);
  const M = getWasmModule();
  if (M && M.FS) {
    try { M.FS.unlink(`/${baseName}`); } catch (e) {}
    try { M.FS.unlink(baseName); } catch (e) {}
    try { M.FS.unlink(`/waves/${baseName}`); } catch (e) {}
    try { M.FS.unlink(`waves/${baseName}`); } catch (e) {}
    console.log(`[rototem-web] Unlinked from Emscripten VFS: ${baseName}`);
  }
}

export function clearAllAudioFiles() {
  for (const fileName of Array.from(fileStore.keys())) {
    removeAudioFile(fileName);
  }
  fileStore.clear();
  console.log("[rototem-web] Cleared all audio files from VFS store.");
}

export async function pickDirectory(callback) {
  ensureAudioContext();
  ensureEngineRunning();

  const isAudioFile = (name) => {
    const lower = name.toLowerCase();
    return lower.endsWith(".wav") || lower.endsWith(".mp3") || lower.endsWith(".flac");
  };

  const processFiles = async (fileList) => {
    const loadedFiles = [];
    for (const file of fileList) {
      // Strictly non-recursive: skip any files located in nested subdirectories
      if (file.webkitRelativePath) {
        const segments = file.webkitRelativePath.split("/").filter(Boolean);
        if (segments.length > 2) {
          console.log(`[rototem-web] Skipping subfolder file: ${file.webkitRelativePath}`);
          continue;
        }
      }

      if (!isAudioFile(file.name)) continue;

      try {
        const buffer = await file.arrayBuffer();
        const uint8 = new Uint8Array(buffer);
        const baseName = file.name.split("/").pop().split("\\").pop();
        writeToEmscriptenVFS(baseName, uint8);
        loadedFiles.push({
          id: baseName,
          name: baseName,
          path: baseName,
          size: file.size,
        });
      } catch (err) {
        console.warn("[rototem-web] Failed reading audio file:", file.name, err);
      }
    }
    const gleamFiles = toList(
      loadedFiles.map((f) => new AudioFile(f.id, f.name, f.path, f.size)),
    );
    if (callback) callback(gleamFiles);
  };

  // Modern File System Access API
  if (win.showDirectoryPicker) {
    try {
      const dirHandle = await win.showDirectoryPicker();
      const files = [];
      for await (const entry of dirHandle.values()) {
        // Non-recursive: strictly direct files only
        if (entry.kind === "file" && isAudioFile(entry.name)) {
          const file = await entry.getFile();
          files.push(file);
        }
      }
      await processFiles(files);
      return;
    } catch (e) {
      if (e.name === "AbortError") return;
      console.warn("showDirectoryPicker failed, falling back to input element:", e);
    }
  }

  // Fallback to webkitdirectory file input (mobile & older browsers)
  const input = document.createElement("input");
  input.type = "file";
  input.webkitdirectory = true;
  input.multiple = true;
  input.accept = ".wav,.mp3,.flac,audio/wav,audio/mp3,audio/flac,audio/x-wav";
  input.style.display = "none";
  input.onchange = async () => {
    if (input.files && input.files.length > 0) {
      await processFiles(Array.from(input.files));
    }
    input.remove();
  };
  document.body.appendChild(input);
  input.click();
}

// ---------------------------------------------------------------------------
// 4. Project ZIP Export & Load (via fflate)
// ---------------------------------------------------------------------------

export function exportZip(settingsJson, callback) {
  try {
    const zipEntries = {
      "settings.json": strToU8(settingsJson),
    };

    for (const [fileName, uint8] of fileStore.entries()) {
      zipEntries[`waves/${fileName}`] = uint8;
    }

    zip(zipEntries, (err, data) => {
      if (err) {
        console.error("[rototem-web] ZIP export error:", err);
        if (callback) callback("ZIP export failed: " + err.message);
        return;
      }

      const blob = new Blob([data], { type: "application/zip" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `rototem-project-${new Date().toISOString().slice(0, 10)}.zip`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);

      if (callback) callback(`Project exported with ${fileStore.size} audio files.`);
    });
  } catch (err) {
    console.error("[rototem-web] exportZip exception:", err);
    if (callback) callback("Export error: " + err.message);
  }
}

export function triggerLoadZip(callback) {
  ensureAudioContext();

  const input = document.createElement("input");
  input.type = "file";
  input.accept = ".zip";
  input.style.display = "none";

  input.onchange = async () => {
    if (!input.files || input.files.length === 0) return;
    const file = input.files[0];
    try {
      const buffer = await file.arrayBuffer();
      const uint8 = new Uint8Array(buffer);

      unzip(uint8, (err, unzipped) => {
        if (err) {
          console.error("[rototem-web] Failed to unzip archive:", err);
          return;
        }

        let settingsJson = "{}";
        const restoredFiles = [];

        for (const [relativePath, data] of Object.entries(unzipped)) {
          if (relativePath === "settings.json" || relativePath.endsWith("/settings.json")) {
            settingsJson = strFromU8(data);
          } else if (
            relativePath.toLowerCase().endsWith(".wav") ||
            relativePath.toLowerCase().endsWith(".mp3") ||
            relativePath.toLowerCase().endsWith(".flac")
          ) {
            const fileName = relativePath.split("/").pop();
            writeToEmscriptenVFS(fileName, data);
            restoredFiles.push({
              id: fileName,
              name: fileName,
              path: `waves/${fileName}`,
              size: data.length,
            });
          }
        }

        console.log(`[rototem-web] ZIP loaded: ${restoredFiles.length} files restored.`);
        const gleamFiles = toList(
          restoredFiles.map((f) => new AudioFile(f.id, f.name, f.path, f.size)),
        );
        if (callback) callback(settingsJson, gleamFiles);
      });
    } catch (err) {
      console.error("[rototem-web] Exception loading ZIP:", err);
    } finally {
      input.remove();
    }
  };

  document.body.appendChild(input);
  input.click();
}

export function pickVfsFiles(callback) {
  ensureAudioContext();

  const input = document.createElement("input");
  input.type = "file";
  input.multiple = true;
  input.accept = ".zip,.wav,.mp3,.flac,.sk,.ks,.txt";
  input.style.display = "none";

  input.onchange = async () => {
    if (!input.files || input.files.length === 0) return;
    const files = Array.from(input.files);
    const M = getWasmModule();
    const uploaded = [];

    for (const file of files) {
      try {
        const buffer = await file.arrayBuffer();
        const uint8 = new Uint8Array(buffer);
        const baseName = file.name.split("/").pop().split("\\").pop();
        const ext = baseName.includes(".") ? baseName.split(".").pop().toLowerCase() : "";

        if (M && M.FS) {
          try { M.FS.writeFile(`/${baseName}`, uint8); } catch (e) {}
          try { M.FS.writeFile(baseName, uint8); } catch (e) {}
          if (ext === "wav" || ext === "mp3" || ext === "flac") {
            try { M.FS.writeFile(`/waves/${baseName}`, uint8); } catch (e) {}
            try { M.FS.writeFile(`waves/${baseName}`, uint8); } catch (e) {}
          }
          console.log(`[rototem-web] Wrote to Emscripten VFS: ${baseName} (${uint8.length} bytes)`);
        }

        fileStore.set(baseName, uint8);
        uploaded.push(new VfsFile(baseName, uint8.length, ext));
      } catch (err) {
        console.error(`[rototem-web] Error writing ${file.name} to VFS:`, err);
      }
    }

    if (callback && uploaded.length > 0) {
      callback(toList(uploaded));
    }
    input.remove();
  };

  document.body.appendChild(input);
  input.click();
}

export function removeVfsFile(fileName) {
  const baseName = fileName.split("/").pop().split("\\").pop();
  fileStore.delete(baseName);
  const M = getWasmModule();
  if (M && M.FS) {
    try { M.FS.unlink(`/${baseName}`); } catch (e) {}
    try { M.FS.unlink(baseName); } catch (e) {}
    try { M.FS.unlink(`/waves/${baseName}`); } catch (e) {}
    try { M.FS.unlink(`waves/${baseName}`); } catch (e) {}
    console.log(`[rototem-web] Unlinked from Emscripten VFS: ${baseName}`);
  }
}

// ---------------------------------------------------------------------------
// 5. Audio Devices & Recording
// ---------------------------------------------------------------------------

export async function listAudioDevices(callback) {
  if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) {
    if (callback) callback(toList([new AudioDevice("default", "Default Audio Output")]));
    return;
  }
  try {
    const devices = await navigator.mediaDevices.enumerateDevices();
    const audioOutputs = devices
      .filter((d) => d.kind === "audiooutput")
      .map((d, idx) => ({
        id: d.deviceId || `device-${idx}`,
        label: d.label || `Audio Output ${idx + 1}`,
      }));

    if (audioOutputs.length === 0) {
      audioOutputs.push({ id: "default", label: "Default System Output" });
    }
    const gleamDevices = toList(
      audioOutputs.map((d) => new AudioDevice(d.id, d.label)),
    );
    if (callback) callback(gleamDevices);
  } catch (err) {
    console.warn("[rototem-web] Failed to enumerate audio devices:", err);
    if (callback) callback(toList([new AudioDevice("default", "Default Audio Output")]));
  }
}

export async function setOutputDevice(deviceId, callback) {
  ensureAudioContext();
  if (audioContext && typeof audioContext.setSinkId === "function") {
    try {
      await audioContext.setSinkId(deviceId);
      if (callback) callback("Output device changed successfully");
      return;
    } catch (err) {
      console.error("[rototem-web] setSinkId error:", err);
      if (callback) callback("Failed to set output device: " + err.message);
      return;
    }
  }
  if (callback) callback("setSinkId is not supported in this browser");
}

export function toggleRecording(callback) {
  ensureAudioContext();

  if (mediaRecorder && mediaRecorder.state === "recording") {
    mediaRecorder.stop();
    if (callback) callback(false);
    return;
  }

  try {
    const dest = audioContext.createMediaStreamDestination();
    recordedChunks = [];
    mediaRecorder = new MediaRecorder(dest.stream);

    mediaRecorder.ondataavailable = (e) => {
      if (e.data.size > 0) recordedChunks.push(e.data);
    };

    mediaRecorder.onstop = () => {
      const blob = new Blob(recordedChunks, { type: "audio/webm" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `rototem-recording-${new Date().toISOString().slice(0, 10)}.webm`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    };

    mediaRecorder.start();
    if (callback) callback(true);
  } catch (err) {
    console.error("[rototem-web] MediaRecorder error:", err);
    if (callback) callback(false);
  }
}

export function getRandomInt(max) {
  if (max <= 1) return 0;
  return Math.floor(Math.random() * max);
}

