import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import rototem/types.{
  type Track, Floating, Grid, Minimized, Normal,
}

pub type SavedTrack {
  SavedTrack(
    id: Int,
    sample_name: Option(String),
    volume: Float,
    speed: Float,
    muted: Bool,
    playing: Bool,
    reversed: Bool,
    is_floating: Bool,
    x: Float,
    y: Float,
    minimized: Bool,
  )
}

pub type SavedProject {
  SavedProject(
    format: String,
    version: Int,
    master_volume: Float,
    tracks: List(SavedTrack),
  )
}

pub fn serialize_project(
  master_volume: Float,
  tracks: List(Track),
) -> String {
  let track_objects =
    list.map(tracks, fn(t) {
      let #(is_floating, x, y) = case t.card_mode {
        Grid -> #(False, 0.0, 0.0)
        Floating(fx, fy, _) -> #(True, fx, fy)
      }
      let minimized = case t.card_display {
        Minimized -> True
        Normal -> False
      }
      let sample_name = case t.audio_file {
        Some(f) -> json.string(f.name)
        None -> json.null()
      }

      json.object([
        #("id", json.int(t.id)),
        #("sample_name", sample_name),
        #("volume", json.float(t.volume)),
        #("speed", json.float(t.speed)),
        #("muted", json.bool(t.muted)),
        #("playing", json.bool(t.playing)),
        #("reversed", json.bool(t.reversed)),
        #("is_floating", json.bool(is_floating)),
        #("x", json.float(x)),
        #("y", json.float(y)),
        #("minimized", json.bool(minimized)),
      ])
    })

  json.object([
    #("format", json.string("rototem-web")),
    #("version", json.int(1)),
    #("master_volume", json.float(master_volume)),
    #("tracks", json.array(track_objects, fn(x) { x })),
  ])
  |> json.to_string
}

fn saved_track_decoder() -> decode.Decoder(SavedTrack) {
  use id <- decode.field("id", decode.int)
  use sample_name <- decode.optional_field("sample_name", None, decode.optional(decode.string))
  use volume <- decode.optional_field("volume", 0.8, decode.float)
  use speed <- decode.optional_field("speed", 69.0, decode.float)
  use muted <- decode.optional_field("muted", False, decode.bool)
  use playing <- decode.optional_field("playing", False, decode.bool)
  use reversed <- decode.optional_field("reversed", False, decode.bool)
  use is_floating <- decode.optional_field("is_floating", False, decode.bool)
  use x <- decode.optional_field("x", 100.0, decode.float)
  use y <- decode.optional_field("y", 100.0, decode.float)
  use minimized <- decode.optional_field("minimized", False, decode.bool)

  decode.success(SavedTrack(
    id:,
    sample_name:,
    volume:,
    speed:,
    muted:,
    playing:,
    reversed:,
    is_floating:,
    x:,
    y:,
    minimized:,
  ))
}

fn project_decoder() -> decode.Decoder(SavedProject) {
  use format <- decode.optional_field("format", "rototem-web", decode.string)
  use version <- decode.optional_field("version", 1, decode.int)
  use master_volume <- decode.optional_field("master_volume", 0.8, decode.float)
  use tracks <- decode.optional_field("tracks", [], decode.list(saved_track_decoder()))

  decode.success(SavedProject(
    format:,
    version:,
    master_volume:,
    tracks:,
  ))
}

pub fn decode_project(json_string: String) -> Result(SavedProject, String) {
  json.parse(json_string, project_decoder())
  |> result.map_error(fn(_err) { "Failed to decode project JSON" })
}
