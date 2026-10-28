//// # Top-Level Lustre View Orchestrator
////
//// Coordinates the visual layout of `rototem-web`, assembling subviews from
//// `rototem/views/` (Master Bar, Track Card Grid & Floating Overlay, Skred Console Drawer,
//// and Sound Library Modal) and binding global Pointer Event drag decoders.
////

import gleam/dynamic/decode
import gleam/list
import gleam/option
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html.{div}
import lustre/event
import rototem/types.{type Model, type Msg, Dark}
import rototem/views/common
import rototem/views/console.{view_console_drawer}
import rototem/views/library_modal.{view_library_modal}
import rototem/views/master_bar.{
  view_master_bar, view_mobile_track_tabs, view_status_banner,
}
import rototem/views/track_card.{
  view_card_grid, view_floating_layer, view_minimized_dock,
}

// Re-exported for test compatibility with rototem_web_test.gleam
pub type ThemePalette =
  common.ThemePalette

/// Retrieves the color tokens for a given UI theme.
pub fn get_palette(theme: types.Theme) -> common.ThemePalette {
  common.get_palette(theme)
}

/// Formats a decibel level into a display string with sign and unit.
pub fn format_db(vol: Float) -> String {
  common.format_db(vol)
}

// ---------------------------------------------------------------------------
// Top-Level View Orchestrator
// ---------------------------------------------------------------------------

/// Root view function composing the Master Bar, Status Banner, Track Workspace,
/// REPL Console drawer, and Library Modal.
pub fn view(model: Model) -> Element(Msg) {
  let is_card_dragging = option.is_some(model.active_drag)
  let is_console_dragging = model.console_dragging

  let theme_class = case model.theme {
    Dark -> "theme-dark"
    types.Light -> "theme-light"
  }

  let drag_class = case is_card_dragging || is_console_dragging {
    True -> " dragging"
    False -> ""
  }

  let container_attrs = [class("rototem-app " <> theme_class <> drag_class)]

  // Unified Pointer Events (touch, mouse, stylus)
  let drag_attrs = case is_card_dragging {
    True -> [
      event.on("pointermove", common.pointer_move_decoder()),
      event.on("pointerup", decode.success(types.EndDragCard)),
    ]
    False ->
      case is_console_dragging {
        True -> [
          event.on("pointermove", common.pointer_move_console_decoder()),
          event.on("pointerup", decode.success(types.EndDragConsole)),
        ]
        False -> []
      }
  }

  div(list.append(container_attrs, drag_attrs), [
    view_master_bar(model),
    view_status_banner(model.status_message),
    view_mobile_track_tabs(model),
    div([class("workspace-area")], [
      // Minimized track dock/shelf on desktop
      view_minimized_dock(model.tracks),
      // 1. Grid of docked cards
      view_card_grid(model.tracks, model.library, model.mobile_active_track),
      // 2. Floating overlay of popped-out cards
      view_floating_layer(model.tracks, model.library),
    ]),
    case model.show_console {
      True -> view_console_drawer(model)
      False -> element.none()
    },
    case model.show_library_modal {
      True -> view_library_modal(model.library)
      False -> element.none()
    },
  ])
}
