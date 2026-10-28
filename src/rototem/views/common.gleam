//// # Common View Utilities, Pointer Decoders & Theme Palettes
////
//// Provides reusable formatters (`format_db`, `format_pitch`), safe input parsers,
//// and Lustre event decoders implementing Pointer Capture for drag-and-drop operations.
////

import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/option.{Some}
import rototem/skred
import rototem/types.{type Msg, type Theme, Dark, Light}

// ---------------------------------------------------------------------------
// Pointer Event Decoders (Touch, Mouse, Pen with Pointer Capture)
// ---------------------------------------------------------------------------

fn is_not_button_decoder() -> decode.Decoder(Nil) {
  use target_tag <- decode.subfield(
    ["target", "tagName"],
    decode.optional(decode.string),
  )
  case target_tag {
    Some("BUTTON") | Some("button") ->
      decode.failure(Nil, "Ignored click on button")
    _ -> decode.success(Nil)
  }
}

fn capture_pointer_decoder() -> decode.Decoder(Nil) {
  decode.new_primitive_decoder("PointerCapture", fn(d) {
    skred.capture_pointer(d)
    Ok(Nil)
  })
}

/// Decodes pointer down event coordinates, initiates card drag, and captures pointer.
pub fn pointer_down_drag_decoder(
  track_id: Int,
  card_x: Float,
  card_y: Float,
) -> decode.Decoder(Msg) {
  use _ <- decode.then(is_not_button_decoder())
  use _ <- decode.then(capture_pointer_decoder())
  use cx <- decode.field("clientX", decode.float)
  use cy <- decode.field("clientY", decode.float)
  decode.success(types.StartDragCard(track_id, card_x, card_y, cx, cy))
}

/// Decodes pointer movement coordinates during card drag.
pub fn pointer_move_decoder() -> decode.Decoder(Msg) {
  use cx <- decode.field("clientX", decode.float)
  use cy <- decode.field("clientY", decode.float)
  decode.success(types.DragCard(cx, cy))
}

/// Decodes pointer down event coordinates for the console drawer drag header.
pub fn pointer_down_drag_console_decoder() -> decode.Decoder(Msg) {
  use _ <- decode.then(is_not_button_decoder())
  use _ <- decode.then(capture_pointer_decoder())
  use cx <- decode.field("clientX", decode.float)
  use cy <- decode.field("clientY", decode.float)
  decode.success(types.StartDragConsole(cx, cy))
}

/// Decodes pointer movement coordinates during console drawer drag.
pub fn pointer_move_console_decoder() -> decode.Decoder(Msg) {
  use cx <- decode.field("clientX", decode.float)
  use cy <- decode.field("clientY", decode.float)
  decode.success(types.DragConsole(cx, cy))
}

// Backward-compatible aliases
pub const mouse_down_drag_decoder = pointer_down_drag_decoder

pub const mouse_move_decoder = pointer_move_decoder

pub const mouse_down_drag_console_decoder = pointer_down_drag_console_decoder

pub const mouse_move_console_decoder = pointer_move_console_decoder

/// Decodes keyboard navigation and command submission inside the REPL input field.
pub fn key_down_console_decoder() -> decode.Decoder(Msg) {
  use key <- decode.field("key", decode.string)
  case key {
    "Enter" -> decode.success(types.SubmitConsoleCommand)
    "ArrowUp" -> decode.success(types.ConsoleHistoryUp)
    "ArrowDown" -> decode.success(types.ConsoleHistoryDown)
    "Escape" -> decode.success(types.ToggleConsole)
    _ -> decode.failure(types.SubmitConsoleCommand, "Not handled")
  }
}

/// Safely parses a string into a float, falling back to a default value on parse error.
pub fn parse_float_input(val_str: String, fallback: Float) -> Float {
  case float.parse(val_str) {
    Ok(v) -> v
    Error(_) ->
      case int.parse(val_str) {
        Ok(i) -> int.to_float(i)
        Error(_) -> fallback
      }
  }
}

/// Formats a speed / MIDI pitch float value to 1 decimal place (e.g. "69.0").
pub fn format_pitch(speed: Float) -> String {
  let rounded = float.round(speed *. 10.0)
  let int_part = rounded / 10
  let dec_part = int.absolute_value(rounded % 10)
  int.to_string(int_part) <> "." <> int.to_string(dec_part)
}

/// Formats decibel volume values with sign and 1 decimal place (e.g. "+3.5 dB", "-6.0 dB", "0.0 dB").
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
      prefix
      <> int.to_string(int_part)
      <> "."
      <> int.to_string(dec_part)
      <> " dB"
    }
    False -> {
      case rounded > 0 {
        True ->
          "+"
          <> int.to_string(int_part)
          <> "."
          <> int.to_string(dec_part)
          <> " dB"
        False -> "0.0 dB"
      }
    }
  }
}

/// Color tokens defining the workstation surface, text, and border aesthetics.
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

/// Returns the color palette values for either `Dark` or `Light` UI theme.
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
