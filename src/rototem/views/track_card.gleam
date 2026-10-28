//// # Track Card Views (Grid & GPU-Composited Floating Overlay)
////
//// Renders the track cards in either responsive Grid or GPU-composited Floating mode.
//// Floating cards leverage CSS custom properties (`--card-x`, `--card-y`) and `translate3d`
//// transforms with Pointer Events and Pointer Capture for silky smooth dragging.
////

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute.{attribute, class, selected, styles, type_, value}
import lustre/element.{type Element, text}
import lustre/element/html.{button, div, input, option, select, span}
import lustre/event
import rototem/types.{
  type AudioFile, type Msg, type Track, Floating, Grid, Minimized, Normal,
}
import rototem/views/common.{
  format_db, format_pitch, parse_float_input, pointer_down_drag_decoder,
}

/// Renders the responsive CSS grid container for all docked track cards.
pub fn view_card_grid(
  tracks: List(Track),
  library: List(AudioFile),
  _mobile_active_track: Int,
) -> Element(Msg) {
  let docked_tracks =
    list.filter(tracks, fn(t) {
      case t.card_mode {
        Grid -> True
        Floating(_, _, _) -> False
      }
    })

  div(
    [class("tracks-grid")],
    list.map(docked_tracks, fn(track) { view_track_card(track, library) }),
  )
}

/// Renders the absolute floating layer containing popped-out GPU-composited cards.
pub fn view_floating_layer(
  tracks: List(Track),
  library: List(AudioFile),
) -> Element(Msg) {
  let floating_tracks =
    list.filter(tracks, fn(t) {
      case t.card_mode {
        Floating(_, _, _) -> True
        Grid -> False
      }
    })

  div(
    [class("floating-layer")],
    list.map(floating_tracks, fn(track) { view_track_card(track, library) }),
  )
}

/// Renders an individual track card in docked or floating mode.
pub fn view_track_card(track: Track, library: List(AudioFile)) -> Element(Msg) {
  let is_minimized = case track.card_display {
    Minimized -> True
    Normal -> False
  }

  // Fast GPU-composited styling via CSS Custom Properties
  let #(is_floating, card_classes, card_styles) = case track.card_mode {
    Grid -> #(False, "track-card", [#("--track-color", track.color)])
    Floating(x, y, z) -> #(True, "track-card floating", [
      #("--track-color", track.color),
      #("--card-x", float.to_string(x)),
      #("--card-y", float.to_string(y)),
      #("--card-z", int.to_string(z)),
    ])
  }

  div([class(card_classes), styles(card_styles)], [
    view_card_header(track, is_floating),
    case is_minimized {
      True -> view_card_minimized_body(track)
      False -> view_card_expanded_body(track, library)
    },
  ])
}

fn view_card_header(track: Track, is_floating: Bool) -> Element(Msg) {
  let is_minimized = case track.card_display {
    Minimized -> True
    Normal -> False
  }

  let #(fx, fy) = case track.card_mode {
    Floating(x, y, _) -> #(x, y)
    Grid -> #(100.0, 100.0)
  }

  let header_drag_attrs = case is_floating {
    True -> [
      class("card-header draggable"),
      event.on("pointerdown", pointer_down_drag_decoder(track.id, fx, fy)),
    ]
    False -> [class("card-header")]
  }

  div(header_drag_attrs, [
    div([class("card-header-left")], [
      span([class("track-title")], [
        text("Track " <> int.to_string(track.id + 1)),
      ]),
      span([class("track-voices")], [
        text(
          "v"
          <> int.to_string(track.left_voice)
          <> "/v"
          <> int.to_string(track.right_voice),
        ),
      ]),
    ]),
    div([class("card-header-right")], [
      button(
        [
          class("card-action-btn"),
          event.on_click(case is_floating {
            True -> types.DockTrackCard(track.id)
            False -> types.FloatTrackCard(track.id)
          }),
        ],
        [
          text(case is_floating {
            True -> "↙ Dock"
            False -> "↗ Float"
          }),
        ],
      ),
      button(
        [
          class("card-action-btn"),
          event.on_click(types.ToggleTrackMinimize(track.id)),
        ],
        [
          text(case is_minimized {
            True -> "□"
            False -> "_"
          }),
        ],
      ),
    ]),
  ])
}

fn view_card_minimized_body(track: Track) -> Element(Msg) {
  let sample_label = case track.audio_file {
    Some(f) -> f.name
    None -> ""
  }

  div([class("card-minimized-body")], [
    span([class("sample-name-min")], [text(sample_label)]),
    div([class("minimized-controls")], [
      button(
        [
          class(case track.playing {
            True -> "btn btn-danger btn-xs"
            False -> "btn btn-primary btn-xs"
          }),
          event.on_click(types.ToggleTrackPlay(track.id)),
        ],
        [
          text(case track.playing {
            True -> "⏹"
            False -> "▶"
          }),
        ],
      ),
      button(
        [
          class(case track.muted {
            True -> "btn btn-danger btn-xs"
            False -> "btn btn-secondary btn-xs"
          }),
          event.on_click(types.ToggleTrackMute(track.id)),
        ],
        [
          text(case track.muted {
            True -> "🔇"
            False -> "🔊"
          }),
        ],
      ),
    ]),
  ])
}

fn view_card_expanded_body(
  track: Track,
  library: List(AudioFile),
) -> Element(Msg) {
  let selected_file_id = case track.audio_file {
    Some(f) -> f.id
    None -> ""
  }

  div([class("card-body")], [
    // Sample Selection Row
    div([class("sample-row")], [
      select(
        [
          value(selected_file_id),
          event.on_change(fn(fid) { types.SelectTrackSample(track.id, fid) }),
          event.on_input(fn(fid) { types.SelectTrackSample(track.id, fid) }),
          class("sample-select"),
        ],
        [
          option(
            [
              value(""),
              selected(selected_file_id == ""),
            ],
            "",
          ),
          ..list.map(library, fn(f) {
            option(
              [
                value(f.id),
                selected(f.id == selected_file_id),
              ],
              f.name,
            )
          })
        ],
      ),
      button(
        [
          class("btn-random"),
          event.on_click(types.RandomTrackSample(track.id)),
          attribute("title", "Assign random sample"),
        ],
        [text("🎲")],
      ),
    ]),

    // Transport & Mute & Direction Controls
    div([class("transport-row")], [
      button(
        [
          class(case track.playing {
            True -> "btn-transport btn-play-active"
            False -> "btn-transport btn-play-inactive"
          }),
          event.on_click(types.ToggleTrackPlay(track.id)),
        ],
        [
          text(case track.playing {
            True -> "⏹ Stop"
            False -> "▶ Play"
          }),
        ],
      ),
      button(
        [
          class(case track.muted {
            True -> "btn-transport btn-mute-active"
            False -> "btn-transport btn-mute-inactive"
          }),
          event.on_click(types.ToggleTrackMute(track.id)),
        ],
        [
          text(case track.muted {
            True -> "🔇 Muted"
            False -> "🔊 Mute"
          }),
        ],
      ),
      button(
        [
          class(case track.reversed {
            True -> "btn-transport btn-rev-active"
            False -> "btn-transport btn-rev-inactive"
          }),
          event.on_click(types.ToggleTrackDirection(track.id)),
        ],
        [
          text(case track.reversed {
            True -> "⇄ Rev"
            False -> "⇄ Fwd"
          }),
        ],
      ),
    ]),

    // Volume Slider
    div([class("slider-group")], [
      span([class("slider-icon"), attribute("title", "Volume")], [text("🔊")]),
      input([
        type_("range"),
        attribute("min", "-60"),
        attribute("max", "12"),
        attribute("step", "0.1"),
        attribute("title", "Volume: " <> format_db(track.volume)),
        value(float.to_string(track.volume)),
        event.on_input(fn(v) {
          types.SetTrackVolume(track.id, parse_float_input(v, track.volume))
        }),
        class("slider-input"),
      ]),
    ]),

    // Speed / Pitch Slider
    div([class("slider-group")], [
      span([class("slider-icon"), attribute("title", "Pitch")], [text("🎵")]),
      input([
        type_("range"),
        attribute("min", "0"),
        attribute("max", "127"),
        attribute("step", "0.1"),
        attribute("title", "Pitch: n" <> format_pitch(track.speed)),
        value(float.to_string(track.speed)),
        event.on_input(fn(v) {
          types.SetTrackSpeed(track.id, parse_float_input(v, track.speed))
        }),
        class("slider-input"),
      ]),
    ]),

    // Quick Pitch Buttons: ½× (-12), -1, 1× (69), +1, 2× (+12)
    div([class("pitch-btn-grid")], [
      quick_pitch_btn(track.id, "½×", -12.0),
      quick_pitch_btn(track.id, "-1", -1.0),
      button(
        [
          class("quick-pitch-btn reset-btn"),
          event.on_click(types.StepTrackSpeed(track.id, 0.0)),
        ],
        [text("1×")],
      ),
      quick_pitch_btn(track.id, "+1", 1.0),
      quick_pitch_btn(track.id, "2×", 12.0),
    ]),

    // Status Info Line: Volume (left), Pitch (right)
    div([class("track-status-line")], [
      span([], [
        text("Vol: "),
        span([class("track-status-val")], [text(format_db(track.volume))]),
      ]),
      span([], [
        text("Pitch: "),
        span([class("track-status-pitch")], [
          text("n" <> format_pitch(track.speed)),
        ]),
      ]),
    ]),
  ])
}

fn quick_pitch_btn(
  track_id: Int,
  label_text: String,
  offset: Float,
) -> Element(Msg) {
  button(
    [
      class("quick-pitch-btn"),
      event.on_click(types.StepTrackSpeed(track_id, offset)),
    ],
    [text(label_text)],
  )
}
