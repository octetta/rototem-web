//// # Rototem Web Main Application Entry
////
//// Initializes and runs the `rototem-web` Lustre application. Implements the root TEA loop
//// (`init`, `update`, `view`) decomposed into clean domain handlers (`update_track_msg`,
//// `update_master_msg`, `update_console_msg`, `update_ffi_msg`).
////

import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/effect.{type Effect}
import rototem/settings
import rototem/skode
import rototem/skred
import rototem/types.{
  type AudioFile, type Model, type Msg, type Track, ActiveDrag, ConsoleLog,
  Floating, Grid, Minimized, Model, Normal, Track,
}
import rototem/ui

const track_colors = [
  "#ff5722",
  "#2196f3",
  "#4caf50",
  "#ffeb3b",
  "#9c27b0",
  "#00bcd4",
  "#ff9800",
  "#795548",
]

fn init_tracks() -> List(Track) {
  list.index_map(track_colors, fn(color, idx) {
    Track(
      id: idx,
      left_voice: idx * 2,
      right_voice: idx * 2 + 1,
      color: color,
      audio_file: None,
      playing: False,
      muted: False,
      volume: 0.0,
      speed: 69.0,
      reversed: False,
      card_mode: Grid,
      card_display: Normal,
    )
  })
}

pub fn init(_flags) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      tracks: init_tracks(),
      library: [],
      vfs_files: [],
      master_volume: 0.0,
      all_playing: False,
      recording: False,
      devices: [types.AudioDevice("default", "Default Audio Output")],
      selected_device_id: "default",
      active_drag: None,
      next_z_index: 10,
      status_message: "Ready. Click 'Folder' or press Ctrl-~ for Skred Console.",
      show_library_modal: False,
      show_console: False,
      console_input: "",
      console_logs: [
        ConsoleLog(
          cmd: "welcome",
          ret: 0,
          response: "Skred Web Console Ready. Type '?a' for audio info, '?v' for voices, or 'help'.",
        ),
      ],
      command_history: [],
      history_index: -1,
      console_x: 120.0,
      console_y: 80.0,
      console_width: 620.0,
      console_height: 420.0,
      console_dragging: False,
      console_drag_start_x: 120.0,
      console_drag_start_y: 80.0,
      console_drag_mouse_x: 0.0,
      console_drag_mouse_y: 0.0,
      mobile_active_track: 0,
      theme: types.Dark,
    )

  let effects =
    effect.batch([
      skred.init_engine_effect(),
      skred.list_devices_effect(),
      skred.register_console_toggle_effect(),
      skred.subscribe_control_plane(types.ControlEventsReceived),
    ])

  #(model, effects)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn clamp_float(val: Float, min_val: Float, max_val: Float) -> Float {
  float.clamp(val, min: min_val, max: max_val)
}

fn update_track(
  tracks: List(Track),
  track_id: Int,
  updater: fn(Track) -> Track,
) -> List(Track) {
  list.map(tracks, fn(t) {
    case t.id == track_id {
      True -> updater(t)
      False -> t
    }
  })
}

fn track_control_command(t: Track, run: Bool) -> skode.SkodeCommand {
  skode.track_control(
    t.left_voice,
    t.right_voice,
    t.volume,
    t.speed,
    t.muted,
    t.reversed,
    run,
  )
}

fn pick_random_sample(files: List(AudioFile)) -> Option(AudioFile) {
  let len = list.length(files)
  case len {
    0 -> None
    _ -> {
      let idx = skred.get_random_int(len)
      list.drop(files, idx) |> list.first |> option.from_result
    }
  }
}

// ---------------------------------------------------------------------------
// Track Domain Update
// ---------------------------------------------------------------------------

fn update_track_msg(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    types.SelectTrackSample(track_id, file_id) -> {
      let selected_file =
        list.find(model.library, fn(f) { f.id == file_id })
        |> option.from_result

      let updated_tracks =
        update_track(model.tracks, track_id, fn(t) {
          Track(..t, audio_file: selected_file, playing: False)
        })

      let eff = case
        selected_file,
        list.find(model.tracks, fn(t) { t.id == track_id })
      {
        Some(f), Ok(t) -> {
          let wave_eff =
            skred.load_track_wave(t.left_voice, t.right_voice, f.path)
          let ctrl_cmd = track_control_command(t, False)
          effect.batch([wave_eff, skred.send(ctrl_cmd)])
        }
        None, Ok(t) -> {
          effect.batch([
            skred.load_track_wave(t.left_voice, t.right_voice, ""),
            skred.send(skode.stereo_run(t.left_voice, t.right_voice, False)),
          ])
        }
        _, _ -> effect.none()
      }

      let status = case selected_file {
        Some(f) ->
          "Assigned " <> f.name <> " to Track " <> int.to_string(track_id + 1)
        None -> "Cleared Track " <> int.to_string(track_id + 1)
      }

      let any_now_playing = list.any(updated_tracks, fn(t) { t.playing })
      #(
        Model(
          ..model,
          tracks: updated_tracks,
          all_playing: any_now_playing,
          status_message: status,
        ),
        eff,
      )
    }

    types.RandomTrackSample(track_id) -> {
      case model.library {
        [] -> #(
          Model(..model, status_message: "Load a folder with audio files first"),
          effect.none(),
        )
        _ -> {
          let sample = pick_random_sample(model.library)
          let updated_tracks =
            update_track(model.tracks, track_id, fn(t) {
              Track(..t, audio_file: sample, playing: False)
            })

          let eff = case
            sample,
            list.find(model.tracks, fn(t) { t.id == track_id })
          {
            Some(f), Ok(t) -> {
              let wave_eff =
                skred.load_track_wave(t.left_voice, t.right_voice, f.path)
              let ctrl_cmd = track_control_command(t, False)
              effect.batch([wave_eff, skred.send(ctrl_cmd)])
            }
            _, _ -> effect.none()
          }

          let status = case sample {
            Some(f) ->
              "Randomized: assigned "
              <> f.name
              <> " to Track "
              <> int.to_string(track_id + 1)
            None -> model.status_message
          }

          let any_now_playing = list.any(updated_tracks, fn(t) { t.playing })
          #(
            Model(
              ..model,
              tracks: updated_tracks,
              all_playing: any_now_playing,
              status_message: status,
            ),
            eff,
          )
        }
      }
    }

    types.ToggleTrackPlay(track_id) -> {
      case list.find(model.tracks, fn(t) { t.id == track_id }) {
        Ok(t) -> {
          case t.audio_file {
            None -> {
              #(
                Model(
                  ..model,
                  status_message: "Track "
                    <> int.to_string(track_id + 1)
                    <> ": Assign an audio sample before playing.",
                ),
                effect.none(),
              )
            }
            Some(_) -> {
              let new_play = !t.playing
              let updated_tracks =
                update_track(model.tracks, track_id, fn(tr) {
                  Track(..tr, playing: new_play)
                })
              let any_now_playing =
                list.any(updated_tracks, fn(tr) { tr.playing })
              let cmd = case new_play {
                True -> track_control_command(t, True)
                False -> skode.stereo_run(t.left_voice, t.right_voice, False)
              }
              #(
                Model(
                  ..model,
                  tracks: updated_tracks,
                  all_playing: any_now_playing,
                ),
                skred.send(cmd),
              )
            }
          }
        }
        Error(_) -> #(model, effect.none())
      }
    }

    types.SetTrackVolume(track_id, vol) -> {
      let clamped = clamp_float(vol, -60.0, 12.0)
      let updated_tracks =
        update_track(model.tracks, track_id, fn(t) {
          Track(..t, volume: clamped)
        })
      let eff = case list.find(model.tracks, fn(t) { t.id == track_id }) {
        Ok(t) ->
          skred.send(skode.stereo_volume(t.left_voice, t.right_voice, clamped))
        Error(_) -> effect.none()
      }
      #(Model(..model, tracks: updated_tracks), eff)
    }

    types.SetTrackSpeed(track_id, midi_pitch) -> {
      let clamped = clamp_float(midi_pitch, 0.0, 127.0)
      let updated_tracks =
        update_track(model.tracks, track_id, fn(t) {
          Track(..t, speed: clamped)
        })
      let eff = case list.find(model.tracks, fn(t) { t.id == track_id }) {
        Ok(t) ->
          skred.send(skode.stereo_speed(t.left_voice, t.right_voice, clamped))
        Error(_) -> effect.none()
      }
      #(Model(..model, tracks: updated_tracks), eff)
    }

    types.StepTrackSpeed(track_id, semitone_offset) -> {
      case list.find(model.tracks, fn(t) { t.id == track_id }) {
        Ok(t) -> {
          let new_pitch = case semitone_offset == 0.0 {
            True -> 69.0
            False -> clamp_float(t.speed +. semitone_offset, 0.0, 127.0)
          }
          let updated_tracks =
            update_track(model.tracks, track_id, fn(tr) {
              Track(..tr, speed: new_pitch)
            })
          let cmd = skode.stereo_speed(t.left_voice, t.right_voice, new_pitch)
          #(Model(..model, tracks: updated_tracks), skred.send(cmd))
        }
        Error(_) -> #(model, effect.none())
      }
    }

    types.ToggleTrackMute(track_id) -> {
      case list.find(model.tracks, fn(t) { t.id == track_id }) {
        Ok(t) -> {
          let new_mute = !t.muted
          let updated_tracks =
            update_track(model.tracks, track_id, fn(tr) {
              Track(..tr, muted: new_mute)
            })
          let cmd = skode.stereo_mute(t.left_voice, t.right_voice, new_mute)
          #(Model(..model, tracks: updated_tracks), skred.send(cmd))
        }
        Error(_) -> #(model, effect.none())
      }
    }

    types.ToggleTrackDirection(track_id) -> {
      case list.find(model.tracks, fn(t) { t.id == track_id }) {
        Ok(t) -> {
          let new_rev = !t.reversed
          let updated_tracks =
            update_track(model.tracks, track_id, fn(tr) {
              Track(..tr, reversed: new_rev)
            })
          let cmd = skode.stereo_flip(t.left_voice, t.right_voice)
          let status = case new_rev {
            True ->
              "Track "
              <> int.to_string(track_id + 1)
              <> " flipped to reverse (b1)"
            False ->
              "Track " <> int.to_string(track_id + 1) <> " set to forward (b0)"
          }
          #(
            Model(..model, tracks: updated_tracks, status_message: status),
            skred.send(cmd),
          )
        }
        Error(_) -> #(model, effect.none())
      }
    }

    types.ToggleTrackMinimize(track_id) -> {
      let updated_tracks =
        update_track(model.tracks, track_id, fn(t) {
          let new_disp = case t.card_display {
            Normal -> Minimized
            Minimized -> Normal
          }
          Track(..t, card_display: new_disp)
        })
      #(Model(..model, tracks: updated_tracks), effect.none())
    }

    types.RestoreAllTracks -> {
      let updated_tracks =
        list.map(model.tracks, fn(t) { Track(..t, card_display: Normal) })
      #(Model(..model, tracks: updated_tracks), effect.none())
    }

    types.FloatTrackCard(track_id) -> {
      let next_z = model.next_z_index + 1
      let default_x = 100.0 +. int.to_float(track_id) *. 25.0
      let default_y = 70.0 +. int.to_float(track_id) *. 25.0

      let updated_tracks =
        update_track(model.tracks, track_id, fn(t) {
          Track(..t, card_mode: Floating(default_x, default_y, next_z))
        })
      #(
        Model(..model, tracks: updated_tracks, next_z_index: next_z),
        effect.none(),
      )
    }

    types.DockTrackCard(track_id) -> {
      let updated_tracks =
        update_track(model.tracks, track_id, fn(t) {
          Track(..t, card_mode: Grid)
        })
      #(Model(..model, tracks: updated_tracks), effect.none())
    }

    types.StartDragCard(track_id, card_x, card_y, mouse_x, mouse_y) -> {
      let next_z = model.next_z_index + 1
      let updated_tracks =
        update_track(model.tracks, track_id, fn(t) {
          case t.card_mode {
            Floating(x, y, _) -> Track(..t, card_mode: Floating(x, y, next_z))
            Grid -> t
          }
        })

      let drag_state =
        Some(ActiveDrag(
          track_id:,
          start_card_x: card_x,
          start_card_y: card_y,
          start_mouse_x: mouse_x,
          start_mouse_y: mouse_y,
        ))

      #(
        Model(
          ..model,
          tracks: updated_tracks,
          active_drag: drag_state,
          next_z_index: next_z,
        ),
        effect.none(),
      )
    }

    types.DragCard(mouse_x, mouse_y) -> {
      case model.active_drag {
        Some(drag) -> {
          let dx = mouse_x -. drag.start_mouse_x
          let dy = mouse_y -. drag.start_mouse_y
          let new_x = float.max(0.0, drag.start_card_x +. dx)
          let new_y = float.max(0.0, drag.start_card_y +. dy)

          let updated_tracks =
            update_track(model.tracks, drag.track_id, fn(t) {
              case t.card_mode {
                Floating(_, _, z) ->
                  Track(..t, card_mode: Floating(new_x, new_y, z))
                Grid -> t
              }
            })
          #(Model(..model, tracks: updated_tracks), effect.none())
        }
        None -> #(model, effect.none())
      }
    }

    types.EndDragCard -> {
      #(Model(..model, active_drag: None), effect.none())
    }

    _ -> #(model, effect.none())
  }
}

// ---------------------------------------------------------------------------
// Master Workstation Domain Update
// ---------------------------------------------------------------------------

fn update_master_msg(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    types.PickDirectory -> {
      #(
        Model(..model, status_message: "Opening directory picker..."),
        skred.pick_directory_effect(),
      )
    }

    types.PickVfsFiles -> {
      #(
        Model(
          ..model,
          status_message: "Opening file picker for Skred Emscripten VFS...",
        ),
        skred.pick_vfs_files_effect(),
      )
    }

    types.VfsFilesUploaded(new_files) -> {
      let existing_names = list.map(new_files, fn(f) { f.name })
      let remaining =
        list.filter(model.vfs_files, fn(f) {
          !list.contains(existing_names, f.name)
        })
      let updated_vfs = list.append(remaining, new_files)

      let names_summary =
        new_files
        |> list.map(fn(f) { f.name })
        |> string.join(", ")

      let count = list.length(new_files)
      let status =
        "Added "
        <> int.to_string(count)
        <> " file(s) to Skred VFS: "
        <> names_summary

      let first_input = case list.first(new_files) {
        Ok(f) ->
          case f.ext {
            "zip" -> "[" <> f.name <> "] %z"
            "sk" -> "[" <> f.name <> "] /ls"
            "ks" -> "[" <> f.name <> "] /ks"
            "wav" | "mp3" | "flac" -> "[" <> f.name <> "] /w"
            _ -> "%cat " <> f.name
          }
        Error(_) -> model.console_input
      }

      let log_entry =
        types.ConsoleLog(
          cmd: first_input,
          ret: 0,
          response: status <> ". Ready in VFS root.",
        )

      #(
        Model(
          ..model,
          vfs_files: updated_vfs,
          status_message: status,
          console_input: first_input,
          console_logs: [log_entry, ..model.console_logs],
        ),
        effect.none(),
      )
    }

    types.RemoveVfsFile(name) -> {
      let updated_vfs = list.filter(model.vfs_files, fn(f) { f.name != name })
      #(
        Model(
          ..model,
          vfs_files: updated_vfs,
          status_message: "Removed " <> name <> " from Skred VFS.",
        ),
        skred.remove_vfs_file_effect(name),
      )
    }

    types.ToggleAllPlay -> {
      let any_playing = list.any(model.tracks, fn(t) { t.playing })
      let new_all_playing = !any_playing

      case new_all_playing {
        True -> {
          // Only start tracks with an assigned audio sample
          let playable_tracks =
            list.filter(model.tracks, fn(t) { option.is_some(t.audio_file) })

          case playable_tracks {
            [] -> {
              #(
                Model(
                  ..model,
                  status_message: "No audio samples assigned to any track. Load samples first.",
                ),
                effect.none(),
              )
            }
            _ -> {
              let updated_tracks =
                list.map(model.tracks, fn(t) {
                  case t.audio_file {
                    Some(_) -> Track(..t, playing: True)
                    None -> Track(..t, playing: False)
                  }
                })
              let cmd =
                skode.Bundle(
                  list.map(playable_tracks, fn(t) {
                    track_control_command(t, True)
                  }),
                )
              let count = list.length(playable_tracks)
              let status =
                "Started playback on "
                <> int.to_string(count)
                <> " track(s) with assigned waves"
              #(
                Model(
                  ..model,
                  all_playing: True,
                  tracks: updated_tracks,
                  status_message: status,
                ),
                skred.send(cmd),
              )
            }
          }
        }

        False -> {
          let updated_tracks =
            list.map(model.tracks, fn(t) { Track(..t, playing: False) })
          let cmd =
            skode.Bundle(
              list.map(model.tracks, fn(t) {
                skode.stereo_run(t.left_voice, t.right_voice, False)
              }),
            )
          #(
            Model(
              ..model,
              all_playing: False,
              tracks: updated_tracks,
              status_message: "Stopped playback on all tracks",
            ),
            skred.send(cmd),
          )
        }
      }
    }

    types.SetAllPlay(playing) -> {
      case playing {
        True -> {
          let playable_tracks =
            list.filter(model.tracks, fn(t) { option.is_some(t.audio_file) })

          case playable_tracks {
            [] -> {
              #(
                Model(
                  ..model,
                  status_message: "No audio samples assigned to any track.",
                ),
                effect.none(),
              )
            }
            _ -> {
              let updated_tracks =
                list.map(model.tracks, fn(t) {
                  case t.audio_file {
                    Some(_) -> Track(..t, playing: True)
                    None -> Track(..t, playing: False)
                  }
                })
              let cmd =
                skode.Bundle(
                  list.map(playable_tracks, fn(t) {
                    track_control_command(t, True)
                  }),
                )
              let count = list.length(playable_tracks)
              let status =
                "Started playback on "
                <> int.to_string(count)
                <> " track(s) with assigned waves"
              #(
                Model(
                  ..model,
                  all_playing: True,
                  tracks: updated_tracks,
                  status_message: status,
                ),
                skred.send(cmd),
              )
            }
          }
        }

        False -> {
          let updated_tracks =
            list.map(model.tracks, fn(t) { Track(..t, playing: False) })
          let cmd =
            skode.Bundle(
              list.map(model.tracks, fn(t) {
                skode.stereo_run(t.left_voice, t.right_voice, False)
              }),
            )
          #(
            Model(
              ..model,
              all_playing: False,
              tracks: updated_tracks,
              status_message: "Stopped playback on all tracks",
            ),
            skred.send(cmd),
          )
        }
      }
    }

    types.RandomizeAllSamples -> {
      case model.library {
        [] -> #(
          Model(..model, status_message: "No audio files attached yet"),
          effect.none(),
        )
        _ -> {
          let #(new_tracks, commands) =
            list.map(model.tracks, fn(t) {
              let sample = pick_random_sample(model.library)
              let updated_t = Track(..t, audio_file: sample, playing: False)
              let eff = case sample {
                Some(f) -> {
                  let wave_eff =
                    skred.load_track_wave(t.left_voice, t.right_voice, f.path)
                  let ctrl_cmd = track_control_command(t, False)
                  effect.batch([wave_eff, skred.send(ctrl_cmd)])
                }
                None -> effect.none()
              }
              #(updated_t, eff)
            })
            |> list.unzip

          #(
            Model(
              ..model,
              tracks: new_tracks,
              all_playing: False,
              status_message: "Randomized sounds on all tracks (playback reset)",
            ),
            effect.batch(commands),
          )
        }
      }
    }

    types.SaveProjectZip -> {
      let settings_json =
        settings.serialize_project(model.master_volume, model.tracks)
      #(
        Model(..model, status_message: "Exporting project ZIP..."),
        skred.export_zip_effect(settings_json),
      )
    }

    types.TriggerLoadZip -> {
      #(
        Model(..model, status_message: "Select a project ZIP file..."),
        skred.load_zip_effect(),
      )
    }

    types.SetMasterVolume(vol) -> {
      let clamped = clamp_float(vol, -60.0, 12.0)
      #(
        Model(..model, master_volume: clamped),
        skred.send(skode.SetMasterVolume(clamped)),
      )
    }

    types.SelectOutputDevice(device_id) -> {
      #(
        Model(..model, selected_device_id: device_id),
        skred.set_output_device_effect(device_id),
      )
    }

    types.ToggleRecord -> {
      #(model, skred.toggle_recording_effect())
    }

    types.ToggleLibraryModal -> {
      #(
        Model(..model, show_library_modal: !model.show_library_modal),
        effect.none(),
      )
    }

    types.ToggleTheme -> {
      let next_theme = case model.theme {
        types.Dark -> types.Light
        types.Light -> types.Dark
      }
      #(Model(..model, theme: next_theme), effect.none())
    }

    types.RemoveAudioFile(file_id) -> {
      let updated_library =
        list.filter(model.library, fn(f) { f.id != file_id })
      let affected_tracks =
        list.filter(model.tracks, fn(t) {
          case t.audio_file {
            Some(f) -> f.id == file_id
            None -> False
          }
        })
      let updated_tracks =
        list.map(model.tracks, fn(t) {
          case t.audio_file {
            Some(f) if f.id == file_id ->
              Track(..t, audio_file: None, playing: False)
            _ -> t
          }
        })
      let stop_effects =
        list.map(affected_tracks, fn(t) {
          skred.send(
            skode.Bundle([
              skode.stereo_run(t.left_voice, t.right_voice, False),
              skode.Raw(
                "v"
                <> int.to_string(t.left_voice)
                <> "w82;v"
                <> int.to_string(t.right_voice)
                <> "w82",
              ),
            ]),
          )
        })
      let remove_eff = skred.remove_audio_file(file_id)
      #(
        Model(
          ..model,
          library: updated_library,
          tracks: updated_tracks,
          status_message: "Removed " <> file_id <> " from attached library.",
        ),
        effect.batch([remove_eff, ..stop_effects]),
      )
    }

    types.ClearAudioLibrary -> {
      let stop_all = skred.send(skode.StopAll)
      let clear_vfs = skred.clear_audio_library()
      let updated_tracks =
        list.map(model.tracks, fn(t) {
          Track(..t, audio_file: None, playing: False)
        })
      #(
        Model(
          ..model,
          library: [],
          tracks: updated_tracks,
          all_playing: False,
          status_message: "Cleared all audio files from library and VFS.",
        ),
        effect.batch([stop_all, clear_vfs]),
      )
    }

    types.SetMobileActiveTrack(idx) -> {
      #(Model(..model, mobile_active_track: idx), effect.none())
    }

    _ -> #(model, effect.none())
  }
}

// ---------------------------------------------------------------------------
// Console REPL Domain Update
// ---------------------------------------------------------------------------

fn update_console_msg(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    types.ToggleConsole -> {
      #(Model(..model, show_console: !model.show_console), effect.none())
    }

    types.SetConsoleInput(input) -> {
      #(Model(..model, console_input: input), effect.none())
    }

    types.SubmitConsoleCommand -> {
      let trimmed = string.trim(model.console_input)
      case trimmed {
        "" -> #(model, effect.none())
        cmd -> {
          let history = [
            cmd,
            ..list.filter(model.command_history, fn(c) { c != cmd })
          ]
          #(
            Model(
              ..model,
              console_input: "",
              command_history: history,
              history_index: -1,
            ),
            skred.eval_command_effect(cmd),
          )
        }
      }
    }

    types.ExecuteConsoleCommand(cmd) -> {
      let trimmed = string.trim(cmd)
      case trimmed {
        "" -> #(model, effect.none())
        c -> {
          let history = [
            c,
            ..list.filter(model.command_history, fn(item) { item != c })
          ]
          #(
            Model(
              ..model,
              console_input: c,
              command_history: history,
              history_index: -1,
            ),
            skred.eval_command_effect(c),
          )
        }
      }
    }

    types.ConsoleHistoryUp -> {
      let len = list.length(model.command_history)
      case len > 0 {
        True -> {
          let next_idx = int.min(len - 1, model.history_index + 1)
          let picked_cmd =
            list.drop(model.command_history, next_idx)
            |> list.first
            |> option.from_result
            |> option.unwrap(model.console_input)
          #(
            Model(..model, history_index: next_idx, console_input: picked_cmd),
            effect.none(),
          )
        }
        False -> #(model, effect.none())
      }
    }

    types.ConsoleHistoryDown -> {
      case model.history_index > 0 {
        True -> {
          let next_idx = model.history_index - 1
          let picked_cmd =
            list.drop(model.command_history, next_idx)
            |> list.first
            |> option.from_result
            |> option.unwrap("")
          #(
            Model(..model, history_index: next_idx, console_input: picked_cmd),
            effect.none(),
          )
        }
        False -> {
          #(Model(..model, history_index: -1, console_input: ""), effect.none())
        }
      }
    }

    types.ConsoleResultReceived(cmd, ret, response) -> {
      let log = ConsoleLog(cmd:, ret:, response:)
      let updated_logs = list.append(model.console_logs, [log])
      #(Model(..model, console_logs: updated_logs), effect.none())
    }

    types.ClearConsole -> {
      #(Model(..model, console_logs: []), effect.none())
    }

    types.StartDragConsole(mouse_x, mouse_y) -> {
      #(
        Model(
          ..model,
          console_dragging: True,
          console_drag_start_x: model.console_x,
          console_drag_start_y: model.console_y,
          console_drag_mouse_x: mouse_x,
          console_drag_mouse_y: mouse_y,
        ),
        effect.none(),
      )
    }

    types.DragConsole(mouse_x, mouse_y) -> {
      case model.console_dragging {
        True -> {
          let dx = mouse_x -. model.console_drag_mouse_x
          let dy = mouse_y -. model.console_drag_mouse_y
          let new_x = float.max(0.0, model.console_drag_start_x +. dx)
          let new_y = float.max(0.0, model.console_drag_start_y +. dy)
          #(Model(..model, console_x: new_x, console_y: new_y), effect.none())
        }
        False -> #(model, effect.none())
      }
    }

    types.EndDragConsole -> {
      #(Model(..model, console_dragging: False), effect.none())
    }

    types.ResetConsolePosition -> {
      #(
        Model(
          ..model,
          console_x: 120.0,
          console_y: 80.0,
          console_width: 620.0,
          console_height: 420.0,
        ),
        effect.none(),
      )
    }

    _ -> #(model, effect.none())
  }
}

// ---------------------------------------------------------------------------
// FFI & Hardware Domain Update
// ---------------------------------------------------------------------------

fn update_ffi_msg(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    types.FilesLoaded(new_files) -> {
      let count = list.length(new_files)
      let merged = list.append(model.library, new_files)
      #(
        Model(
          ..model,
          library: merged,
          status_message: "Loaded "
            <> int.to_string(count)
            <> " audio files into library.",
        ),
        effect.none(),
      )
    }

    types.ZipProjectLoaded(json_str, restored_files) -> {
      let merged_library = list.append(model.library, restored_files)

      case settings.decode_project(json_str) {
        Ok(proj) -> {
          let updated_tracks =
            list.map(model.tracks, fn(t) {
              let saved = list.find(proj.tracks, fn(st) { st.id == t.id })
              case saved {
                Ok(st) -> {
                  let file_opt = case st.sample_name {
                    Some(name) ->
                      list.find(merged_library, fn(f) { f.name == name })
                      |> option.from_result
                    None -> None
                  }
                  let card_mode = case st.is_floating {
                    True -> Floating(st.x, st.y, model.next_z_index)
                    False -> Grid
                  }
                  let card_display = case st.minimized {
                    True -> Minimized
                    False -> Normal
                  }
                  Track(
                    ..t,
                    audio_file: file_opt,
                    volume: st.volume,
                    speed: st.speed,
                    muted: st.muted,
                    playing: st.playing,
                    reversed: st.reversed,
                    card_mode: card_mode,
                    card_display: card_display,
                  )
                }
                Error(_) -> t
              }
            })

          let wave_effects =
            list.filter_map(updated_tracks, fn(t) {
              case t.audio_file {
                Some(f) ->
                  Ok(skred.load_track_wave(t.left_voice, t.right_voice, f.path))
                None -> Error(Nil)
              }
            })

          #(
            Model(
              ..model,
              tracks: updated_tracks,
              library: merged_library,
              master_volume: proj.master_volume,
              status_message: "Project successfully restored from ZIP.",
            ),
            effect.batch(wave_effects),
          )
        }
        Error(_) -> {
          #(
            Model(
              ..model,
              library: merged_library,
              status_message: "Restored audio files from ZIP (default settings applied).",
            ),
            effect.none(),
          )
        }
      }
    }

    types.AudioDevicesListed(devs) -> {
      #(Model(..model, devices: devs), effect.none())
    }

    types.StatusUpdated(msg) -> {
      #(Model(..model, status_message: msg), effect.none())
    }

    types.EngineInitialized(success) -> {
      let status = case success {
        True -> "Skred Audio Engine initialized (256 voices ready)."
        False -> "Warning: Audio engine could not be initialized."
      }
      #(Model(..model, status_message: status), effect.none())
    }

    types.RecordingStateChanged(rec) -> {
      let status = case rec {
        True -> "Recording master mix started..."
        False -> "Recording finished and exported."
      }
      #(Model(..model, recording: rec, status_message: status), effect.none())
    }

    types.ControlEventsReceived(events) -> {
      // Fold chronologically over control plane events to track voice playback
      let voice_updates =
        list.fold(events, dict.new(), fn(acc, ev) {
          case ev {
            types.VoiceTrigger(v, _) if v >= 0 && v < 16 ->
              dict.insert(acc, v / 2, True)
            types.VoiceRelease(v) if v >= 0 && v < 16 ->
              dict.insert(acc, v / 2, False)
            types.VoiceFinished(v) if v >= 0 && v < 16 ->
              dict.insert(acc, v / 2, False)
            _ -> acc
          }
        })

      case dict.is_empty(voice_updates) {
        True -> #(model, effect.none())
        False -> {
          let updated_tracks =
            list.map(model.tracks, fn(t) {
              case dict.get(voice_updates, t.id) {
                Ok(new_state) -> Track(..t, playing: new_state)
                Error(_) -> t
              }
            })
          let any_now_playing = list.any(updated_tracks, fn(t) { t.playing })
          #(
            Model(..model, tracks: updated_tracks, all_playing: any_now_playing),
            effect.none(),
          )
        }
      }
    }

    _ -> #(model, effect.none())
  }
}

// ---------------------------------------------------------------------------
// Main Update Router
// ---------------------------------------------------------------------------

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    types.SelectTrackSample(..)
    | types.RandomTrackSample(..)
    | types.ToggleTrackPlay(..)
    | types.SetTrackVolume(..)
    | types.SetTrackSpeed(..)
    | types.StepTrackSpeed(..)
    | types.ToggleTrackMute(..)
    | types.ToggleTrackDirection(..)
    | types.ToggleTrackMinimize(..)
    | types.RestoreAllTracks
    | types.FloatTrackCard(..)
    | types.DockTrackCard(..)
    | types.StartDragCard(..)
    | types.DragCard(..)
    | types.EndDragCard -> update_track_msg(model, msg)

    types.PickDirectory
    | types.PickVfsFiles
    | types.VfsFilesUploaded(..)
    | types.RemoveVfsFile(..)
    | types.ToggleAllPlay
    | types.SetAllPlay(..)
    | types.RandomizeAllSamples
    | types.SaveProjectZip
    | types.TriggerLoadZip
    | types.SetMasterVolume(..)
    | types.SelectOutputDevice(..)
    | types.ToggleRecord
    | types.ToggleLibraryModal
    | types.ToggleTheme
    | types.RemoveAudioFile(..)
    | types.ClearAudioLibrary
    | types.SetMobileActiveTrack(..) -> update_master_msg(model, msg)

    types.ToggleConsole
    | types.SetConsoleInput(..)
    | types.SubmitConsoleCommand
    | types.ExecuteConsoleCommand(..)
    | types.ConsoleHistoryUp
    | types.ConsoleHistoryDown
    | types.ConsoleResultReceived(..)
    | types.ClearConsole
    | types.StartDragConsole(..)
    | types.DragConsole(..)
    | types.EndDragConsole
    | types.ResetConsolePosition -> update_console_msg(model, msg)

    types.FilesLoaded(..)
    | types.ZipProjectLoaded(..)
    | types.AudioDevicesListed(..)
    | types.StatusUpdated(..)
    | types.EngineInitialized(..)
    | types.RecordingStateChanged(..)
    | types.ControlEventsReceived(..) -> update_ffi_msg(model, msg)
  }
}

// ---------------------------------------------------------------------------
// Application Entry Point
// ---------------------------------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, ui.view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
