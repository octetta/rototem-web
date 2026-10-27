import gleam/float
import gleam/int
import gleam/string
import lustre/effect.{type Effect}
import rototem/types.{type AudioDevice, type AudioFile, type Msg}

@external(javascript, "../skred_ffi.mjs", "initEngine")
fn js_init_engine(callback: fn(Bool) -> Nil) -> Nil

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

@external(javascript, "../skred_ffi.mjs", "listAudioDevices")
fn js_list_audio_devices(callback: fn(List(AudioDevice)) -> Nil) -> Nil

@external(javascript, "../skred_ffi.mjs", "setOutputDevice")
fn js_set_output_device(device_id: String, callback: fn(String) -> Nil) -> Nil

@external(javascript, "../skred_ffi.mjs", "toggleRecording")
fn js_toggle_recording(callback: fn(Bool) -> Nil) -> Nil

@external(javascript, "../skred_ffi.mjs", "getRandomInt")
pub fn get_random_int(max: Int) -> Int


pub fn init_engine_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_init_engine(fn(success) {
      dispatch(types.EngineInitialized(success))
    })
  })
}

pub fn send_command(cmd: String) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    js_send_command(cmd)
  })
}

pub fn eval_command_effect(cmd: String) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_eval_command(cmd, fn(c, ret, resp) {
      dispatch(types.ConsoleResultReceived(c, ret, resp))
    })
  })
}

pub fn register_console_toggle_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_register_console_toggle(fn() {
      dispatch(types.ToggleConsole)
    })
  })
}

pub fn load_track_wave(left_voice: Int, right_voice: Int, path: String) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    js_load_track_wave(left_voice, right_voice, path)
  })
}

pub fn pick_directory_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_pick_directory(fn(files) {
      dispatch(types.FilesLoaded(files))
    })
  })
}

pub fn remove_audio_file(file_name: String) -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    js_remove_audio_file(file_name)
  })
}

pub fn clear_audio_library() -> Effect(Msg) {
  effect.from(fn(_dispatch) {
    js_clear_all_audio_files()
  })
}

pub fn export_zip_effect(settings_json: String) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_export_zip(settings_json, fn(msg) {
      dispatch(types.StatusUpdated(msg))
    })
  })
}

pub fn load_zip_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_trigger_load_zip(fn(settings, files) {
      dispatch(types.ZipProjectLoaded(settings, files))
    })
  })
}

pub fn list_devices_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_list_audio_devices(fn(devices) {
      dispatch(types.AudioDevicesListed(devices))
    })
  })
}

pub fn set_output_device_effect(device_id: String) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_set_output_device(device_id, fn(msg) {
      dispatch(types.StatusUpdated(msg))
    })
  })
}

pub fn toggle_recording_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    js_toggle_recording(fn(rec_state) {
      dispatch(types.RecordingStateChanged(rec_state))
    })
  })
}

/// Helper to format voice volume commands for a stereo pair: "v0a0.8;v1a0.8" (no '+' for Skred)
pub fn format_voice_volume(left_voice: Int, right_voice: Int, volume: Float) -> String {
  let v_str = string.replace(float.to_string(volume), "+", "")
  "v" <> int.to_string(left_voice) <> "a" <> v_str <> ";v" <> int.to_string(right_voice) <> "a" <> v_str
}

/// Helper to format voice speed (MIDI note pitch): "v0n69;v1n69" (no '+' for Skred)
pub fn format_voice_speed(left_voice: Int, right_voice: Int, midi_pitch: Float) -> String {
  let p_str = string.replace(float.to_string(midi_pitch), "+", "")
  "v" <> int.to_string(left_voice) <> "n" <> p_str <> ";v" <> int.to_string(right_voice) <> "n" <> p_str
}

/// Helper to format voice start/stop for a stereo pair: "v0l1;v1l1"
pub fn format_voice_run(left_voice: Int, right_voice: Int, running: Bool) -> String {
  let r_str = case running {
    True -> "1"
    False -> "0"
  }
  "v" <> int.to_string(left_voice) <> "l" <> r_str <> ";v" <> int.to_string(right_voice) <> "l" <> r_str
}

/// Helper to format voice mute for a stereo pair: "v0m1;v1m1"
pub fn format_voice_mute(left_voice: Int, right_voice: Int, muted: Bool) -> String {
  let m_str = case muted {
    True -> "1"
    False -> "0"
  }
  "v" <> int.to_string(left_voice) <> "m" <> m_str <> ";v" <> int.to_string(right_voice) <> "m" <> m_str
}

/// Helper to set voice playback direction: "v0b1;v1b1" (reverse) or "v0b0;v1b0" (forward)
pub fn format_voice_direction(left_voice: Int, right_voice: Int, reversed: Bool) -> String {
  let b_val = case reversed {
    True -> "1"
    False -> "0"
  }
  "v" <> int.to_string(left_voice) <> "b" <> b_val <> ";v" <> int.to_string(right_voice) <> "b" <> b_val
}

/// Helper to toggle voice playback direction for a stereo pair: "v0b; v1b;"
pub fn format_voice_flip(left_voice: Int, right_voice: Int) -> String {
  "v" <> int.to_string(left_voice) <> "b; v" <> int.to_string(right_voice) <> "b;"
}

/// Helper for master volume in decibels: ";V-6.0;" (0.0 dB unity, no '+' for Skred)
pub fn format_master_volume(vol_db: Float) -> String {
  let v_str = string.replace(float.to_string(vol_db), "+", "")
  ";V" <> v_str <> ";"
}
