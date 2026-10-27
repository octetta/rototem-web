import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import rototem/settings
import rototem/skred
import rototem/types.{
  AudioFile, Dark, Floating, Grid, Light, Minimized, Normal, Track,
}
import rototem/ui

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
