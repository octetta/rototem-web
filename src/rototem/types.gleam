import gleam/option.{type Option}

pub type AudioFile {
  AudioFile(
    id: String,
    name: String,
    path: String,
    size: Int,
  )
}

pub type CardMode {
  Grid
  Floating(x: Float, y: Float, z_index: Int)
}

pub type CardDisplay {
  Normal
  Minimized
}

pub type Theme {
  Dark
  Light
}

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

pub type AudioDevice {
  AudioDevice(id: String, label: String)
}

pub type ActiveDrag {
  ActiveDrag(
    track_id: Int,
    start_card_x: Float,
    start_card_y: Float,
    start_mouse_x: Float,
    start_mouse_y: Float,
  )
}

pub type ConsoleLog {
  ConsoleLog(
    cmd: String,
    ret: Int,
    response: String,
  )
}

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
  FloatTrackCard(track_id: Int)
  DockTrackCard(track_id: Int)
  StartDragCard(track_id: Int, card_x: Float, card_y: Float, mouse_x: Float, mouse_y: Float)
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
}
