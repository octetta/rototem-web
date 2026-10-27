import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute.{attribute, class, selected, styles, type_, value}
import lustre/element.{type Element, text}
import lustre/element/html.{
  button, div, h1, h2, header, input, label, option, p, pre, select,
  span,
}
import lustre/event
import rototem/types.{
  type AudioFile, type ConsoleLog, type Model, type Msg, type Theme, type Track,
  Dark, Floating, Grid, Light, Minimized, Normal,
}

// ---------------------------------------------------------------------------
// Decoders for Mouse Dragging & Keys
// ---------------------------------------------------------------------------

fn mouse_down_drag_decoder(
  track_id: Int,
  card_x: Float,
  card_y: Float,
) -> decode.Decoder(Msg) {
  use cx <- decode.field("clientX", decode.float)
  use cy <- decode.field("clientY", decode.float)
  decode.success(types.StartDragCard(track_id, card_x, card_y, cx, cy))
}

fn mouse_move_decoder() -> decode.Decoder(Msg) {
  use cx <- decode.field("clientX", decode.float)
  use cy <- decode.field("clientY", decode.float)
  decode.success(types.DragCard(cx, cy))
}

fn mouse_down_drag_console_decoder() -> decode.Decoder(Msg) {
  use cx <- decode.field("clientX", decode.float)
  use cy <- decode.field("clientY", decode.float)
  decode.success(types.StartDragConsole(cx, cy))
}

fn mouse_move_console_decoder() -> decode.Decoder(Msg) {
  use cx <- decode.field("clientX", decode.float)
  use cy <- decode.field("clientY", decode.float)
  decode.success(types.DragConsole(cx, cy))
}

fn key_down_console_decoder() -> decode.Decoder(Msg) {
  use key <- decode.field("key", decode.string)
  case key {
    "Enter" -> decode.success(types.SubmitConsoleCommand)
    "ArrowUp" -> decode.success(types.ConsoleHistoryUp)
    "ArrowDown" -> decode.success(types.ConsoleHistoryDown)
    _ -> decode.failure(types.SubmitConsoleCommand, "Not handled")
  }
}

fn parse_float_input(val_str: String, fallback: Float) -> Float {
  case float.parse(val_str) {
    Ok(v) -> v
    Error(_) ->
      case int.parse(val_str) {
        Ok(i) -> int.to_float(i)
        Error(_) -> fallback
      }
  }
}

pub fn format_db(vol: Float) -> String {
  let rounded = float.round(vol *. 10.0)
  let int_part = rounded / 10
  let dec_part = int.absolute_value(rounded % 10)
  case rounded < 0 {
    True -> {
      let prefix = case int_part == 0 {
        True -> "-"
        False -> ""
      }
      prefix <> int.to_string(int_part) <> "." <> int.to_string(dec_part) <> " dB"
    }
    False -> {
      case rounded > 0 {
        True -> "+" <> int.to_string(int_part) <> "." <> int.to_string(dec_part) <> " dB"
        False -> "0.0 dB"
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Theme Palette
// ---------------------------------------------------------------------------

pub type ThemePalette {
  ThemePalette(
    bg_app: String,
    bg_surface: String,
    bg_subtle: String,
    bg_card: String,
    bg_card_header: String,
    border: String,
    text_main: String,
    text_muted: String,
    text_bright: String,
    input_bg: String,
  )
}

pub fn get_palette(theme: Theme) -> ThemePalette {
  case theme {
    Dark ->
      ThemePalette(
        bg_app: "#0d1117",
        bg_surface: "#161b22",
        bg_subtle: "#21262d",
        bg_card: "#161b22",
        bg_card_header: "#21262d",
        border: "#30363d",
        text_main: "#c9d1d9",
        text_muted: "#8b949e",
        text_bright: "#f0f6fc",
        input_bg: "#0d1117",
      )
    Light ->
      ThemePalette(
        bg_app: "#f0f2f5",
        bg_surface: "#ffffff",
        bg_subtle: "#e4e7eb",
        bg_card: "#ffffff",
        bg_card_header: "#f6f8fa",
        border: "#d0d7de",
        text_main: "#1f2328",
        text_muted: "#57606a",
        text_bright: "#0969da",
        input_bg: "#ffffff",
      )
  }
}

// ---------------------------------------------------------------------------
// Main View
// ---------------------------------------------------------------------------

pub fn view(model: Model) -> Element(Msg) {
  let palette = get_palette(model.theme)
  let is_card_dragging = option.is_some(model.active_drag)
  let is_console_dragging = model.console_dragging

  let container_attrs = [
    class("rototem-app"),
    styles([
      #("display", "flex"),
      #("flex-direction", "column"),
      #("height", "100vh"),
      #("background", palette.bg_app),
      #("color", palette.text_main),
      #("font-family", "system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif"),
      #("overflow", "hidden"),
      #("user-select", case is_card_dragging || is_console_dragging {
        True -> "none"
        False -> "auto"
      }),
    ]),
  ]

  let drag_attrs = case is_card_dragging {
    True -> [
      event.on("mousemove", mouse_move_decoder()),
      event.on("mouseup", decode.success(types.EndDragCard)),
    ]
    False ->
      case is_console_dragging {
        True -> [
          event.on("mousemove", mouse_move_console_decoder()),
          event.on("mouseup", decode.success(types.EndDragConsole)),
        ]
        False -> []
      }
  }

  div(list.append(container_attrs, drag_attrs), [
    view_master_bar(model, palette),
    view_status_banner(model.status_message, palette),
    view_mobile_track_tabs(model, palette),
    div(
      [
        class("workspace-area"),
        styles([
          #("position", "relative"),
          #("flex", "1"),
          #("overflow-y", "auto"),
          #("padding", "0.75rem"),
        ]),
      ],
      [
        // 1. Grid of docked cards
        view_card_grid(model.tracks, model.library, model.mobile_active_track, palette),
        // 2. Floating overlay of popped-out cards
        view_floating_layer(model.tracks, model.library, palette),
      ],
    ),
    case model.show_console {
      True -> view_console_drawer(model, palette)
      False -> element.none()
    },
    case model.show_library_modal {
      True -> view_library_modal(model.library, palette)
      False -> element.none()
    },
  ])
}

// ---------------------------------------------------------------------------
// Mobile Track Tabs (Shows 1 track at a time on small screens for zero clutter)
// ---------------------------------------------------------------------------

fn view_mobile_track_tabs(model: Model, palette: ThemePalette) -> Element(Msg) {
  div(
    [
      class("mobile-tabs-bar"),
      styles([
        #("display", "none"),
        #("background", palette.bg_surface),
        #("border-bottom", "1px solid " <> palette.border),
        #("padding", "0.4rem 0.5rem"),
        #("gap", "0.3rem"),
        #("overflow-x", "auto"),
      ]),
    ],
    list.map(model.tracks, fn(t) {
      let is_active = t.id == model.mobile_active_track
      button(
        [
          event.on_click(types.SetMobileActiveTrack(t.id)),
          styles([
            #("background", case is_active {
              True -> t.color
              False -> palette.bg_subtle
            }),
            #("color", case is_active {
              True -> "#000000"
              False -> palette.text_main
            }),
            #("border", "none"),
            #("border-radius", "4px"),
            #("padding", "0.4rem 0.6rem"),
            #("font-size", "0.75rem"),
            #("font-weight", "700"),
            #("cursor", "pointer"),
            #("white-space", "nowrap"),
          ]),
        ],
        [text("T" <> int.to_string(t.id + 1))],
      )
    }),
  )
}

// ---------------------------------------------------------------------------
// Master Toolbar
// ---------------------------------------------------------------------------

fn view_master_bar(model: Model, palette: ThemePalette) -> Element(Msg) {
  let is_any_playing =
    model.all_playing || list.any(model.tracks, fn(t) { t.playing })

  header(
    [
      class("master-bar"),
      styles([
        #("display", "flex"),
        #("align-items", "center"),
        #("gap", "0.5rem"),
        #("padding", "0.5rem 0.8rem"),
        #("background", palette.bg_surface),
        #("border-bottom", "1px solid " <> palette.border),
        #("flex-wrap", "wrap"),
      ]),
    ],
    [
      // Brand Title
      div(
        [
          styles([
            #("display", "flex"),
            #("align-items", "center"),
            #("gap", "0.4rem"),
            #("margin-right", "0.4rem"),
          ]),
        ],
        [
          h1(
            [
              styles([
                #("margin", "0"),
                #("font-size", "1.1rem"),
                #("font-weight", "800"),
                #("letter-spacing", "0.05em"),
                #("color", "#58a6ff"),
              ]),
            ],
            [text("ROTOTEM")],
          ),
          span(
            [
              styles([
                #("font-size", "0.65rem"),
                #("background", palette.bg_subtle),
                #("padding", "0.15rem 0.35rem"),
                #("border-radius", "4px"),
                #("color", palette.text_muted),
                #("border", "1px solid " <> palette.border),
              ]),
            ],
            [text("Skred Web")],
          ),
        ],
      ),
      // Directory Picker Button
      button(
        [
          class("btn btn-primary"),
          event.on_click(types.PickDirectory),
          styles([
            #("background", "#238636"),
            #("color", "#ffffff"),
            #("border", "none"),
            #("border-radius", "5px"),
            #("padding", "0.35rem 0.65rem"),
            #("font-size", "0.8rem"),
            #("font-weight", "600"),
            #("cursor", "pointer"),
          ]),
        ],
        [text("📂 Folder")],
      ),
      // Start / Stop All Voices Unified Button
      button(
        [
          class("btn"),
          event.on_click(types.ToggleAllPlay),
          styles([
            #(
              "background",
              case is_any_playing {
                True -> "#da3633"
                False -> "#238636"
              },
            ),
            #("color", "#ffffff"),
            #("border", "none"),
            #("border-radius", "5px"),
            #("padding", "0.35rem 0.65rem"),
            #("font-size", "0.8rem"),
            #("font-weight", "600"),
            #("cursor", "pointer"),
          ]),
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
          styles([
            #("background", palette.bg_subtle),
            #("color", palette.text_main),
            #("border", "1px solid " <> palette.border),
            #("border-radius", "5px"),
            #("padding", "0.35rem 0.6rem"),
            #("font-size", "0.8rem"),
            #("cursor", "pointer"),
          ]),
        ],
        [text("🎲 Random All")],
      ),
      // Theme Toggle Button (Light / Dark)
      button(
        [
          class("btn btn-secondary"),
          event.on_click(types.ToggleTheme),
          styles([
            #("background", palette.bg_subtle),
            #("color", palette.text_main),
            #("border", "1px solid " <> palette.border),
            #("border-radius", "5px"),
            #("padding", "0.35rem 0.6rem"),
            #("font-size", "0.8rem"),
            #("cursor", "pointer"),
            #("display", "flex"),
            #("align-items", "center"),
            #("gap", "0.3rem"),
          ]),
        ],
        [
          text(case model.theme {
            Dark -> "☀️ Light"
            Light -> "🌙 Dark"
          }),
        ],
      ),
      // Master Volume Slider
      div(
        [
          styles([
            #("display", "flex"),
            #("align-items", "center"),
            #("gap", "0.45rem"),
            #("background", palette.bg_subtle),
            #("padding", "0.25rem 0.65rem"),
            #("border-radius", "5px"),
            #("border", "1px solid " <> palette.border),
          ]),
        ],
        [
          label(
            [
              styles([
                #("font-size", "0.75rem"),
                #("font-weight", "600"),
                #("color", palette.text_main),
              ]),
            ],
            [text("Master:")],
          ),
          input([
            type_("range"),
            attribute("min", "-60"),
            attribute("max", "12"),
            attribute("step", "0.5"),
            attribute(
              "title",
              "Master Volume: " <> format_db(model.master_volume),
            ),
            value(float.to_string(model.master_volume)),
            event.on_input(fn(v) {
              types.SetMasterVolume(parse_float_input(v, model.master_volume))
            }),
            styles([#("width", "130px"), #("cursor", "pointer")]),
          ]),
          span(
            [
              styles([
                #("font-size", "0.7rem"),
                #("min-width", "52px"),
                #("text-align", "right"),
                #("color", palette.text_muted),
              ]),
            ],
            [text(format_db(model.master_volume))],
          ),
        ],
      ),
      // Audio Output Device Chooser
      div(
        [
          styles([
            #("display", "flex"),
            #("align-items", "center"),
            #("gap", "0.35rem"),
          ]),
        ],
        [
          select(
            [
              value(model.selected_device_id),
              event.on_change(types.SelectOutputDevice),
              event.on_input(types.SelectOutputDevice),
              styles([
                #("background", palette.bg_subtle),
                #("color", palette.text_main),
                #("border", "1px solid " <> palette.border),
                #("border-radius", "5px"),
                #("padding", "0.3rem 0.45rem"),
                #("font-size", "0.75rem"),
                #("max-width", "130px"),
              ]),
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
        ],
      ),
      // Master Record Button
      button(
        [
          class("btn"),
          event.on_click(types.ToggleRecord),
          styles([
            #(
              "background",
              case model.recording {
                True -> "#da3633"
                False -> palette.bg_subtle
              },
            ),
            #(
              "color",
              case model.recording {
                True -> "#ffffff"
                False -> "#f85149"
              },
            ),
            #("border", "1px solid " <> palette.border),
            #("border-radius", "5px"),
            #("padding", "0.35rem 0.65rem"),
            #("font-size", "0.8rem"),
            #("font-weight", "600"),
            #("cursor", "pointer"),
            #("display", "flex"),
            #("align-items", "center"),
            #("gap", "0.3rem"),
          ]),
        ],
        [
          span(
            [
              styles([
                #("width", "7px"),
                #("height", "7px"),
                #("border-radius", "50%"),
                #(
                  "background",
                  case model.recording {
                    True -> "#ffffff"
                    False -> "#f85149"
                  },
                ),
              ]),
            ],
            [],
          ),
          text(case model.recording {
            True -> "Stop Rec"
            False -> "Record"
          }),
        ],
      ),
      // Console Toggle Button (Ctrl-~)
      button(
        [
          class("btn btn-secondary"),
          event.on_click(types.ToggleConsole),
          styles([
            #(
              "background",
              case model.show_console {
                True -> "#388bfd33"
                False -> palette.bg_subtle
              },
            ),
            #(
              "color",
              case model.show_console {
                True -> "#58a6ff"
                False -> palette.text_main
              },
            ),
            #("border", "1px solid " <> palette.border),
            #("border-radius", "5px"),
            #("padding", "0.35rem 0.6rem"),
            #("font-size", "0.8rem"),
            #("font-weight", "600"),
            #("cursor", "pointer"),
            #("margin-left", "auto"),
          ]),
        ],
        [text("Console (~)")],
      ),
      // Library Summary Toggle Button
      button(
        [
          class("btn btn-secondary"),
          event.on_click(types.ToggleLibraryModal),
          styles([
            #("background", palette.bg_subtle),
            #("color", palette.text_muted),
            #("border", "1px solid " <> palette.border),
            #("border-radius", "5px"),
            #("padding", "0.35rem 0.55rem"),
            #("font-size", "0.8rem"),
            #("cursor", "pointer"),
          ]),
        ],
        [text("Files (" <> int.to_string(list.length(model.library)) <> ")")],
      ),
    ],
  )
}

// ---------------------------------------------------------------------------
// Status Banner
// ---------------------------------------------------------------------------

fn view_status_banner(msg: String, palette: ThemePalette) -> Element(Msg) {
  case msg {
    "" -> element.none()
    _ ->
      div(
        [
          class("status-banner"),
          styles([
            #("background", palette.bg_surface),
            #("color", "#58a6ff"),
            #("padding", "0.2rem 0.8rem"),
            #("font-size", "0.72rem"),
            #("border-bottom", "1px solid " <> palette.border),
            #("display", "flex"),
            #("align-items", "center"),
            #("gap", "0.4rem"),
          ]),
        ],
        [
          span([styles([#("color", "#3fb950")])], [text("●")]),
          text(msg),
        ],
      )
  }
}

// ---------------------------------------------------------------------------
// Grid Workspace of Docked Cards
// ---------------------------------------------------------------------------

fn view_card_grid(
  tracks: List(Track),
  library: List(AudioFile),
  _mobile_active_track: Int,
  palette: ThemePalette,
) -> Element(Msg) {
  let docked_tracks =
    list.filter(tracks, fn(t) {
      case t.card_mode {
        Grid -> True
        Floating(_, _, _) -> False
      }
    })

  div(
    [
      class("tracks-grid"),
      styles([
        #("display", "grid"),
        #("grid-template-columns", "repeat(auto-fill, minmax(290px, 1fr))"),
        #("gap", "0.75rem"),
        #("width", "100%"),
      ]),
    ],
    list.map(docked_tracks, fn(track) { view_track_card(track, library, palette) }),
  )
}

// ---------------------------------------------------------------------------
// Floating Layer of Popped-out Cards
// ---------------------------------------------------------------------------

fn view_floating_layer(
  tracks: List(Track),
  library: List(AudioFile),
  palette: ThemePalette,
) -> Element(Msg) {
  let floating_tracks =
    list.filter(tracks, fn(t) {
      case t.card_mode {
        Floating(_, _, _) -> True
        Grid -> False
      }
    })

  div(
    [
      class("floating-layer"),
      styles([
        #("position", "absolute"),
        #("top", "0"),
        #("left", "0"),
        #("right", "0"),
        #("bottom", "0"),
        #("pointer-events", "none"),
      ]),
    ],
    list.map(floating_tracks, fn(track) { view_track_card(track, library, palette) }),
  )
}

// ---------------------------------------------------------------------------
// Single Track Card Component
// ---------------------------------------------------------------------------

fn view_track_card(
  track: Track,
  library: List(AudioFile),
  palette: ThemePalette,
) -> Element(Msg) {
  let is_minimized = case track.card_display {
    Minimized -> True
    Normal -> False
  }

  let card_style = case track.card_mode {
    Grid -> [
      #("background", palette.bg_card),
      #("border", "1px solid " <> palette.border),
      #("border-top", "3px solid " <> track.color),
      #("border-radius", "6px"),
      #("display", "flex"),
      #("flex-direction", "column"),
      #(
        "box-shadow",
        case palette.bg_card {
          "#ffffff" -> "0 2px 8px rgba(0,0,0,0.08)"
          _ -> "0 2px 8px rgba(0,0,0,0.3)"
        },
      ),
    ]
    Floating(x, y, z) -> [
      #("position", "absolute"),
      #("left", float.to_string(x) <> "px"),
      #("top", float.to_string(y) <> "px"),
      #("width", "310px"),
      #("z-index", int.to_string(z)),
      #("background", palette.bg_card),
      #("border", "1px solid #58a6ff"),
      #("border-top", "4px solid " <> track.color),
      #("border-radius", "6px"),
      #("display", "flex"),
      #("flex-direction", "column"),
      #(
        "box-shadow",
        case palette.bg_card {
          "#ffffff" -> "0 8px 24px rgba(0,0,0,0.15)"
          _ -> "0 8px 24px rgba(0,0,0,0.6)"
        },
      ),
      #("pointer-events", "auto"),
    ]
  }

  div([class("track-card"), styles(card_style)], [
    view_card_header(track, palette),
    case is_minimized {
      True -> view_card_minimized_body(track, palette)
      False -> view_card_expanded_body(track, library, palette)
    },
  ])
}

// ---------------------------------------------------------------------------
// Track Card Header (with Drag Handle and Window Controls)
// ---------------------------------------------------------------------------

fn view_card_header(track: Track, palette: ThemePalette) -> Element(Msg) {
  let #(is_floating, fx, fy) = case track.card_mode {
    Grid -> #(False, 100.0, 100.0)
    Floating(x, y, _) -> #(True, x, y)
  }

  let is_minimized = case track.card_display {
    Minimized -> True
    Normal -> False
  }

  let header_drag_attrs = case is_floating {
    True -> [
      event.on("mousedown", mouse_down_drag_decoder(track.id, fx, fy)),
      styles([#("cursor", "grab")]),
    ]
    False -> []
  }

  let base_header_style = [
    #("display", "flex"),
    #("align-items", "center"),
    #("justify-content", "space-between"),
    #("padding", "0.4rem 0.65rem"),
    #("background", palette.bg_card_header),
    #("border-bottom", "1px solid " <> palette.border),
    #("border-top-left-radius", "5px"),
    #("border-top-right-radius", "5px"),
  ]

  div(
    list.append(
      [class("card-header"), styles(base_header_style)],
      header_drag_attrs,
    ),
    [
      div(
        [
          styles([
            #("display", "flex"),
            #("align-items", "center"),
            #("gap", "0.4rem"),
          ]),
        ],
        [
          span(
            [
              styles([
                #("font-weight", "800"),
                #("font-size", "0.82rem"),
                #("color", track.color),
              ]),
            ],
            [text("Track " <> int.to_string(track.id + 1))],
          ),
          span(
            [styles([#("font-size", "0.68rem"), #("color", palette.text_muted)])],
            [
              text(
                "v"
                <> int.to_string(track.left_voice)
                <> "/v"
                <> int.to_string(track.right_voice),
              ),
            ],
          ),
        ],
      ),
      div(
        [
          styles([
            #("display", "flex"),
            #("align-items", "center"),
            #("gap", "0.3rem"),
          ]),
        ],
        [
          // Float / Dock Toggle Button
          button(
            [
              class("card-action-btn"),
              event.on_click(case is_floating {
                True -> types.DockTrackCard(track.id)
                False -> types.FloatTrackCard(track.id)
              }),
              styles([
                #("background", "transparent"),
                #("border", "1px solid " <> palette.border),
                #("border-radius", "3px"),
                #("color", palette.text_main),
                #("padding", "0.15rem 0.35rem"),
                #("font-size", "0.68rem"),
                #("cursor", "pointer"),
              ]),
            ],
            [
              text(case is_floating {
                True -> "↙ Dock"
                False -> "↗ Float"
              }),
            ],
          ),
          // Minimize / Restore Toggle Button
          button(
            [
              class("card-action-btn"),
              event.on_click(types.ToggleTrackMinimize(track.id)),
              styles([
                #("background", "transparent"),
                #("border", "1px solid " <> palette.border),
                #("border-radius", "3px"),
                #("color", palette.text_main),
                #("padding", "0.15rem 0.35rem"),
                #("font-size", "0.68rem"),
                #("cursor", "pointer"),
              ]),
            ],
            [
              text(case is_minimized {
                True -> "□"
                False -> "_"
              }),
            ],
          ),
        ],
      ),
    ],
  )
}

// ---------------------------------------------------------------------------
// Minimized Card Body
// ---------------------------------------------------------------------------

fn view_card_minimized_body(
  track: Track,
  palette: ThemePalette,
) -> Element(Msg) {
  let sample_label = case track.audio_file {
    Some(f) -> f.name
    None -> ""
  }

  div(
    [
      class("card-minimized-body"),
      styles([
        #("display", "flex"),
        #("align-items", "center"),
        #("justify-content", "space-between"),
        #("padding", "0.35rem 0.65rem"),
        #("font-size", "0.75rem"),
      ]),
    ],
    [
      span(
        [
          styles([
            #("color", palette.text_muted),
            #("white-space", "nowrap"),
            #("overflow", "hidden"),
            #("text-overflow", "ellipsis"),
            #("max-width", "150px"),
          ]),
        ],
        [text(sample_label)],
      ),
      div([styles([#("display", "flex"), #("gap", "0.25rem")])], [
        button(
          [
            event.on_click(types.ToggleTrackPlay(track.id)),
            styles([
              #(
                "background",
                case track.playing {
                  True -> "#da3633"
                  False -> "#238636"
                },
              ),
              #("color", "#ffffff"),
              #("border", "none"),
              #("border-radius", "3px"),
              #("padding", "0.15rem 0.4rem"),
              #("font-size", "0.72rem"),
              #("cursor", "pointer"),
            ]),
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
            event.on_click(types.ToggleTrackMute(track.id)),
            styles([
              #(
                "background",
                case track.muted {
                  True -> "#da3633"
                  False -> palette.bg_subtle
                },
              ),
              #(
                "color",
                case track.muted {
                  True -> "#ffffff"
                  False -> palette.text_main
                },
              ),
              #("border", "1px solid " <> palette.border),
              #("border-radius", "3px"),
              #("padding", "0.15rem 0.4rem"),
              #("font-size", "0.72rem"),
              #("cursor", "pointer"),
            ]),
          ],
          [
            text(case track.muted {
              True -> "🔇"
              False -> "🔊"
            }),
          ],
        ),
      ]),
    ],
  )
}

// ---------------------------------------------------------------------------
// Expanded Full Card Body
// ---------------------------------------------------------------------------

fn format_pitch(speed: Float) -> String {
  let rounded = float.round(speed *. 10.0)
  let int_part = rounded / 10
  let dec_part = int.absolute_value(rounded % 10)
  int.to_string(int_part) <> "." <> int.to_string(dec_part)
}

fn view_card_expanded_body(
  track: Track,
  library: List(AudioFile),
  palette: ThemePalette,
) -> Element(Msg) {
  let selected_file_id = case track.audio_file {
    Some(f) -> f.id
    None -> ""
  }

  div(
    [
      class("card-body"),
      styles([
        #("display", "flex"),
        #("flex-direction", "column"),
        #("gap", "0.5rem"),
        #("padding", "0.65rem"),
      ]),
    ],
    [
      // Sample Selection Row
      div(
        [
          styles([
            #("display", "flex"),
            #("align-items", "center"),
            #("gap", "0.35rem"),
          ]),
        ],
        [
          select(
            [
              value(selected_file_id),
              event.on_change(fn(fid) { types.SelectTrackSample(track.id, fid) }),
              event.on_input(fn(fid) { types.SelectTrackSample(track.id, fid) }),
              styles([
                #("flex", "1"),
                #("background", palette.input_bg),
                #("color", palette.text_main),
                #("border", "1px solid " <> palette.border),
                #("border-radius", "4px"),
                #("padding", "0.25rem 0.35rem"),
                #("font-size", "0.75rem"),
              ]),
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
              event.on_click(types.RandomTrackSample(track.id)),
              styles([
                #("background", palette.bg_subtle),
                #("color", palette.text_main),
                #("border", "1px solid " <> palette.border),
                #("border-radius", "4px"),
                #("padding", "0.25rem 0.45rem"),
                #("font-size", "0.75rem"),
                #("cursor", "pointer"),
              ]),
            ],
            [text("🎲")],
          ),
        ],
      ),
      // Transport & Mute & Direction Controls
      div(
        [
          styles([
            #("display", "flex"),
            #("align-items", "center"),
            #("gap", "0.35rem"),
          ]),
        ],
        [
          // Play / Stop button
          button(
            [
              event.on_click(types.ToggleTrackPlay(track.id)),
              styles([
                #("flex", "1"),
                #(
                  "background",
                  case track.playing {
                    True -> "#da3633"
                    False -> "#238636"
                  },
                ),
                #("color", "#ffffff"),
                #("border", "none"),
                #("border-radius", "4px"),
                #("padding", "0.35rem 0.4rem"),
                #("font-size", "0.78rem"),
                #("font-weight", "700"),
                #("cursor", "pointer"),
              ]),
            ],
            [
              text(case track.playing {
                True -> "⏹ Stop"
                False -> "▶ Play"
              }),
            ],
          ),
          // Mute Toggle Button
          button(
            [
              event.on_click(types.ToggleTrackMute(track.id)),
              styles([
                #("flex", "1"),
                #(
                  "background",
                  case track.muted {
                    True -> "#da3633"
                    False -> palette.bg_subtle
                  },
                ),
                #(
                  "color",
                  case track.muted {
                    True -> "#ffffff"
                    False -> palette.text_main
                  },
                ),
                #("border", "1px solid " <> palette.border),
                #("border-radius", "4px"),
                #("padding", "0.35rem 0.4rem"),
                #("font-size", "0.78rem"),
                #("cursor", "pointer"),
              ]),
            ],
            [
              text(case track.muted {
                True -> "🔇 Muted"
                False -> "🔊 Mute"
              }),
            ],
          ),
          // Direction Flip Button
          button(
            [
              event.on_click(types.ToggleTrackDirection(track.id)),
              styles([
                #("flex", "1"),
                #(
                  "background",
                  case track.reversed {
                    True -> "#8957e5"
                    False -> palette.bg_subtle
                  },
                ),
                #(
                  "color",
                  case track.reversed {
                    True -> "#ffffff"
                    False -> palette.text_main
                  },
                ),
                #("border", "1px solid " <> palette.border),
                #("border-radius", "4px"),
                #("padding", "0.35rem 0.4rem"),
                #("font-size", "0.75rem"),
                #("cursor", "pointer"),
              ]),
            ],
            [
              text(case track.reversed {
                True -> "⇄ Rev"
                False -> "⇄ Fwd"
              }),
            ],
          ),
        ],
      ),
      // Volume Slider
      div(
        [
          styles([
            #("display", "flex"),
            #("align-items", "center"),
            #("gap", "0.5rem"),
            #("background", palette.input_bg),
            #("border", "1px solid " <> palette.border),
            #("padding", "0.25rem 0.5rem"),
            #("border-radius", "4px"),
          ]),
        ],
        [
          span(
            [
              attribute("title", "Volume"),
              styles([
                #("font-size", "0.85rem"),
                #("user-select", "none"),
                #("line-height", "1"),
              ]),
            ],
            [text("🔊")],
          ),
          input([
            type_("range"),
            attribute("min", "-60"),
            attribute("max", "12"),
            attribute("step", "0.1"),
            attribute(
              "title",
              "Volume: " <> format_db(track.volume),
            ),
            value(float.to_string(track.volume)),
            event.on_input(fn(v) {
              types.SetTrackVolume(track.id, parse_float_input(v, track.volume))
            }),
            styles([
              #("flex", "1"),
              #("width", "100%"),
              #("cursor", "pointer"),
            ]),
          ]),
        ],
      ),
      // Speed / Pitch Slider (MIDI notes 21 to 108, centered at 69)
      div(
        [
          styles([
            #("display", "flex"),
            #("align-items", "center"),
            #("gap", "0.5rem"),
            #("background", palette.input_bg),
            #("border", "1px solid " <> palette.border),
            #("padding", "0.25rem 0.5rem"),
            #("border-radius", "4px"),
          ]),
        ],
        [
          span(
            [
              attribute("title", "Pitch"),
              styles([
                #("font-size", "0.85rem"),
                #("user-select", "none"),
                #("line-height", "1"),
              ]),
            ],
            [text("🎵")],
          ),
          input([
            type_("range"),
            attribute("min", "0"),
            attribute("max", "127"),
            attribute("step", "0.1"),
            attribute(
              "title",
              "Pitch: n" <> format_pitch(track.speed),
            ),
            value(float.to_string(track.speed)),
            event.on_input(fn(v) {
              types.SetTrackSpeed(track.id, parse_float_input(v, track.speed))
            }),
            styles([
              #("flex", "1"),
              #("width", "100%"),
              #("cursor", "pointer"),
            ]),
          ]),
        ],
      ),
      // Quick Pitch Buttons: ½× (-12), -1, 1× (69), +1, 2× (+12)
      div(
        [
          styles([
            #("display", "grid"),
            #("grid-template-columns", "repeat(5, 1fr)"),
            #("gap", "0.25rem"),
          ]),
        ],
        [
          quick_pitch_btn(track.id, "½×", -12.0, palette),
          quick_pitch_btn(track.id, "-1", -1.0, palette),
          button(
            [
              event.on_click(types.StepTrackSpeed(track.id, 0.0)),
              styles([
                #("background", palette.bg_subtle),
                #("color", "#58a6ff"),
                #("border", "1px solid " <> palette.border),
                #("border-radius", "4px"),
                #("padding", "0.25rem 0.1rem"),
                #("font-size", "0.72rem"),
                #("font-weight", "700"),
                #("cursor", "pointer"),
                #("text-align", "center"),
              ]),
            ],
            [text("1×")],
          ),
          quick_pitch_btn(track.id, "+1", 1.0, palette),
          quick_pitch_btn(track.id, "2×", 12.0, palette),
        ],
      ),
      // Status Info Line: Volume (left), Pitch (right)
      div(
        [
          class("track-status-line"),
          styles([
            #("display", "flex"),
            #("align-items", "center"),
            #("justify-content", "space-between"),
            #("font-size", "0.68rem"),
            #("color", palette.text_muted),
            #("padding", "0.1rem 0.15rem"),
          ]),
        ],
        [
          span(
            [styles([#("color", palette.text_main), #("font-weight", "600")])],
            [text("Vol: " <> format_db(track.volume))],
          ),
          span(
            [],
            [
              text("Pitch: "),
              span(
                [styles([#("color", "#58a6ff"), #("font-weight", "600")])],
                [text("n" <> format_pitch(track.speed))],
              ),
            ],
          ),
        ],
      ),
    ],
  )
}

fn quick_pitch_btn(
  track_id: Int,
  label_text: String,
  offset: Float,
  palette: ThemePalette,
) -> Element(Msg) {
  button(
    [
      event.on_click(types.StepTrackSpeed(track_id, offset)),
      styles([
        #("background", palette.bg_subtle),
        #("color", palette.text_main),
        #("border", "1px solid " <> palette.border),
        #("border-radius", "4px"),
        #("padding", "0.25rem 0.1rem"),
        #("font-size", "0.72rem"),
        #("cursor", "pointer"),
        #("text-align", "center"),
      ]),
    ],
    [text(label_text)],
  )
}

// ---------------------------------------------------------------------------
// Skred Ctrl-~ Console REPL Window (Floating & Resizable)
// ---------------------------------------------------------------------------

fn view_console_drawer(model: Model, palette: ThemePalette) -> Element(Msg) {
  let left_px = float.to_string(model.console_x) <> "px"
  let top_px = float.to_string(model.console_y) <> "px"
  let width_px = float.to_string(model.console_width) <> "px"
  let height_px = float.to_string(model.console_height) <> "px"

  div(
    [
      class("console-window"),
      styles([
        #("position", "fixed"),
        #("left", left_px),
        #("top", top_px),
        #("width", width_px),
        #("height", height_px),
        #("min-width", "340px"),
        #("min-height", "220px"),
        #("resize", "both"),
        #("overflow", "hidden"),
        #("background", palette.bg_card),
        #("border", "1px solid " <> palette.border),
        #("border-radius", "6px"),
        #(
          "box-shadow",
          case palette.bg_card {
            "#ffffff" -> "0 14px 40px rgba(0, 0, 0, 0.2)"
            _ -> "0 14px 40px rgba(0, 0, 0, 0.85)"
          },
        ),
        #("display", "flex"),
        #("flex-direction", "column"),
        #("z-index", "10000"),
      ]),
    ],
    [
      // Console Header Bar (Drag Handle)
      div(
        [
          class("console-title-bar"),
          event.on("mousedown", mouse_down_drag_console_decoder()),
          styles([
            #("display", "flex"),
            #("justify-content", "space-between"),
            #("align-items", "center"),
            #("padding", "0.4rem 0.75rem"),
            #("background", palette.bg_card_header),
            #("border-bottom", "1px solid " <> palette.border),
            #("cursor", case model.console_dragging {
              True -> "grabbing"
              False -> "grab"
            }),
            #("user-select", "none"),
          ]),
        ],
        [
          div(
            [
              styles([
                #("display", "flex"),
                #("align-items", "center"),
                #("gap", "0.5rem"),
              ]),
            ],
            [
              span(
                [
                  styles([
                    #("font-size", "0.85rem"),
                    #("font-weight", "800"),
                    #("color", "#58a6ff"),
                    #("letter-spacing", "0.05em"),
                  ]),
                ],
                [text("SKRED CONSOLE")],
              ),
              span(
                [styles([#("font-size", "0.68rem"), #("color", palette.text_muted)])],
                [text("drag to move • resize corner • Ctrl-~ or Esc")],
              ),
            ],
          ),
          div(
            [
              styles([
                #("display", "flex"),
                #("align-items", "center"),
                #("gap", "0.4rem"),
              ]),
            ],
            [
              button(
                [
                  event.on_click(types.ResetConsolePosition),
                  styles([
                    #("background", palette.bg_subtle),
                    #("color", palette.text_muted),
                    #("border", "1px solid " <> palette.border),
                    #("border-radius", "4px"),
                    #("padding", "0.15rem 0.4rem"),
                    #("font-size", "0.7rem"),
                    #("cursor", "pointer"),
                  ]),
                ],
                [text("⟲ Pos")],
              ),
              button(
                [
                  event.on_click(types.ClearConsole),
                  styles([
                    #("background", palette.bg_subtle),
                    #("color", palette.text_muted),
                    #("border", "1px solid " <> palette.border),
                    #("border-radius", "4px"),
                    #("padding", "0.15rem 0.4rem"),
                    #("font-size", "0.7rem"),
                    #("cursor", "pointer"),
                  ]),
                ],
                [text("Clear")],
              ),
              button(
                [
                  event.on_click(types.ToggleConsole),
                  styles([
                    #("background", "transparent"),
                    #("color", palette.text_main),
                    #("border", "none"),
                    #("font-size", "1rem"),
                    #("cursor", "pointer"),
                    #("padding", "0 0.4rem"),
                  ]),
                ],
                [text("✕")],
              ),
            ],
          ),
        ],
      ),
      // Quick diagnostic button toolbar
      div(
        [
          styles([
            #("display", "flex"),
            #("align-items", "center"),
            #("gap", "0.3rem"),
            #("padding", "0.3rem 0.75rem"),
            #("background", palette.bg_subtle),
            #("border-bottom", "1px solid " <> palette.border),
            #("overflow-x", "auto"),
          ]),
        ],
        [
          span(
            [styles([#("font-size", "0.68rem"), #("color", palette.text_muted)])],
            [text("Quick Diagnostics:")],
          ),
          quick_cmd_btn("?a (Audio Status)", "?a", palette),
          quick_cmd_btn("?v (Voices)", "?v", palette),
          quick_cmd_btn("v0? (Voice 0)", "v0?", palette),
          quick_cmd_btn("/ws (Wavetables)", "/ws", palette),
          quick_cmd_btn("?q (Queue)", "?q", palette),
          quick_cmd_btn("?? (Full Status)", "??", palette),
          quick_cmd_btn("v0l1; v1l1 (V0-1 Run)", "v0l1; v1l1", palette),
          quick_cmd_btn("v0l0; v1l0 (V0-1 Stop)", "v0l0; v1l0", palette),
        ],
      ),
      // Console Log Output
      div(
        [
          class("console-log-area"),
          styles([
            #("flex", "1"),
            #("overflow-y", "auto"),
            #("padding", "0.5rem 0.75rem"),
            #("display", "flex"),
            #("flex-direction", "column"),
            #("gap", "0.4rem"),
            #("font-family", "'JetBrains Mono', 'Fira Code', monospace"),
            #("font-size", "0.75rem"),
            #("background", palette.input_bg),
          ]),
        ],
        list.map(model.console_logs, fn(log: ConsoleLog) {
          div(
            [
              styles([
                #("display", "flex"),
                #("flex-direction", "column"),
                #("background", palette.bg_surface),
                #("border", "1px solid " <> palette.border),
                #("border-radius", "4px"),
                #("padding", "0.35rem 0.5rem"),
              ]),
            ],
            [
              div(
                [
                  styles([
                    #("display", "flex"),
                    #("justify-content", "space-between"),
                    #("align-items", "center"),
                    #("margin-bottom", "0.2rem"),
                  ]),
                ],
                [
                  span(
                    [styles([#("color", "#58a6ff"), #("font-weight", "700")])],
                    [text("> " <> log.cmd)],
                  ),
                  span(
                    [
                      styles([
                        #(
                          "color",
                          case log.ret == 0 {
                            True -> "#3fb950"
                            False -> "#f85149"
                          },
                        ),
                        #("font-size", "0.68rem"),
                      ]),
                    ],
                    [text("ret: " <> int.to_string(log.ret))],
                  ),
                ],
              ),
              pre(
                [
                  styles([
                    #("margin", "0"),
                    #("color", palette.text_main),
                    #("white-space", "pre-wrap"),
                    #("word-break", "break-all"),
                  ]),
                ],
                [text(log.response)],
              ),
            ],
          )
        }),
      ),
      // Console Command Input Row
      div(
        [
          styles([
            #("display", "flex"),
            #("align-items", "center"),
            #("padding", "0.4rem 0.75rem"),
            #("background", palette.bg_surface),
            #("border-top", "1px solid " <> palette.border),
            #("gap", "0.4rem"),
          ]),
        ],
        [
          span(
            [styles([#("color", "#58a6ff"), #("font-weight", "800")])],
            [text("skred>")],
          ),
          input([
            type_("text"),
            class("console-input"),
            attribute("placeholder", "Type ASCII Skode command and press Enter (e.g. ?a, v0 w82 f440 a10)..."),
            value(model.console_input),
            event.on_input(types.SetConsoleInput),
            event.on("keydown", key_down_console_decoder()),
            styles([
              #("flex", "1"),
              #("background", palette.input_bg),
              #("color", palette.text_main),
              #("border", "1px solid " <> palette.border),
              #("border-radius", "4px"),
              #("padding", "0.4rem 0.5rem"),
              #("font-family", "monospace"),
              #("font-size", "0.8rem"),
              #("outline", "none"),
            ]),
          ]),
          button(
            [
              event.on_click(types.SubmitConsoleCommand),
              styles([
                #("background", "#1f6feb"),
                #("color", "#ffffff"),
                #("border", "none"),
                #("border-radius", "4px"),
                #("padding", "0.4rem 0.8rem"),
                #("font-size", "0.78rem"),
                #("font-weight", "700"),
                #("cursor", "pointer"),
              ]),
            ],
            [text("Send (Enter)")],
          ),
        ],
      ),
    ],
  )
}

fn quick_cmd_btn(
  label_str: String,
  cmd: String,
  palette: ThemePalette,
) -> Element(Msg) {
  button(
    [
      event.on_click(types.ConsoleResultReceived(cmd, 0, "")),
      event.on_click(types.SetConsoleInput(cmd)),
      styles([
        #("background", palette.bg_surface),
        #("color", "#58a6ff"),
        #("border", "1px solid " <> palette.border),
        #("border-radius", "3px"),
        #("padding", "0.15rem 0.35rem"),
        #("font-size", "0.68rem"),
        #("font-family", "monospace"),
        #("cursor", "pointer"),
        #("white-space", "nowrap"),
      ]),
    ],
    [text(label_str)],
  )
}

// ---------------------------------------------------------------------------
// Library Drawer / Modal
// ---------------------------------------------------------------------------

fn view_library_modal(
  library: List(AudioFile),
  palette: ThemePalette,
) -> Element(Msg) {
  div(
    [
      class("modal-backdrop"),
      styles([
        #("position", "fixed"),
        #("inset", "0"),
        #("background", "rgba(0, 0, 0, 0.75)"),
        #("display", "flex"),
        #("justify-content", "center"),
        #("align-items", "center"),
        #("z-index", "9999"),
      ]),
    ],
    [
      div(
        [
          class("modal-content"),
          styles([
            #("background", palette.bg_surface),
            #("border", "1px solid " <> palette.border),
            #("border-radius", "8px"),
            #("width", "500px"),
            #("max-width", "90vw"),
            #("max-height", "80vh"),
            #("display", "flex"),
            #("flex-direction", "column"),
            #("padding", "1rem"),
            #(
              "box-shadow",
              case palette.bg_surface {
                "#ffffff" -> "0 8px 32px rgba(0,0,0,0.2)"
                _ -> "0 8px 32px rgba(0,0,0,0.8)"
              },
            ),
          ]),
        ],
        [
          div(
            [
              styles([
                #("display", "flex"),
                #("justify-content", "space-between"),
                #("align-items", "center"),
                #("margin-bottom", "0.75rem"),
              ]),
            ],
            [
              div(
                [
                  styles([
                    #("display", "flex"),
                    #("align-items", "center"),
                    #("gap", "0.75rem"),
                  ]),
                ],
                [
                  h2(
                    [
                      styles([
                        #("margin", "0"),
                        #("font-size", "1.1rem"),
                        #("color", "#58a6ff"),
                      ]),
                    ],
                    [
                      text(
                        "Attached Audio Files ("
                        <> int.to_string(list.length(library))
                        <> ")",
                      ),
                    ],
                  ),
                  case list.is_empty(library) {
                    True -> element.none()
                    False ->
                      button(
                        [
                          event.on_click(types.ClearAudioLibrary),
                          styles([
                            #("background", "rgba(248, 81, 73, 0.15)"),
                            #("color", "#f85149"),
                            #("border", "1px solid rgba(248, 81, 73, 0.4)"),
                            #("border-radius", "4px"),
                            #("padding", "0.2rem 0.5rem"),
                            #("font-size", "0.75rem"),
                            #("cursor", "pointer"),
                          ]),
                        ],
                        [text("Clear All")],
                      )
                  },
                ],
              ),
              button(
                [
                  event.on_click(types.ToggleLibraryModal),
                  styles([
                    #("background", "transparent"),
                    #("border", "none"),
                    #("color", palette.text_muted),
                    #("font-size", "1.1rem"),
                    #("cursor", "pointer"),
                  ]),
                ],
                [text("✕")],
              ),
            ],
          ),
          div(
            [
              styles([
                #("flex", "1"),
                #("overflow-y", "auto"),
                #("display", "flex"),
                #("flex-direction", "column"),
                #("gap", "0.4rem"),
              ]),
            ],
            case library {
              [] -> [
                p(
                  [
                    styles([
                      #("color", palette.text_muted),
                      #("font-size", "0.85rem"),
                      #("text-align", "center"),
                      #("margin", "2rem 0"),
                    ]),
                  ],
                  [
                    text(
                      "No audio files loaded yet. Click 'Folder' to load .wav, .mp3, or .flac files.",
                    ),
                  ],
                ),
              ]
              _ ->
                list.map(library, fn(f) {
                  let size_kb = int.to_string(f.size / 1024) <> " KB"
                  div(
                    [
                      styles([
                        #("display", "flex"),
                        #("justify-content", "space-between"),
                        #("align-items", "center"),
                        #("background", palette.bg_subtle),
                        #("padding", "0.4rem 0.6rem"),
                        #("border-radius", "4px"),
                        #("font-size", "0.8rem"),
                        #("gap", "0.5rem"),
                      ]),
                    ],
                    [
                      span(
                        [
                          styles([
                            #("color", palette.text_main),
                            #("flex", "1"),
                            #("overflow", "hidden"),
                            #("text-overflow", "ellipsis"),
                            #("white-space", "nowrap"),
                          ]),
                        ],
                        [text(f.name)],
                      ),
                      span(
                        [
                          styles([
                            #("color", palette.text_muted),
                            #("margin-right", "0.5rem"),
                          ]),
                        ],
                        [text(size_kb)],
                      ),
                      button(
                        [
                          event.on_click(types.RemoveAudioFile(f.id)),
                          styles([
                            #("background", "rgba(248, 81, 73, 0.15)"),
                            #("color", "#f85149"),
                            #("border", "1px solid rgba(248, 81, 73, 0.4)"),
                            #("border-radius", "4px"),
                            #("padding", "0.15rem 0.45rem"),
                            #("font-size", "0.72rem"),
                            #("cursor", "pointer"),
                          ]),
                        ],
                        [text("🗑 Remove")],
                      ),
                    ],
                  )
                })
            },
          ),
        ],
      ),
    ],
  )
}
