import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import rototem/settings
import rototem/skode
import rototem/skred
import rototem/types.{
  AudioFile, Dark, Floating, Grid, Light, Minimized, Normal, Track,
}
import rototem/ui
import rototem/views/common
import rototem_web

pub fn main() {
  gleeunit.main()
}

pub fn skred_command_formatting_test() {
  // Voice volume formatting
  skred.format_voice_volume(0, 1, 0.75)
  |> should.equal("v0a0.75;v1a0.75")

  // Voice speed formatting (MIDI pitch note)
  skred.format_voice_speed(2, 3, 69.0)
  |> should.equal("v2n69.0;v3n69.0")

  // Voice run / stop formatting
  skred.format_voice_run(4, 5, True)
  |> should.equal("v4l1;v5l1")

  skred.format_voice_run(4, 5, False)
  |> should.equal("v4l0;v5l0")

  // Voice mute formatting
  skred.format_voice_mute(6, 7, True)
  |> should.equal("v6m1;v7m1")

  skred.format_voice_mute(6, 7, False)
  |> should.equal("v6m0;v7m0")

  // Voice flip direction (b1 backward, b0 forward)
  skred.format_voice_flip(8, 9)
  |> should.equal("v8b; v9b;")

  skred.format_voice_direction(8, 9, True)
  |> should.equal("v8b1;v9b1")

  skred.format_voice_direction(8, 9, False)
  |> should.equal("v8b0;v9b0")

  // Master volume formatting (in dB)
  skred.format_master_volume(-2.5)
  |> should.equal(";V-2.5;")
}

pub fn settings_serialization_roundtrip_test() {
  let sample =
    AudioFile(
      id: "kick.wav",
      name: "kick.wav",
      path: "waves/kick.wav",
      size: 1024,
    )

  let track0 =
    Track(
      id: 0,
      left_voice: 0,
      right_voice: 1,
      color: "#ff5722",
      audio_file: Some(sample),
      playing: True,
      muted: False,
      volume: 0.9,
      speed: 69.0,
      reversed: True,
      card_mode: Floating(150.0, 200.0, 12),
      card_display: Normal,
    )

  let track1 =
    Track(
      id: 1,
      left_voice: 2,
      right_voice: 3,
      color: "#2196f3",
      audio_file: None,
      playing: False,
      muted: True,
      volume: 0.5,
      speed: 57.0,
      reversed: False,
      card_mode: Grid,
      card_display: Minimized,
    )

  let tracks = [track0, track1]
  let json_str = settings.serialize_project(0.8, tracks)

  let decoded_result = settings.decode_project(json_str)
  decoded_result |> should.be_ok

  let assert Ok(proj) = decoded_result
  proj.version |> should.equal(1)
  proj.format |> should.equal("rototem-web")
  proj.master_volume |> should.equal(0.8)
  list.length(proj.tracks) |> should.equal(2)

  let assert Ok(st0) = list.first(proj.tracks)
  st0.id |> should.equal(0)
  st0.sample_name |> should.equal(Some("kick.wav"))
  st0.volume |> should.equal(0.9)
  st0.playing |> should.equal(True)
  st0.muted |> should.equal(False)
  st0.reversed |> should.equal(True)
  st0.is_floating |> should.equal(True)
  st0.x |> should.equal(150.0)
  st0.y |> should.equal(200.0)
  st0.minimized |> should.equal(False)

  let assert Ok(st1) = list.last(proj.tracks)
  st1.id |> should.equal(1)
  st1.sample_name |> should.equal(None)
  st1.volume |> should.equal(0.5)
  st1.speed |> should.equal(57.0)
  st1.muted |> should.equal(True)
  st1.is_floating |> should.equal(False)
  st1.minimized |> should.equal(True)
}

pub fn theme_palette_test() {
  let dark_palette = ui.get_palette(Dark)
  dark_palette.bg_app |> should.equal("#0d1117")

  let light_palette = ui.get_palette(Light)
  light_palette.bg_app |> should.equal("#f0f2f5")
}

pub fn format_db_test() {
  ui.format_db(0.0) |> should.equal("0.0 dB")
  ui.format_db(3.5) |> should.equal("+3.5 dB")
  ui.format_db(-6.0) |> should.equal("-6.0 dB")
  ui.format_db(-0.5) |> should.equal("-0.5 dB")

  // Ensure Skred commands NEVER include '+'
  skred.format_voice_volume(0, 1, 6.0) |> should.equal("v0a6.0;v1a6.0")
  skred.format_voice_volume(0, 1, -12.5) |> should.equal("v0a-12.5;v1a-12.5")
  skred.format_master_volume(3.0) |> should.equal(";V3.0;")
  skred.format_master_volume(-6.0) |> should.equal(";V-6.0;")
}

pub fn skode_ast_and_syntax_test() {
  // 1. Strings via [...]
  skode.command_to_string(skode.StringLiteral("waves/snare.wav"))
  |> should.equal("[waves/snare.wav]")

  skode.command_to_string(skode.LoadWaveFile("waves/snare.wav"))
  |> should.equal("[waves/snare.wav] /w")

  // 2. Arrays via (...) with numbers, ties '.', rests '-', and registers '$N'
  skode.command_to_string(
    skode.DataArray([
      skode.Num(60.0),
      skode.Rest,
      skode.Num(64.0),
      skode.Tie,
      skode.Variable(2),
      skode.ReturnRef(0),
    ]),
  )
  |> should.equal("(60.0 - 64.0 . $2 @0)")

  // 3. Comments via '#'
  skode.command_to_string(skode.LineComment("set up voice 0"))
  |> should.equal("# set up voice 0")

  // 4. Macro commands starting with the letter 'e' (eR, eRR, e!, e?, e>)
  skode.command_to_string(skode.Macro(skode.RepeatSeconds(0, 4, 0.5, None)))
  |> should.equal("0,4,0.5 eR")

  skode.command_to_string(skode.Macro(skode.RepeatBeats(1, 8, 2.0, Some(42))))
  |> should.equal("1,8,2.0,42 eRR")

  skode.command_to_string(skode.Macro(skode.ExpandAndQueue(3)))
  |> should.equal("3 e!")

  skode.command_to_string(skode.Macro(skode.QueryBuffer(None)))
  |> should.equal("e?")

  skode.command_to_string(skode.Macro(skode.QueryBuffer(Some(2))))
  |> should.equal("2 e?")

  skode.command_to_string(skode.Macro(skode.StoreBuffer(1, "v0 n60 l1;")))
  |> should.equal("[v0 n60 l1;] 1 e>")

  // 5. Deferrals (+ and ~)
  skode.command_to_string(skode.DelayRelative(0.25, skode.SetGate(1.0)))
  |> should.equal("+0.25 l1.0")

  skode.command_to_string(skode.DelayTicks(4.0, skode.SetGate(0.0)))
  |> should.equal("~4.0 l0.0")

  // 6. Compound Bundle
  skode.command_to_string(
    skode.Bundle([
      skode.SetVoice(0),
      skode.SetAmp(-6.0),
      skode.SetMidiPitch(69.0, None),
      skode.SetGate(1.0),
    ]),
  )
  |> should.equal("v0; a-6.0; n69.0; l1.0")
}

pub fn skode_stereo_and_domain_helpers_test() {
  // 1. Stereo Volume
  skode.command_to_string(skode.stereo_volume(0, 1, 0.75))
  |> should.equal("v0a0.75;v1a0.75")

  // 2. Stereo Speed
  skode.command_to_string(skode.stereo_speed(2, 3, 69.0))
  |> should.equal("v2n69.0;v3n69.0")

  // 3. Stereo Run & Mute
  skode.command_to_string(skode.stereo_run(4, 5, True))
  |> should.equal("v4l1;v5l1")

  skode.command_to_string(skode.stereo_mute(6, 7, False))
  |> should.equal("v6m0;v7m0")

  // 4. Stereo Flip & Direction
  skode.command_to_string(skode.stereo_direction(8, 9, True))
  |> should.equal("v8b1;v9b1")

  skode.command_to_string(skode.stereo_flip(0, 1))
  |> should.equal("v0b; v1b;")

  // 5. Track Control Composite
  skode.command_to_string(skode.track_control(
    0,
    1,
    0.5,
    69.0,
    False,
    False,
    True,
  ))
  |> should.equal("v0a0.5;v1a0.5;v0n69.0;v1n69.0;v0m0;v1m0;v0b0;v1b0;v0l1;v1l1")

  // 6. StopAll and ResetVoices
  skode.command_to_string(skode.StopAll)
  |> should.equal("*l0;S-1;V0")

  skode.command_to_string(skode.ResetVoices(skode.AllVoices))
  |> should.equal("S-1")

  // 7. FlipVoice with VoiceTarget
  skode.command_to_string(skode.FlipVoice(skode.AllVoices))
  |> should.equal("*b")

  skode.command_to_string(skode.FlipVoice(skode.Stereo(2, 3)))
  |> should.equal("v2b; v3b;")
}

pub fn skode_named_macros_test() {
  // 1. Definition of named macro: [name] : body ;
  skode.command_to_string(skode.define_macro(
    "play",
    skode.Raw("?ce! /cer 1 Z0 Z! y0 z1"),
  ))
  |> should.equal("[play] : ?ce! /cer 1 Z0 Z! y0 z1 ;")

  skode.command_to_string(skode.define_macro(
    "stop",
    skode.Raw("/cer 0 Z0 O DQ ?ce!"),
  ))
  |> should.equal("[stop] : /cer 0 Z0 O DQ ?ce! ;")

  // 2. Macro with positional argument placeholders: $$0, $$1
  skode.command_to_string(skode.define_macro("ar", skode.Raw("t $$0 0 $$1 0")))
  |> should.equal("[ar] : t $$0 0 $$1 0 ;")

  skode.command_to_string(skode.macro_arg(0))
  |> should.equal("$$0")

  // 3. Invoking named macros with arguments
  skode.command_to_string(
    skode.call_macro("ar", [skode.Num(0.01), skode.Num(0.4)]),
  )
  |> should.equal("ar 0.01 0.4")

  skode.command_to_string(skode.call_macro("play", []))
  |> should.equal("play")

  // 4. Low-level ANDS Element MacroDef and MacroArgRef
  skode.element_to_string(
    skode.MacroDef("kik", [
      skode.Atom("v0l", [skode.MacroArg(0)]),
      skode.Atom("v1l", [skode.MacroArg(0)]),
    ]),
  )
  |> should.equal("[kik] : v0l$$0 v1l$$0 ;")
}

pub fn skode_variables_and_streams_test() {
  // 1. Variables via $ ($0 to $127)
  skode.value_to_string(skode.Variable(0))
  |> should.equal("$0")

  skode.value_to_string(skode.Variable(127))
  |> should.equal("$127")

  skode.command_to_string(skode.variable(3))
  |> should.equal("$3")

  // 2. Streams via & (&0 to &127)
  skode.value_to_string(skode.Stream(1))
  |> should.equal("&1")

  skode.value_to_string(skode.Stream(15))
  |> should.equal("&15")

  skode.command_to_string(skode.stream(2))
  |> should.equal("&2")

  // 3. Mixing variables ($), streams (&), returns (@), rests (-), and ties (.) in an array
  skode.command_to_string(
    skode.DataArray([
      skode.Num(60.0),
      skode.Variable(0),
      skode.Stream(1),
      skode.ReturnRef(2),
      skode.Tie,
      skode.Rest,
    ]),
  )
  |> should.equal("(60.0 $0 &1 @2 . -)")

  // 4. Low-level Element representation
  skode.element_to_string(skode.VarRefElement(42))
  |> should.equal("$42")

  skode.element_to_string(skode.StreamRefElement(7))
  |> should.equal("&7")
}

pub fn control_plane_events_test() {
  // 1. Voice Trigger (Type 1)
  skred.to_skred_event(
    skred.RawEvent(t: 1, seq: 10, v: 0, p: 0, s: 0, id: 0, vals: [0.95]),
  )
  |> should.equal(types.VoiceTrigger(voice: 0, velocity: 0.95))

  // 2. Voice Release (Type 2)
  skred.to_skred_event(
    skred.RawEvent(t: 2, seq: 11, v: 1, p: 0, s: 0, id: 0, vals: []),
  )
  |> should.equal(types.VoiceRelease(voice: 1))

  // 3. Voice Finished (Type 3)
  skred.to_skred_event(
    skred.RawEvent(t: 3, seq: 12, v: 2, p: 0, s: 0, id: 0, vals: []),
  )
  |> should.equal(types.VoiceFinished(voice: 2))

  // 4. User Event from "ce id, a, b, c" (Type 4)
  skred.to_skred_event(
    skred.RawEvent(t: 4, seq: 13, v: -1, p: -1, s: -1, id: 42, vals: [
      100.0,
      200.0,
      300.0,
    ]),
  )
  |> should.equal(types.UserEvent(id: 42, a: 100.0, b: 200.0, c: 300.0))

  // 5. Pattern Start / End / Step (Types 5, 6, 9)
  skred.to_skred_event(
    skred.RawEvent(t: 5, seq: 14, v: -1, p: 3, s: 0, id: 0, vals: []),
  )
  |> should.equal(types.PatternStart(pattern: 3))

  skred.to_skred_event(
    skred.RawEvent(t: 6, seq: 15, v: -1, p: 3, s: 15, id: 0, vals: []),
  )
  |> should.equal(types.PatternEnd(pattern: 3))

  skred.to_skred_event(
    skred.RawEvent(t: 9, seq: 16, v: -1, p: 0, s: 7, id: 0, vals: []),
  )
  |> should.equal(types.PatternStep(pattern: 0, step: 7))

  // 6. Tempo Change & Mute Change (Types 11, 13)
  skred.to_skred_event(
    skred.RawEvent(t: 11, seq: 17, v: -1, p: -1, s: -1, id: 0, vals: [128.0]),
  )
  |> should.equal(types.TempoChange(tempo: 128.0))

  skred.to_skred_event(
    skred.RawEvent(t: 13, seq: 18, v: -1, p: 2, s: -1, id: 0, vals: [1.0]),
  )
  |> should.equal(types.MuteChange(pattern: 2, muted: True))
}

pub fn control_plane_json_decoding_test() {
  let json_payload =
    "[{\"t\":1,\"seq\":101,\"v\":0,\"p\":0,\"s\":0,\"id\":0,\"vals\":[0.9]},{\"t\":3,\"seq\":102,\"v\":0,\"p\":0,\"s\":0,\"id\":0,\"vals\":[]},{\"t\":9,\"seq\":103,\"v\":-1,\"p\":1,\"s\":4,\"id\":0,\"vals\":[]}]"

  let decoded =
    json.parse(json_payload, decode.list(skred.raw_event_decoder()))
    |> should.be_ok

  let events = list.map(decoded, skred.to_skred_event)

  events
  |> should.equal([
    types.VoiceTrigger(voice: 0, velocity: 0.9),
    types.VoiceFinished(voice: 0),
    types.PatternStep(pattern: 1, step: 4),
  ])
}

pub fn skode_macro_buffers_and_wave_test() {
  // Wave direction
  skode.command_to_string(skode.SetWaveDirection(skode.Forward))
  |> should.equal("b0")

  skode.command_to_string(skode.SetWaveDirection(skode.Reverse))
  |> should.equal("b1")

  skode.command_to_string(skode.SetWaveDirection(skode.PingPong))
  |> should.equal("b2")

  // Wave loop & loop count
  skode.command_to_string(skode.SetWaveLoop(True))
  |> should.equal("B1")

  skode.command_to_string(skode.SetWaveLoop(False))
  |> should.equal("B0")

  skode.command_to_string(skode.SetWaveLoopCount(4))
  |> should.equal("BC4")

  // Macro buffer ops: eR, eRR, e!, e?, e>
  skode.command_to_string(skode.Macro(skode.RepeatSeconds(0, 4, 0.25, None)))
  |> should.equal("0,4,0.25 eR")

  skode.command_to_string(skode.Macro(skode.RepeatSeconds(1, 8, 0.5, Some(99))))
  |> should.equal("1,8,0.5,99 eR")

  skode.command_to_string(skode.Macro(skode.RepeatBeats(2, 16, 4.0, None)))
  |> should.equal("2,16,4.0 eRR")

  skode.command_to_string(skode.Macro(skode.ExpandAndQueue(3)))
  |> should.equal("3 e!")

  skode.command_to_string(skode.Macro(skode.QueryBuffer(None)))
  |> should.equal("e?")

  skode.command_to_string(skode.Macro(skode.QueryBuffer(Some(2))))
  |> should.equal("2 e?")

  skode.command_to_string(skode.Macro(skode.StoreBuffer(0, "v0l1")))
  |> should.equal("[v0l1] 0 e>")
}

pub fn settings_invalid_json_test() {
  settings.decode_project("not a valid json string {]")
  |> should.be_error
  |> should.equal("Failed to decode project JSON")
}

pub fn view_common_helpers_test() {
  // Float parsing
  common.parse_float_input("42.5", 0.0) |> should.equal(42.5)
  common.parse_float_input("100", 0.0) |> should.equal(100.0)
  common.parse_float_input("invalid", 12.34) |> should.equal(12.34)

  // Pitch formatting
  common.format_pitch(69.0) |> should.equal("69.0")
  common.format_pitch(60.25) |> should.equal("60.3")
}

pub fn play_all_omits_unassigned_tracks_test() {
  let #(initial_model, _) = rototem_web.init(Nil)

  // 1. Initially no tracks have audio files assigned. ToggleAllPlay should not start playback.
  let #(model_after_toggle_empty, _) =
    rototem_web.update(initial_model, types.ToggleAllPlay)
  model_after_toggle_empty.all_playing |> should.equal(False)
  list.all(model_after_toggle_empty.tracks, fn(t) { !t.playing })
  |> should.equal(True)

  // 2. Individual ToggleTrackPlay on track with no sample does nothing
  let #(model_after_single_empty, _) =
    rototem_web.update(initial_model, types.ToggleTrackPlay(0))
  let assert Ok(t0_empty) = list.first(model_after_single_empty.tracks)
  t0_empty.playing |> should.equal(False)

  // 3. Assign sample ONLY to track 0
  let sample =
    AudioFile(
      id: "snare.wav",
      name: "snare.wav",
      path: "waves/snare.wav",
      size: 2048,
    )
  let model_with_one_sample =
    types.Model(
      ..initial_model,
      library: [sample],
      tracks: list.map(initial_model.tracks, fn(t) {
        case t.id {
          0 -> types.Track(..t, audio_file: Some(sample))
          _ -> t
        }
      }),
    )

  // 4. ToggleAllPlay should start ONLY track 0; tracks 1..7 remain playing: False
  let #(model_played, _) =
    rototem_web.update(model_with_one_sample, types.ToggleAllPlay)
  model_played.all_playing |> should.equal(True)

  let assert Ok(t0_played) = list.find(model_played.tracks, fn(t) { t.id == 0 })
  t0_played.playing |> should.equal(True)

  let assert Ok(t1_unassigned) =
    list.find(model_played.tracks, fn(t) { t.id == 1 })
  t1_unassigned.playing |> should.equal(False)

  let unassigned_are_stopped =
    model_played.tracks
    |> list.filter(fn(t) { t.id != 0 })
    |> list.all(fn(t) { !t.playing })
  unassigned_are_stopped |> should.equal(True)
}

pub fn console_controls_and_execution_test() {
  let #(initial_model, _) = rototem_web.init(Nil)

  // 1. ExecuteConsoleCommand should add to history and update console_input
  let #(model_after_quick, _) =
    rototem_web.update(initial_model, types.ExecuteConsoleCommand("?a"))
  model_after_quick.console_input |> should.equal("?a")
  model_after_quick.command_history |> should.equal(["?a"])

  // 2. ClearConsole should empty console_logs
  let model_with_logs =
    types.Model(..initial_model, console_logs: [
      types.ConsoleLog("?a", 0, "audio running"),
    ])
  let #(model_cleared, _) =
    rototem_web.update(model_with_logs, types.ClearConsole)
  model_cleared.console_logs |> should.equal([])

  // 3. ResetConsolePosition should restore default coordinates and size
  let moved_model =
    types.Model(
      ..initial_model,
      console_x: 500.0,
      console_y: 300.0,
      console_width: 800.0,
      console_height: 600.0,
    )
  let #(model_reset, _) =
    rototem_web.update(moved_model, types.ResetConsolePosition)
  model_reset.console_x |> should.equal(120.0)
  model_reset.console_y |> should.equal(80.0)
  model_reset.console_width |> should.equal(620.0)
  model_reset.console_height |> should.equal(420.0)

  // 4. ToggleConsole should toggle show_console
  let #(toggled, _) = rototem_web.update(initial_model, types.ToggleConsole)
  toggled.show_console |> should.equal(True)
  let #(toggled_back, _) = rototem_web.update(toggled, types.ToggleConsole)
  toggled_back.show_console |> should.equal(False)

  // 5. JSON dynamic decode of key_down decoder for Escape and Enter
  let enter_json = "{\"key\": \"Enter\"}"
  json.parse(enter_json, common.key_down_console_decoder())
  |> should.equal(Ok(types.SubmitConsoleCommand))

  let esc_json = "{\"key\": \"Escape\"}"
  json.parse(esc_json, common.key_down_console_decoder())
  |> should.equal(Ok(types.ToggleConsole))
}
