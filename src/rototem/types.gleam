//// # Rototem Domain Types & Messages
////
//// Defines the core domain models, state containers, and action messages for `rototem-web`
//// according to The Elm Architecture (TEA) in Lustre.
////

import gleam/option.{type Option}

/// Real-time control plane notifications emitted by Skred's audio engine.
pub type SkredEvent {
  /// Voice triggered by command, pad, or sequencer (voice 0..255, velocity 0.0..1.0)
  VoiceTrigger(voice: Int, velocity: Float)
  /// Voice release / note-off
  VoiceRelease(voice: Int)
  /// Voice playback finished naturally (envelope or wave end)
  VoiceFinished(voice: Int)
  /// Sequencer pattern step reached (pattern index, step index 0..15)
  PatternStep(pattern: Int, step: Int)
  /// Sequencer pattern began playback
  PatternStart(pattern: Int)
  /// Sequencer pattern finished its cycle
  PatternEnd(pattern: Int)
  /// Global tempo changed (in BPM)
  TempoChange(tempo: Float)
  /// Pattern mute state toggled
  MuteChange(pattern: Int, muted: Bool)
  /// Custom user marker event emitted via Skode "ce id, a, b, c"
  UserEvent(id: Int, a: Float, b: Float, c: Float)
  /// Other control plane event
  OtherEvent(type_id: Int)
}

/// Represents an audio sample loaded into the in-memory or VFS library.
pub type AudioFile {
  AudioFile(id: String, name: String, path: String, size: Int)
}

/// Positioning mode for a track card in the UI workspace.
pub type CardMode {
  /// Card is docked inside the standard CSS auto-fitting responsive grid.
  Grid
  /// Card is popped out into the floating overlay layer with explicit coordinates.
  Floating(x: Float, y: Float, z_index: Int)
}

/// Visual expansion state of a track card.
pub type CardDisplay {
  Normal
  Minimized
}

/// UI color theme selection.
pub type Theme {
  Dark
  Light
}

/// Represents one of the 8 stereo track channels (16 underlying voices).
pub type Track {
  Track(
    id: Int,
    left_voice: Int,
    right_voice: Int,
    color: String,
    audio_file: Option(AudioFile),
    playing: Bool,
    muted: Bool,
    volume: Float,
    speed: Float,
    reversed: Bool,
    card_mode: CardMode,
    card_display: CardDisplay,
  )
}

/// Represents an output audio playback hardware device reported by Web Audio.
pub type AudioDevice {
  AudioDevice(id: String, label: String)
}

/// Represents the active drag gesture state for floating track cards.
pub type ActiveDrag {
  ActiveDrag(
    track_id: Int,
    start_card_x: Float,
    start_card_y: Float,
    start_mouse_x: Float,
    start_mouse_y: Float,
  )
}

/// A line of execution history and stdout output in the Skred diagnostic console.
pub type ConsoleLog {
  ConsoleLog(cmd: String, ret: Int, response: String)
}

/// Complete application state container for the Lustre runtime.
pub type Model {
  Model(
    tracks: List(Track),
    library: List(AudioFile),
    master_volume: Float,
    all_playing: Bool,
    recording: Bool,
    devices: List(AudioDevice),
    selected_device_id: String,
    active_drag: Option(ActiveDrag),
    next_z_index: Int,
    status_message: String,
    show_library_modal: Bool,
    // Skred Console / REPL (Ctrl-~)
    show_console: Bool,
    console_input: String,
    console_logs: List(ConsoleLog),
    command_history: List(String),
    history_index: Int,
    // Floating & Resizable Console Window
    console_x: Float,
    console_y: Float,
    console_width: Float,
    console_height: Float,
    console_dragging: Bool,
    console_drag_start_x: Float,
    console_drag_start_y: Float,
    console_drag_mouse_x: Float,
    console_drag_mouse_y: Float,
    // Mobile Viewport State
    mobile_active_track: Int,
    // UI Theme
    theme: Theme,
  )
}

/// TEA Action Messages dispatched by UI events, timers, and FFI effects.
pub type Msg {
  // Track Actions
  SelectTrackSample(track_id: Int, file_id: String)
  RandomTrackSample(track_id: Int)
  ToggleTrackPlay(track_id: Int)
  SetTrackVolume(track_id: Int, volume: Float)
  SetTrackSpeed(track_id: Int, midi_pitch: Float)
  StepTrackSpeed(track_id: Int, semitone_offset: Float)
  ToggleTrackMute(track_id: Int)
  ToggleTrackDirection(track_id: Int)
  ToggleTrackMinimize(track_id: Int)
  RestoreAllTracks
  FloatTrackCard(track_id: Int)
  DockTrackCard(track_id: Int)
  StartDragCard(
    track_id: Int,
    card_x: Float,
    card_y: Float,
    mouse_x: Float,
    mouse_y: Float,
  )
  DragCard(mouse_x: Float, mouse_y: Float)
  EndDragCard

  // Master Actions
  PickDirectory
  ToggleAllPlay
  SetAllPlay(playing: Bool)
  RandomizeAllSamples
  SaveProjectZip
  TriggerLoadZip
  SetMasterVolume(volume: Float)
  SelectOutputDevice(device_id: String)
  ToggleRecord
  ToggleLibraryModal
  ToggleTheme
  RemoveAudioFile(file_id: String)
  ClearAudioLibrary

  // Skred Ctrl-~ Console REPL
  ToggleConsole
  SetConsoleInput(String)
  SubmitConsoleCommand
  ExecuteConsoleCommand(String)
  ConsoleHistoryUp
  ConsoleHistoryDown
  ConsoleResultReceived(cmd: String, ret: Int, response: String)
  ClearConsole
  StartDragConsole(mouse_x: Float, mouse_y: Float)
  DragConsole(mouse_x: Float, mouse_y: Float)
  EndDragConsole
  ResetConsolePosition

  // Mobile navigation
  SetMobileActiveTrack(Int)

  // Asynchronous & FFI Callbacks
  FilesLoaded(files: List(AudioFile))
  ZipProjectLoaded(json_settings: String, files: List(AudioFile))
  AudioDevicesListed(devices: List(AudioDevice))
  StatusUpdated(msg: String)
  EngineInitialized(success: Bool)
  RecordingStateChanged(recording: Bool)
  ControlEventsReceived(events: List(SkredEvent))
}
