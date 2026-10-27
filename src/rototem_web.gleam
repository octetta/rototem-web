import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/effect.{type Effect}
import rototem/settings
import rototem/skred
import rototem/types.{
  type AudioFile, type Model, type Msg, type Track, ActiveDrag,
  ConsoleLog, Floating, Grid, Minimized, Model, Normal, Track,
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
      master_volume: 0.0,
      all_playing: False,
      recording: False,
      devices: [types.AudioDevice("default", "Default Audio Output")],
      selected_device_id: "default",
      active_drag: None,
      next_z_index: 10,
      status_message: "Ready. Click 'Select Folder' or press Ctrl-~ for Skred Console.",
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
      // Floating & Resizable Console Window
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
    ])

  #(model, effects)
}

fn clamp_float(val: Float, min_val: Float, max_val: Float) -> Float {
  case val <. min_val {
    True -> min_val
    False ->
      case val >. max_val {
        True -> max_val
        False -> val
      }
  }
}

// Random sample selection from library using FFI Math.random
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

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    // -----------------------------------------------------------------------
    // Track Operations
    // -----------------------------------------------------------------------
    types.SelectTrackSample(track_id, file_id) -> {
      let selected_file =
        list.find(model.library, fn(f) { f.id == file_id })
        |> option.from_result

      let updated_tracks =
        list.map(model.tracks, fn(t) {
          case t.id == track_id {
            True -> Track(..t, audio_file: selected_file, playing: False)
            False -> t
          }
        })

      let track_opt = list.find(model.tracks, fn(t) { t.id == track_id })
      let eff = case selected_file, track_opt {
        Some(f), Ok(t) -> {
          let left_v = track_id * 2
          let right_v = track_id * 2 + 1
          let wave_eff = skred.load_track_wave(left_v, right_v, f.path)
          let ctrl_cmd =
            skred.format_voice_volume(left_v, right_v, t.volume)
            <> ";"
            <> skred.format_voice_speed(left_v, right_v, t.speed)
            <> ";"
            <> skred.format_voice_mute(left_v, right_v, t.muted)
            <> ";"
            <> skred.format_voice_direction(left_v, right_v, t.reversed)
            <> ";"
            <> skred.format_voice_run(left_v, right_v, False)
          effect.batch([wave_eff, skred.send_command(ctrl_cmd)])
        }
        None, Ok(_) -> {
          let left_v = track_id * 2
          let right_v = track_id * 2 + 1
          effect.batch([
            skred.load_track_wave(left_v, right_v, ""),
            skred.send_command(skred.format_voice_run(left_v, right_v, False)),
          ])
        }
        _, _ -> effect.none()
      }

      let status = case selected_file {
        Some(f) -> "Assigned " <> f.name <> " to Track " <> int.to_string(track_id + 1)
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
            list.map(model.tracks, fn(t) {
              case t.id == track_id {
                True -> Track(..t, audio_file: sample, playing: False)
                False -> t
              }
            })

          let track_opt = list.find(model.tracks, fn(t) { t.id == track_id })
          let eff = case sample, track_opt {
            Some(f), Ok(t) -> {
              let left_v = track_id * 2
              let right_v = track_id * 2 + 1
              let wave_eff = skred.load_track_wave(left_v, right_v, f.path)
              let ctrl_cmd =
                skred.format_voice_volume(left_v, right_v, t.volume)
                <> ";"
                <> skred.format_voice_speed(left_v, right_v, t.speed)
                <> ";"
                <> skred.format_voice_mute(left_v, right_v, t.muted)
                <> ";"
                <> skred.format_voice_direction(left_v, right_v, t.reversed)
                <> ";"
                <> skred.format_voice_run(left_v, right_v, False)
              effect.batch([wave_eff, skred.send_command(ctrl_cmd)])
            }
            _, _ -> effect.none()
          }

          let status = case sample {
            Some(f) -> "Randomized: assigned " <> f.name <> " to Track " <> int.to_string(track_id + 1)
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
      let mut_track = list.find(model.tracks, fn(t) { t.id == track_id })
      case mut_track {
        Ok(t) -> {
          let new_play = !t.playing
          let updated_tracks =
            list.map(model.tracks, fn(tr) {
              case tr.id == track_id {
                True -> Track(..tr, playing: new_play)
                False -> tr
              }
            })
          let all_now_playing = list.all(updated_tracks, fn(tr) { tr.playing })
          // When starting, make sure volume and mute states are restored
          let cmd = case new_play {
            True ->
              skred.format_voice_volume(t.left_voice, t.right_voice, t.volume)
              <> ";"
              <> skred.format_voice_mute(t.left_voice, t.right_voice, t.muted)
              <> ";"
              <> skred.format_voice_direction(t.left_voice, t.right_voice, t.reversed)
              <> ";"
              <> skred.format_voice_run(t.left_voice, t.right_voice, True)
            False ->
              skred.format_voice_run(t.left_voice, t.right_voice, False)
          }
          #(
            Model(..model, tracks: updated_tracks, all_playing: all_now_playing),
            skred.send_command(cmd),
          )
        }
        Error(_) -> #(model, effect.none())
      }
    }

    types.SetTrackVolume(track_id, vol) -> {
      let clamped = clamp_float(vol, -60.0, 12.0)
      let mut_track = list.find(model.tracks, fn(t) { t.id == track_id })
      let updated_tracks =
        list.map(model.tracks, fn(t) {
          case t.id == track_id {
            True -> Track(..t, volume: clamped)
            False -> t
          }
        })
      let eff = case mut_track {
        Ok(t) -> {
          let cmd = skred.format_voice_volume(t.left_voice, t.right_voice, clamped)
          skred.send_command(cmd)
        }
        Error(_) -> effect.none()
      }
      #(Model(..model, tracks: updated_tracks), eff)
    }

    types.SetTrackSpeed(track_id, midi_pitch) -> {
      let clamped = clamp_float(midi_pitch, 0.0, 127.0)
      let mut_track = list.find(model.tracks, fn(t) { t.id == track_id })
      let updated_tracks =
        list.map(model.tracks, fn(t) {
          case t.id == track_id {
            True -> Track(..t, speed: clamped)
            False -> t
          }
        })
      let eff = case mut_track {
        Ok(t) -> {
          let cmd = skred.format_voice_speed(t.left_voice, t.right_voice, clamped)
          skred.send_command(cmd)
        }
        Error(_) -> effect.none()
      }
      #(Model(..model, tracks: updated_tracks), eff)
    }

    types.StepTrackSpeed(track_id, semitone_offset) -> {
      let mut_track = list.find(model.tracks, fn(t) { t.id == track_id })
      case mut_track {
        Ok(t) -> {
          let new_pitch = case semitone_offset == 0.0 {
            True -> 69.0
            False -> clamp_float(t.speed +. semitone_offset, 0.0, 127.0)
          }
          let updated_tracks =
            list.map(model.tracks, fn(tr) {
              case tr.id == track_id {
                True -> Track(..tr, speed: new_pitch)
                False -> tr
              }
            })
          let cmd = skred.format_voice_speed(t.left_voice, t.right_voice, new_pitch)
          #(Model(..model, tracks: updated_tracks), skred.send_command(cmd))
        }
        Error(_) -> #(model, effect.none())
      }
    }

    types.ToggleTrackMute(track_id) -> {
      let mut_track = list.find(model.tracks, fn(t) { t.id == track_id })
      case mut_track {
        Ok(t) -> {
          let new_mute = !t.muted
          let updated_tracks =
            list.map(model.tracks, fn(tr) {
              case tr.id == track_id {
                True -> Track(..tr, muted: new_mute)
                False -> tr
              }
            })
          let cmd = skred.format_voice_mute(t.left_voice, t.right_voice, new_mute)
          #(Model(..model, tracks: updated_tracks), skred.send_command(cmd))
        }
        Error(_) -> #(model, effect.none())
      }
    }

    types.ToggleTrackDirection(track_id) -> {
      let mut_track = list.find(model.tracks, fn(t) { t.id == track_id })
      case mut_track {
        Ok(t) -> {
          let new_rev = !t.reversed
          let updated_tracks =
            list.map(model.tracks, fn(tr) {
              case tr.id == track_id {
                True -> Track(..tr, reversed: new_rev)
                False -> tr
              }
            })
          let cmd = skred.format_voice_flip(t.left_voice, t.right_voice)
          let status = case new_rev {
            True -> "Track " <> int.to_string(track_id + 1) <> " flipped to reverse (b1)"
            False -> "Track " <> int.to_string(track_id + 1) <> " set to forward (b0)"
          }
          #(
            Model(..model, tracks: updated_tracks, status_message: status),
            skred.send_command(cmd),
          )
        }
        Error(_) -> #(model, effect.none())
      }
    }

    types.ToggleTrackMinimize(track_id) -> {
      let updated_tracks =
        list.map(model.tracks, fn(t) {
          case t.id == track_id {
            True -> {
              let new_disp = case t.card_display {
                Normal -> Minimized
                Minimized -> Normal
              }
              Track(..t, card_display: new_disp)
            }
            False -> t
          }
        })
      #(Model(..model, tracks: updated_tracks), effect.none())
    }

    types.FloatTrackCard(track_id) -> {
      let next_z = model.next_z_index + 1
      let default_x = 100.0 +. int.to_float(track_id) *. 25.0
      let default_y = 70.0 +. int.to_float(track_id) *. 25.0

      let updated_tracks =
        list.map(model.tracks, fn(t) {
          case t.id == track_id {
            True -> Track(..t, card_mode: Floating(default_x, default_y, next_z))
            False -> t
          }
        })
      #(Model(..model, tracks: updated_tracks, next_z_index: next_z), effect.none())
    }

    types.DockTrackCard(track_id) -> {
      let updated_tracks =
        list.map(model.tracks, fn(t) {
          case t.id == track_id {
            True -> Track(..t, card_mode: Grid)
            False -> t
          }
        })
      #(Model(..model, tracks: updated_tracks), effect.none())
    }

    types.StartDragCard(track_id, card_x, card_y, mouse_x, mouse_y) -> {
      let next_z = model.next_z_index + 1
      let updated_tracks =
        list.map(model.tracks, fn(t) {
          case t.id == track_id {
            True ->
              case t.card_mode {
                Floating(x, y, _) -> Track(..t, card_mode: Floating(x, y, next_z))
                Grid -> t
              }
            False -> t
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
            list.map(model.tracks, fn(t) {
              case t.id == drag.track_id {
                True ->
                  case t.card_mode {
                    Floating(_, _, z) ->
                      Track(..t, card_mode: Floating(new_x, new_y, z))
                    Grid -> t
                  }
                False -> t
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

    // -----------------------------------------------------------------------
    // Master Operations
    // -----------------------------------------------------------------------
    types.PickDirectory -> {
      #(
        Model(..model, status_message: "Opening directory picker..."),
        skred.pick_directory_effect(),
      )
    }

    types.ToggleAllPlay -> {
      let any_playing = list.any(model.tracks, fn(t) { t.playing })
      let new_all_playing = !any_playing
      let updated_tracks =
        list.map(model.tracks, fn(t) { Track(..t, playing: new_all_playing) })
      let cmd = case new_all_playing {
        True ->
          list.map(model.tracks, fn(t) {
            skred.format_voice_volume(t.left_voice, t.right_voice, t.volume)
            <> ";"
            <> skred.format_voice_mute(t.left_voice, t.right_voice, t.muted)
            <> ";"
            <> skred.format_voice_direction(t.left_voice, t.right_voice, t.reversed)
            <> ";"
            <> "v" <> int.to_string(t.left_voice) <> "l1;v" <> int.to_string(t.right_voice) <> "l1"
          })
          |> string.join(";")
        False ->
          list.map(model.tracks, fn(t) {
            "v" <> int.to_string(t.left_voice) <> "l0;v" <> int.to_string(t.right_voice) <> "l0"
          })
          |> string.join(";")
      }
      let status = case new_all_playing {
        True -> "Started playback on all tracks"
        False -> "Stopped playback on all tracks"
      }
      #(
        Model(
          ..model,
          all_playing: new_all_playing,
          tracks: updated_tracks,
          status_message: status,
        ),
        skred.send_command(cmd),
      )
    }

    types.SetAllPlay(playing) -> {
      let updated_tracks =
        list.map(model.tracks, fn(t) { Track(..t, playing: playing) })
      let cmd = case playing {
        True ->
          list.map(model.tracks, fn(t) {
            skred.format_voice_volume(t.left_voice, t.right_voice, t.volume)
            <> ";"
            <> skred.format_voice_mute(t.left_voice, t.right_voice, t.muted)
            <> ";"
            <> skred.format_voice_direction(t.left_voice, t.right_voice, t.reversed)
            <> ";"
            <> "v" <> int.to_string(t.left_voice) <> "l1;v" <> int.to_string(t.right_voice) <> "l1"
          })
          |> string.join(";")
        False ->
          list.map(model.tracks, fn(t) {
            "v" <> int.to_string(t.left_voice) <> "l0;v" <> int.to_string(t.right_voice) <> "l0"
          })
          |> string.join(";")
      }
      let status = case playing {
        True -> "Started playback on all tracks"
        False -> "Stopped playback on all tracks"
      }
      #(
        Model(
          ..model,
          all_playing: playing,
          tracks: updated_tracks,
          status_message: status,
        ),
        skred.send_command(cmd),
      )
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
                  let wave_eff = skred.load_track_wave(t.left_voice, t.right_voice, f.path)
                  let ctrl_cmd =
                    skred.format_voice_volume(t.left_voice, t.right_voice, t.volume)
                    <> ";"
                    <> skred.format_voice_speed(t.left_voice, t.right_voice, t.speed)
                    <> ";"
                    <> skred.format_voice_mute(t.left_voice, t.right_voice, t.muted)
                    <> ";"
                    <> skred.format_voice_direction(t.left_voice, t.right_voice, t.reversed)
                    <> ";"
                    <> skred.format_voice_run(t.left_voice, t.right_voice, False)
                  effect.batch([wave_eff, skred.send_command(ctrl_cmd)])
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
      let cmd = skred.format_master_volume(clamped)
      #(Model(..model, master_volume: clamped), skred.send_command(cmd))
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
      #(Model(..model, show_library_modal: !model.show_library_modal), effect.none())
    }

    types.ToggleTheme -> {
      let next_theme = case model.theme {
        types.Dark -> types.Light
        types.Light -> types.Dark
      }
      #(Model(..model, theme: next_theme), effect.none())
    }

    types.RemoveAudioFile(file_id) -> {
      let updated_library = list.filter(model.library, fn(f) { f.id != file_id })
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
          skred.send_command(
            skred.format_voice_run(t.left_voice, t.right_voice, False)
            <> ";"
            <> "v" <> int.to_string(t.left_voice) <> "w82;"
            <> "v" <> int.to_string(t.right_voice) <> "w82",
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
      let stop_all = skred.send_command("*l0;S-1;V0")
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

    // -----------------------------------------------------------------------
    // Skred Console / REPL (Ctrl-~)
    // -----------------------------------------------------------------------
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
          let history = [cmd, ..list.filter(model.command_history, fn(c) { c != cmd })]
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
            Model(
              ..model,
              history_index: next_idx,
              console_input: picked_cmd,
            ),
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
            Model(
              ..model,
              history_index: next_idx,
              console_input: picked_cmd,
            ),
            effect.none(),
          )
        }
        False -> {
          #(
            Model(..model, history_index: -1, console_input: ""),
            effect.none(),
          )
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
          #(
            Model(..model, console_x: new_x, console_y: new_y),
            effect.none(),
          )
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

    types.SetMobileActiveTrack(idx) -> {
      #(Model(..model, mobile_active_track: idx), effect.none())
    }

    // -----------------------------------------------------------------------
    // FFI Callbacks
    // -----------------------------------------------------------------------
    types.FilesLoaded(new_files) -> {
      let count = list.length(new_files)
      let merged = list.append(model.library, new_files)
      #(
        Model(
          ..model,
          library: merged,
          status_message: "Loaded " <> int.to_string(count) <> " audio files into library.",
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
                Some(f) -> Ok(skred.load_track_wave(t.left_voice, t.right_voice, f.path))
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
  }
}

pub fn main() {
  let app = lustre.application(init, update, ui.view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
