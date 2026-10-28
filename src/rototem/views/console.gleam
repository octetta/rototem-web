//// # Skred REPL & Diagnostic Console View
////
//// Renders the floating, draggable, resizable Skred console drawer (`Ctrl-~`), allowing
//// live evaluation of Skode ASCII commands, history navigation, and stdout inspection.
////

import gleam/float
import gleam/int
import gleam/list
import lustre/attribute.{attribute, class, styles, type_, value}
import lustre/element.{type Element, none, text}
import lustre/element/html.{button, div, input, pre, span}
import lustre/event
import rototem/types.{type ConsoleLog, type Model, type Msg, type VfsFile}
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
      // Console Header Bar
      div(
        [
          class(case model.console_dragging {
            True -> "console-title-bar grabbing"
            False -> "console-title-bar"
          }),
        ],
        [
          // Drag handle on title & hint area
          div(
            [
              class("card-header-left draggable"),
              event.on("pointerdown", pointer_down_drag_console_decoder()),
            ],
            [
              span([class("console-title")], [text("SKRED CONSOLE")]),
              span([class("console-hint")], [
                text("drag to move • resize corner • Ctrl-~ or Esc"),
              ]),
            ],
          ),
          div([class("card-header-right")], [
            button(
              [
                class("card-action-btn"),
                attribute(
                  "title",
                  "Add files (.zip, .sk, .ks, .wav, .mp3, .flac) to Skred VFS",
                ),
                event.on_click(types.PickVfsFiles),
              ],
              [text("📄 Add File")],
            ),
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
        span([class("console-hint")], [text("Quick Commands:")]),
        quick_cmd_btn("? (Voice 0)", "v0 ?"),
        quick_cmd_btn("?? (All Voices)", "??"),
        quick_cmd_btn("?ws (Wavetables)", "?ws"),
        quick_cmd_btn("?m (Macros)", "?m"),
        quick_cmd_btn("?q (Queue)", "?q"),
        quick_cmd_btn("?ce (Events)", "?ce"),
        quick_cmd_btn("%ls (VFS List)", "%ls"),
        quick_cmd_btn("%pwd (VFS Info)", "%pwd"),
        quick_cmd_btn("%zu (Unmount)", "%zu"),
        quick_cmd_btn("v0l1; v1l1 (V0-1 Run)", "v0l1; v1l1"),
        quick_cmd_btn("v0l0; v1l0 (V0-1 Stop)", "v0l0; v1l0"),
        quick_cmd_btn("*l0 (Stop All)", "*l0"),
      ]),

      // VFS Files Bar (Uploaded .zip, .sk, .ks, etc.)
      view_vfs_files_bar(model.vfs_files),

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
      event.on_click(types.ExecuteConsoleCommand(cmd)),
    ],
    [text(label_str)],
  )
}

fn view_vfs_files_bar(files: List(VfsFile)) -> Element(Msg) {
  case files {
    [] -> none()
    _ ->
      div([class("console-vfs-bar")], [
        span([class("console-hint")], [text("VFS Files:")]),
        ..list.map(files, fn(f: VfsFile) {
          let click_cmd = case f.ext {
            "zip" -> "[" <> f.name <> "] %z"
            "sk" -> "[" <> f.name <> "] /ls"
            "ks" -> "[" <> f.name <> "] /ks"
            "wav" | "mp3" | "flac" -> "[" <> f.name <> "] /w"
            _ -> "%cat " <> f.name
          }
          let icon = case f.ext {
            "zip" -> "📦 "
            "sk" -> "🎼 "
            "ks" -> "🧮 "
            "wav" | "mp3" | "flac" -> "🔊 "
            _ -> "📄 "
          }
          div([class("vfs-chip")], [
            button(
              [
                class("quick-cmd-btn"),
                attribute("title", "Click to insert `" <> click_cmd <> "`"),
                event.on_click(types.SetConsoleInput(click_cmd)),
              ],
              [text(icon <> f.name)],
            ),
            button(
              [
                class("vfs-chip-remove"),
                attribute("title", "Remove " <> f.name <> " from VFS"),
                event.on_click(types.RemoveVfsFile(f.name)),
              ],
              [text("✕")],
            ),
          ])
        })
      ])
  }
}
