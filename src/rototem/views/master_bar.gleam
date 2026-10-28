//// # Master Workstation Bar View
////
//// Renders the top transport control bar (Global Play/Stop, Master Volume, Sample Loading,
//// Project ZIP Save/Load, Web Audio Output Device selector, and Live Audio Recording toggle).
////

import gleam/float
import gleam/int
import gleam/list
import lustre/attribute.{attribute, class, selected, styles, type_, value}
import lustre/element.{type Element, text}
import lustre/element/html.{
  button, div, h1, header, input, label, option, select, span,
}
import lustre/event
import rototem/types.{type Model, type Msg, Dark, Light}
import rototem/views/common.{format_db, parse_float_input}

/// Renders the top transport control bar and master workstation controls.
pub fn view_master_bar(model: Model) -> Element(Msg) {
  let is_any_playing =
    model.all_playing || list.any(model.tracks, fn(t) { t.playing })

  header([class("master-bar")], [
    // Brand Title
    div([class("brand-section")], [
      h1([class("brand-title")], [text("ROTOTEM")]),
      span([class("brand-badge")], [text("Skred Web")]),
    ]),

    // Directory Picker Button
    button(
      [
        class("btn btn-primary"),
        event.on_click(types.PickDirectory),
      ],
      [text("📂 Folder")],
    ),

    // Start / Stop All Voices Unified Button
    button(
      [
        class(case is_any_playing {
          True -> "btn btn-danger"
          False -> "btn btn-primary"
        }),
        event.on_click(types.ToggleAllPlay),
      ],
      [
        text(case is_any_playing {
          True -> "⏹ Stop All"
          False -> "▶ Start All"
        }),
      ],
    ),

    // Randomize All Samples
    button(
      [
        class("btn btn-secondary"),
        event.on_click(types.RandomizeAllSamples),
      ],
      [text("🎲 Random All")],
    ),

    // Theme Toggle Button
    button(
      [
        class("btn btn-secondary"),
        event.on_click(types.ToggleTheme),
      ],
      [
        text(case model.theme {
          Dark -> "☀️ Light"
          Light -> "🌙 Dark"
        }),
      ],
    ),

    // Master Volume Slider
    div([class("slider-group")], [
      label([class("track-voices")], [text("Master:")]),
      input([
        type_("range"),
        attribute("min", "-60"),
        attribute("max", "12"),
        attribute("step", "0.5"),
        attribute("title", "Master Volume: " <> format_db(model.master_volume)),
        value(float.to_string(model.master_volume)),
        event.on_input(fn(v) {
          types.SetMasterVolume(parse_float_input(v, model.master_volume))
        }),
        class("slider-input w-slider"),
      ]),
      span([class("track-voices w-status-num")], [
        text(format_db(model.master_volume)),
      ]),
    ]),

    // Audio Output Device Chooser
    div([], [
      select(
        [
          value(model.selected_device_id),
          event.on_change(types.SelectOutputDevice),
          event.on_input(types.SelectOutputDevice),
          class("sample-select select-device"),
        ],
        list.map(model.devices, fn(dev) {
          option(
            [
              value(dev.id),
              selected(dev.id == model.selected_device_id),
            ],
            dev.label,
          )
        }),
      ),
    ]),

    // Master Record Button
    button(
      [
        class(case model.recording {
          True -> "btn btn-record-active"
          False -> "btn btn-record-inactive"
        }),
        event.on_click(types.ToggleRecord),
      ],
      [
        span([class("record-dot")], []),
        text(case model.recording {
          True -> "Stop Rec"
          False -> "Record"
        }),
      ],
    ),

    // Console Toggle Button (Ctrl-~)
    button(
      [
        class(case model.show_console {
          True -> "btn btn-accent ml-auto"
          False -> "btn btn-secondary ml-auto"
        }),
        event.on_click(types.ToggleConsole),
      ],
      [text("Console (~)")],
    ),

    // Library Summary Toggle Button
    button(
      [
        class("btn btn-secondary"),
        event.on_click(types.ToggleLibraryModal),
      ],
      [text("Files (" <> int.to_string(list.length(model.library)) <> ")")],
    ),
  ])
}

pub fn view_status_banner(msg: String) -> Element(Msg) {
  case msg {
    "" -> element.none()
    _ ->
      div([class("status-banner")], [
        span([class("status-dot")], [text("●")]),
        text(msg),
      ])
  }
}

pub fn view_mobile_track_tabs(model: Model) -> Element(Msg) {
  div(
    [class("mobile-tabs-bar")],
    list.map(model.tracks, fn(t) {
      let is_active = t.id == model.mobile_active_track
      button(
        [
          event.on_click(types.SetMobileActiveTrack(t.id)),
          class("mobile-tab-btn"),
          styles([
            #("--tab-bg", case is_active {
              True -> t.color
              False -> "var(--bg-subtle)"
            }),
            #("--tab-color", case is_active {
              True -> "#000000"
              False -> "var(--text-main)"
            }),
          ]),
        ],
        [text("T" <> int.to_string(t.id + 1))],
      )
    }),
  )
}
