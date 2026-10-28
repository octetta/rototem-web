//// # Audio File Library Modal View
////
//// Renders the modal overlay listing all loaded audio samples, their file sizes, and
//// options to remove individual files or clear the attached VFS sound library.
////

import gleam/int
import gleam/list
import lustre/attribute.{class}
import lustre/element.{type Element, text}
import lustre/element/html.{button, div, h2, p, span}
import lustre/event
import rototem/types.{type AudioFile, type Msg}

/// Renders the modal window displaying all currently mounted audio samples.
pub fn view_library_modal(library: List(AudioFile)) -> Element(Msg) {
  div([class("modal-backdrop")], [
    div([class("modal-content")], [
      div([class("modal-header")], [
        div([class("modal-title-row")], [
          h2([class("modal-title")], [
            text(
              "Attached Audio Files ("
              <> int.to_string(list.length(library))
              <> ")",
            ),
          ]),
          case list.is_empty(library) {
            True -> element.none()
            False ->
              button(
                [
                  class("btn-remove"),
                  event.on_click(types.ClearAudioLibrary),
                ],
                [text("Clear All")],
              )
          },
        ]),
        button(
          [
            class("btn-close"),
            event.on_click(types.ToggleLibraryModal),
          ],
          [text("✕")],
        ),
      ]),
      div([class("modal-list")], case library {
        [] -> [
          p([class("console-hint")], [
            text(
              "No audio files loaded yet. Click 'Folder' to load .wav, .mp3, or .flac files.",
            ),
          ]),
        ]
        _ ->
          list.map(library, fn(f) {
            let size_kb = int.to_string(f.size / 1024) <> " KB"
            div([class("modal-item")], [
              span([class("file-name")], [text(f.name)]),
              span([class("file-size")], [text(size_kb)]),
              button(
                [
                  class("btn-remove"),
                  event.on_click(types.RemoveAudioFile(f.id)),
                ],
                [text("🗑 Remove")],
              ),
            ])
          })
      }),
    ]),
  ])
}
