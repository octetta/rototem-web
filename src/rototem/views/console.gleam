//// # Skred REPL & Diagnostic Console View
////
//// Renders the floating, draggable, resizable Skred console drawer (`Ctrl-~`), allowing
//// live evaluation of Skode ASCII commands, history navigation, and stdout inspection.
////

import gleam/float
import gleam/int
import gleam/list
import lustre/attribute.{attribute, class, styles, type_, value}
import lustre/element.{type Element, text}
import lustre/element/html.{button, div, input, pre, span}
import lustre/event
import rototem/types.{type ConsoleLog, type Model, type Msg}
import rototem/views/common.{
  key_down_console_decoder, pointer_down_drag_console_decoder,
}

/// Renders the floating, draggable, resizable Skred REPL console drawer.
pub fn view_console_drawer(model: Model) -> Element(Msg) {
  // Fast GPU-composited positioning via CSS Custom Properties
  div(
    [
      class("console-window"),
      styles([
        #("--console-x", float.to_string(model.console_x)),
        #("--console-y", float.to_string(model.console_y)),
        #("--console-w", float.to_string(model.console_width)),
        #("--console-h", float.to_string(model.console_height)),
      ]),
    ],
    [
      // Console Header Bar (Drag Handle)
      div(
        [
          class(case model.console_dragging {
            True -> "console-title-bar grabbing"
            False -> "console-title-bar"
          }),
          event.on("pointerdown", pointer_down_drag_console_decoder()),
        ],
        [
          div([class("card-header-left")], [
            span([class("console-title")], [text("SKRED CONSOLE")]),
            span([class("console-hint")], [
              text("drag to move • resize corner • Ctrl-~ or Esc"),
            ]),
          ]),
          div([class("card-header-right")], [
            button(
              [
                class("card-action-btn"),
                event.on_click(types.ResetConsolePosition),
              ],
              [text("⟲ Pos")],
            ),
            button(
              [
                class("card-action-btn"),
                event.on_click(types.ClearConsole),
              ],
              [text("Clear")],
            ),
            button(
              [
                class("btn-close"),
                event.on_click(types.ToggleConsole),
              ],
              [text("✕")],
            ),
          ]),
        ],
      ),

      // Quick diagnostic button toolbar
      div([class("console-quick-bar")], [
        span([class("console-hint")], [text("Quick Diagnostics:")]),
        quick_cmd_btn("?a (Audio Status)", "?a"),
        quick_cmd_btn("?v (Voices)", "?v"),
        quick_cmd_btn("v0? (Voice 0)", "v0?"),
        quick_cmd_btn("/ws (Wavetables)", "/ws"),
        quick_cmd_btn("?q (Queue)", "?q"),
        quick_cmd_btn("?? (Full Status)", "??"),
        quick_cmd_btn("v0l1; v1l1 (V0-1 Run)", "v0l1; v1l1"),
        quick_cmd_btn("v0l0; v1l0 (V0-1 Stop)", "v0l0; v1l0"),
      ]),

      // Console Log Output
      div(
        [class("console-log-area")],
        list.map(model.console_logs, fn(log: ConsoleLog) {
          div([class("console-log-card")], [
            div([class("console-log-meta")], [
              span([class("console-log-cmd")], [text("> " <> log.cmd)]),
              span(
                [
                  class(case log.ret == 0 {
                    True -> "console-log-ret-ok"
                    False -> "console-log-ret-err"
                  }),
                ],
                [text("ret: " <> int.to_string(log.ret))],
              ),
            ]),
            pre([class("console-log-pre")], [text(log.response)]),
          ])
        }),
      ),

      // Console Command Input Row
      div([class("console-input-row")], [
        span([class("console-prompt")], [text("skred>")]),
        input([
          type_("text"),
          class("console-input"),
          attribute(
            "placeholder",
            "Type ASCII Skode command and press Enter (e.g. ?a, v0 w82 f440 a10)...",
          ),
          value(model.console_input),
          event.on_input(types.SetConsoleInput),
          event.on("keydown", key_down_console_decoder()),
        ]),
        button(
          [
            class("btn btn-accent"),
            event.on_click(types.SubmitConsoleCommand),
          ],
          [text("Send (Enter)")],
        ),
      ]),
    ],
  )
}

fn quick_cmd_btn(label_str: String, cmd: String) -> Element(Msg) {
  button(
    [
      class("quick-cmd-btn"),
      event.on_click(types.ConsoleResultReceived(cmd, 0, "")),
      event.on_click(types.SetConsoleInput(cmd)),
    ],
    [text(label_str)],
  )
}
