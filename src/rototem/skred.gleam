//// # Skred Audio Engine FFI Bridge & Effect Dispatcher
////
//// This module exposes type-safe Lustre `Effect` wrappers for communicating with the
//// underlying WebAssembly Skred audio engine, Web Audio hardware devices, file system (VFS),
//// ZIP archiving, and Pointer Capture DOM APIs.
////

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/result
import lustre/effect.{type Effect}
import rototem/skode
import rototem/types.{
  type AudioDevice, type AudioFile, type Msg, type SkredEvent, type VfsFile,
}

@external(javascript, "../skred_ffi.mjs", "initEngine")
fn js_init_engine(callback: fn(Bool) -> Nil) -> Nil

@external(javascript, "../skred_ffi.mjs", "subscribeEvents")
fn js_subscribe_events(callback: fn(Dynamic) -> Nil) -> fn() -> Nil

@external(javascript, "../skred_ffi.mjs", "sendCommand")
fn js_send_command(cmd: String) -> Nil

@external(javascript, "../skred_ffi.mjs", "evalCommand")
fn js_eval_command(cmd: String, callback: fn(String, Int, String) -> Nil) -> Nil

@external(javascript, "../skred_ffi.mjs", "registerConsoleToggle")
fn js_register_console_toggle(callback: fn() -> Nil) -> Nil

@external(javascript, "../skred_ffi.mjs", "loadTrackWave")
fn js_load_track_wave(left_voice: Int, right_voice: Int, path: String) -> Nil

@external(javascript, "../skred_ffi.mjs", "removeAudioFile")
fn js_remove_audio_file(file_name: String) -> Nil

@external(javascript, "../skred_ffi.mjs", "clearAllAudioFiles")
fn js_clear_all_audio_files() -> Nil

@external(javascript, "../skred_ffi.mjs", "pickDirectory")
fn js_pick_directory(callback: fn(List(AudioFile)) -> Nil) -> Nil

@external(javascript, "../skred_ffi.mjs", "exportZip")
fn js_export_zip(settings_json: String, callback: fn(String) -> Nil) -> Nil

@external(javascript, "../skred_ffi.mjs", "triggerLoadZip")
fn js_trigger_load_zip(callback: fn(String, List(AudioFile)) -> Nil) -> Nil

@external(javascript, "../skred_ffi.mjs", "pickVfsFiles")
fn js_pick_vfs_files(callback: fn(List(VfsFile)) -> Nil) -> Nil

@external(javascript, "../skred_ffi.mjs", "removeVfsFile")
fn js_remove_vfs_file(name: String) -> Nil

@external(javascript, "../skred_ffi.mjs", "listAudioDevices")
fn js_list_audio_devices(callback: fn(List(AudioDevice)) -> Nil) -> Nil

@external(javascript, "../skred_ffi.mjs", "setOutputDevice")
fn js_set_output_device(device_id: String, callback: fn(String) -> Nil) -> Nil

@external(javascript, "../skred_ffi.mjs", "toggleRecording")
fn js_toggle_recording(callback: fn(Bool) -> Nil) -> Nil

/// Invokes `element.setPointerCapture(event.pointerId)` via JS FFI.
@external(javascript, "../skred_ffi.mjs", "capturePointer")
pub fn capture_pointer(event: Dynamic) -> Nil

/// Releases pointer capture via JS FFI.
@external(javascript, "../skred_ffi.mjs", "releasePointer")
pub fn release_pointer(event: Dynamic) -> Nil

/// Returns a pseudo-random integer in `[0, max)` via JS `Math.random`.
@external(javascript, "../skred_ffi.mjs", "getRandomInt")
pub fn get_random_int(max: Int) -> Int

/// Effect initializing the WebAssembly Skred audio engine.
pub fn init_engine_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_init_engine(fn(success) { dispatch(types.EngineInitialized(success)) })
  })
}

/// Dispatches an ad-hoc raw string command into the audio engine.
pub fn send_command(cmd: String) -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_send_command(cmd) })
}

/// Send a typed Skode AST command to the audio engine.
pub fn send(cmd: skode.SkodeCommand) -> Effect(Msg) {
  send_command(skode.command_to_string(cmd))
}

/// Evaluates a command string and returns its return code and stdout log.
pub fn eval_command_effect(cmd: String) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_eval_command(cmd, fn(c, ret, resp) {
      dispatch(types.ConsoleResultReceived(c, ret, resp))
    })
  })
}

/// Registers the global `Ctrl-~` keyboard listener for toggling the REPL console.
pub fn register_console_toggle_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_register_console_toggle(fn() { dispatch(types.ToggleConsole) })
  })
}

/// Mounts an audio file from VFS `/waves` onto a stereo voice pair in Skred.
pub fn load_track_wave(
  left_voice: Int,
  right_voice: Int,
  path: String,
) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    js_load_track_wave(left_voice, right_voice, path)
  })
}

/// Prompts the user to select a folder of audio files via the browser Directory Picker.
pub fn pick_directory_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_pick_directory(fn(files) { dispatch(types.FilesLoaded(files)) })
  })
}

/// Removes a mounted audio file from memory and the Emscripten VFS.
pub fn remove_audio_file(file_name: String) -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_remove_audio_file(file_name) })
}

/// Clears all loaded audio files from the in-memory library and VFS.
pub fn clear_audio_library() -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_clear_all_audio_files() })
}

/// Packs project settings and audio files into a ZIP archive and triggers browser download.
pub fn export_zip_effect(settings_json: String) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_export_zip(settings_json, fn(msg) { dispatch(types.StatusUpdated(msg)) })
  })
}

/// Prompts the user to pick a `.zip` project file, unzips settings and audio files into VFS.
pub fn load_zip_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_trigger_load_zip(fn(settings, files) {
      dispatch(types.ZipProjectLoaded(settings, files))
    })
  })
}

/// Prompts the user to pick generic files (.zip, .sk, .ks, .wav, .mp3, .flac) to write directly into Emscripten VFS.
pub fn pick_vfs_files_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_pick_vfs_files(fn(files) { dispatch(types.VfsFilesUploaded(files)) })
  })
}

/// Removes a file from Emscripten VFS.
pub fn remove_vfs_file_effect(name: String) -> Effect(Msg) {
  effect.from(fn(_dispatch) { js_remove_vfs_file(name) })
}

/// Enumerates connected audio output devices via the Web Audio API.
pub fn list_devices_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_list_audio_devices(fn(devices) {
      dispatch(types.AudioDevicesListed(devices))
    })
  })
}

/// Sets the Web Audio sink destination to a specific audio output device ID.
pub fn set_output_device_effect(device_id: String) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_set_output_device(device_id, fn(msg) {
      dispatch(types.StatusUpdated(msg))
    })
  })
}

/// Starts or stops live WAV recording of the master Web Audio stream.
pub fn toggle_recording_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_toggle_recording(fn(rec_state) {
      dispatch(types.RecordingStateChanged(rec_state))
    })
  })
}

// ---------------------------------------------------------------------------
// Control Plane Event Decoders & Subscription
// ---------------------------------------------------------------------------

/// Intermediate representation of an unpacked binary Skred control event received across FFI.
pub type RawEvent {
  RawEvent(t: Int, seq: Int, v: Int, p: Int, s: Int, id: Int, vals: List(Float))
}

/// Dynamic decoder for JSON-like objects emitted by the WASM control plane poller.
pub fn raw_event_decoder() -> decode.Decoder(RawEvent) {
  use t <- decode.field("t", decode.int)
  use seq <- decode.optional_field("seq", 0, decode.int)
  use v <- decode.field("v", decode.int)
  use p <- decode.field("p", decode.int)
  use s <- decode.field("s", decode.int)
  use id <- decode.field("id", decode.int)
  use vals <- decode.field("vals", decode.list(decode.float))
  decode.success(RawEvent(t:, seq:, v:, p:, s:, id:, vals:))
}

/// Converts a decoded `RawEvent` into a typed domain `SkredEvent`.
pub fn to_skred_event(raw: RawEvent) -> SkredEvent {
  case raw.t {
    // SKRED_CONTROL_EVENT_VOICE_TRIGGER = 1
    1 -> {
      let vel = list.first(raw.vals) |> result.unwrap(0.8)
      types.VoiceTrigger(voice: raw.v, velocity: vel)
    }
    // SKRED_CONTROL_EVENT_VOICE_RELEASE = 2
    2 -> types.VoiceRelease(voice: raw.v)
    // SKRED_CONTROL_EVENT_VOICE_FINISHED = 3
    3 -> types.VoiceFinished(voice: raw.v)
    // SKRED_CONTROL_EVENT_USER = 4
    4 -> {
      let #(a, b, c) = case raw.vals {
        [x, y, z, ..] -> #(x, y, z)
        [x, y] -> #(x, y, 0.0)
        [x] -> #(x, 0.0, 0.0)
        [] -> #(0.0, 0.0, 0.0)
      }
      types.UserEvent(id: raw.id, a:, b:, c:)
    }
    // SKRED_CONTROL_EVENT_PATTERN_START = 5
    5 -> types.PatternStart(pattern: raw.p)
    // SKRED_CONTROL_EVENT_PATTERN_END = 6
    6 -> types.PatternEnd(pattern: raw.p)
    // SKRED_CONTROL_EVENT_PATTERN_STEP = 9
    9 -> types.PatternStep(pattern: raw.p, step: raw.s)
    // SKRED_CONTROL_EVENT_TEMPO_CHANGE = 11
    11 -> {
      let bpm = list.first(raw.vals) |> result.unwrap(120.0)
      types.TempoChange(tempo: bpm)
    }
    // SKRED_CONTROL_EVENT_MUTE_CHANGE = 13
    13 -> {
      let muted = list.first(raw.vals) |> result.unwrap(0.0) >. 0.5
      types.MuteChange(pattern: raw.p, muted:)
    }
    other -> types.OtherEvent(type_id: other)
  }
}

/// Decodes a Dynamic JS array of raw event objects into a list of typed `SkredEvent`s.
pub fn decode_events(
  dynamic_array: Dynamic,
) -> Result(List(SkredEvent), List(decode.DecodeError)) {
  decode.run(
    dynamic_array,
    decode.list(raw_event_decoder())
      |> decode.map(fn(raw_list) { list.map(raw_list, to_skred_event) }),
  )
}

/// Subscribes to the 60Hz batched control plane event stream from Skred.
pub fn subscribe_control_plane(
  on_batch: fn(List(SkredEvent)) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    js_subscribe_events(fn(dynamic_array) {
      case decode_events(dynamic_array) {
        Ok(events) -> dispatch(on_batch(events))
        Error(_) -> Nil
      }
    })
    Nil
  })
}

/// Helper to format voice volume commands for a stereo pair: "v0a0.8;v1a0.8" (no '+' for Skred)
pub fn format_voice_volume(
  left_voice: Int,
  right_voice: Int,
  volume: Float,
) -> String {
  skode.command_to_string(skode.stereo_volume(left_voice, right_voice, volume))
}

/// Helper to format voice speed (MIDI note pitch): "v0n69;v1n69" (no '+' for Skred)
pub fn format_voice_speed(
  left_voice: Int,
  right_voice: Int,
  midi_pitch: Float,
) -> String {
  skode.command_to_string(skode.stereo_speed(
    left_voice,
    right_voice,
    midi_pitch,
  ))
}

/// Helper to format voice start/stop for a stereo pair: "v0l1;v1l1"
pub fn format_voice_run(
  left_voice: Int,
  right_voice: Int,
  running: Bool,
) -> String {
  skode.command_to_string(skode.stereo_run(left_voice, right_voice, running))
}

/// Helper to format voice mute for a stereo pair: "v0m1;v1m1"
pub fn format_voice_mute(
  left_voice: Int,
  right_voice: Int,
  muted: Bool,
) -> String {
  skode.command_to_string(skode.stereo_mute(left_voice, right_voice, muted))
}

/// Helper to set voice playback direction: "v0b1;v1b1" (reverse) or "v0b0;v1b0" (forward)
pub fn format_voice_direction(
  left_voice: Int,
  right_voice: Int,
  reversed: Bool,
) -> String {
  skode.command_to_string(skode.stereo_direction(
    left_voice,
    right_voice,
    reversed,
  ))
}

/// Helper to toggle voice playback direction for a stereo pair: "v0b; v1b;"
pub fn format_voice_flip(left_voice: Int, right_voice: Int) -> String {
  skode.command_to_string(skode.stereo_flip(left_voice, right_voice))
}

/// Helper for master volume in decibels: ";V-6.0;" (0.0 dB unity, no '+' for Skred)
pub fn format_master_volume(vol_db: Float) -> String {
  skode.command_to_string(skode.SetMasterVolume(vol_db))
}
