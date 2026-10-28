//// # Skode & ANDS Audio Command Language AST
////
//// This module provides an Abstract Syntax Tree (AST) and lowering compiler for
//// **Skode**, the live musical and DSP command language driving the **Skred** audio engine.
////
//// The implementation is modeled directly after Skred's C source (`ands.c` and `skode.c`).
////
//// ## Two-Layer Architecture
////
//// 1. **Low-Level ANDS Grammar Layer (`Element`, `Value`, `Chunk`, `Script`)**:
////    Faithfully models the concrete syntactic tokens of the ANDS tokenizer:
////    - Atoms (`v0`, `a-6.0`, `f440`, `DL`, `*R`)
////    - Bracketed string literals (`[path/to/wave.wav]`)
////    - Parenthesized numeric data arrays (`( 60 64 67 )`)
////    - In-band line comments (`# comment`)
////    - Named text macro definitions (`[name] : body ;`)
////    - Variables (`$0` to `$127`) and live audio streams (`&0` to `&127`)
////    - Return registers (`@0` to `@9`) and macro argument placeholders (`$$0` to `$$7`)
////    - Schedulable deferred execution chunks (`+0.25 ...;` or `~4 ...;`)
////
//// 2. **High-Level Domain Layer (`SkodeCommand`)**:
////    Provides type-safe musical constructors (`stereo_volume`, `stereo_speed`, `track_control`,
////    `define_macro`, `call_macro`) so the frontend and audio controllers never deal with
////    error-prone string concatenation.
////

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// ---------------------------------------------------------------------------
// ANDS Grammar AST (Low-Level Syntax Layer)
// ---------------------------------------------------------------------------

/// Values that can accumulate on the ANDS argument stack or inside arrays.
pub type Value {
  /// Literal floating-point number (e.g. 440.0, -6.0)
  Num(Float)
  /// Musical tie sentinel (represented as '.' or '_' in ANDS)
  Tie
  /// Musical rest sentinel (represented as '-' in ANDS)
  Rest
  /// Variable register reference ($0 to $127)
  Variable(Int)
  /// Stream modulation reference (&0 to &127)
  Stream(Int)
  /// Return value register reference (@0 to @9)
  ReturnRef(Int)
  /// Macro argument placeholder reference ($$0 to $$9)
  MacroArg(Int)
}

/// Timing mode for ANDS deferral chunks ('+' or '~')
pub type DeferMode {
  /// Relative time in seconds: +0.25
  RelativeSeconds
  /// Tempo-relative duration in ticks/steps: ~4
  TempoTicks
}

/// Fundamental syntactic element in the ANDS stream.
pub type Element {
  /// Atom word with zero or more preceding/following arguments (e.g. "v0", "a-6.0", "eR")
  Atom(name: String, args: List(Value))
  /// Bracketed string literal: [path/to/wave.wav]
  Str(String)
  /// Parenthesized numeric data array: (10.0 20.0 30.0) or (60 - 64 .)
  Arr(List(Value))
  /// In-band comment line or chunk: # comment text
  Comment(String)
  /// Schedulable deferred chunk (+0.5 ...; or ~2 ...;)
  Defer(mode: DeferMode, amount: Float, elements: List(Element))
  /// Named text macro definition: [name] : elements ;
  MacroDef(name: String, elements: List(Element))
  /// Macro argument placeholder: $$0, $$1, etc.
  MacroArgRef(Int)
  /// Variable register read: $0, $1, etc.
  VarRefElement(Int)
  /// Stream modulation reference: &0, &1, etc.
  StreamRefElement(Int)
}

/// A semicolon-delimited execution chunk in ANDS.
pub type Chunk {
  Chunk(List(Element))
}

/// A full Skode script composed of chunks.
pub type Script {
  Script(List(Chunk))
}

// ---------------------------------------------------------------------------
// Semantic Domain AST (High-Level Music / DSP Layer)
// ---------------------------------------------------------------------------

pub type VoiceTarget {
  Voice(Int)
  Stereo(left: Int, right: Int)
  AllVoices
}

pub type Direction {
  Forward
  Reverse
  PingPong
}

pub type MacroOp {
  /// Repeat macro by seconds: eR index, count, seconds [, tag]
  RepeatSeconds(index: Int, count: Int, seconds: Float, tag: Option(Int))
  /// Repeat macro by tempo beats: eRR index, count, beats [, tag]
  RepeatBeats(index: Int, count: Int, beats: Float, tag: Option(Int))
  /// Compile and inline macro buffer: e! index
  ExpandAndQueue(index: Int)
  /// Inspect macro buffers: e? [index]
  QueryBuffer(index: Option(Int))
  /// Copy string into macro buffer: [body] e> index
  StoreBuffer(index: Int, body: String)
  /// Named ANDS text macro definition: [name] : body ;
  DefineNamed(name: String, body: SkodeCommand)
  /// Call named macro with arguments: name arg0 arg1 ...
  CallNamed(name: String, args: List(Value))
}

pub type SkodeCommand {
  // Voice & Target
  SetVoice(Int)
  SetStereo(left: Int, right: Int)
  ResetVoices(target: VoiceTarget)
  FlipVoice(target: VoiceTarget)

  // Audio & DSP Parameters
  SetAmp(db: Float)
  SetFrequency(hz: Float)
  SetMidiPitch(note: Float, cents: Option(Float))
  SetPan(pan: Float)
  SetMute(Bool)
  SetGate(velocity: Float)
  Trigger

  // Wave / Sampler Parameters
  SetWave(wave_id: Int)
  SetWaveDirection(Direction)
  SetWaveLoop(Bool)
  SetWaveLoopCount(Int)

  // High-Level Macro / 'e' words & Named Macros
  Macro(MacroOp)
  DefineMacro(name: String, body: SkodeCommand)
  CallMacro(name: String, args: List(Value))
  MacroArgPlaceholder(Int)
  VariableRef(Int)
  StreamTarget(Int)

  // Master & VFS
  SetMasterVolume(db: Float)
  LoadWaveFile(path: String)
  StopAll

  // Raw & Structured Chunks
  Raw(String)
  DataArray(List(Value))
  StringLiteral(String)
  LineComment(String)

  // Timing & Scheduling
  DelayRelative(seconds: Float, cmd: SkodeCommand)
  DelayTicks(ticks: Float, cmd: SkodeCommand)

  // Compound Batch
  Bundle(List(SkodeCommand))
}

// ---------------------------------------------------------------------------
// Serialization / Compiler Functions
// ---------------------------------------------------------------------------

fn clean_float(f: Float) -> String {
  string.replace(float.to_string(f), "+", "")
}

/// Formats an argument value (`Num`, `Tie`, `Rest`, `Variable`, `Stream`, `ReturnRef`, `MacroArg`) to its ANDS string form.
pub fn value_to_string(v: Value) -> String {
  case v {
    Num(f) -> clean_float(f)
    Tie -> "."
    Rest -> "-"
    Variable(idx) -> "$" <> int.to_string(idx)
    Stream(idx) -> "&" <> int.to_string(idx)
    ReturnRef(idx) -> "@" <> int.to_string(idx)
    MacroArg(idx) -> "$$" <> int.to_string(idx)
  }
}

/// Serializes an ANDS grammar `Element` to its concrete token representation.
pub fn element_to_string(el: Element) -> String {
  case el {
    Atom(name, []) -> name
    Atom(name, args) -> {
      let args_str = list.map(args, value_to_string) |> string.join(" ")
      name <> args_str
    }
    Str(s) -> "[" <> s <> "]"
    Arr(vals) -> {
      let inner = list.map(vals, value_to_string) |> string.join(" ")
      "(" <> inner <> ")"
    }
    Comment(c) -> "# " <> c
    Defer(mode, amt, elements) -> {
      let sigil = case mode {
        RelativeSeconds -> "+"
        TempoTicks -> "~"
      }
      let inner = list.map(elements, element_to_string) |> string.join(" ")
      sigil <> clean_float(amt) <> " " <> inner
    }
    MacroDef(name, elements) -> {
      let body = list.map(elements, element_to_string) |> string.join(" ")
      "[" <> name <> "] : " <> body <> " ;"
    }
    MacroArgRef(idx) -> "$$" <> int.to_string(idx)
    VarRefElement(idx) -> "$" <> int.to_string(idx)
    StreamRefElement(idx) -> "&" <> int.to_string(idx)
  }
}

/// Serializes an execution chunk (space-delimited elements).
pub fn chunk_to_string(chunk: Chunk) -> String {
  let Chunk(elements) = chunk
  list.map(elements, element_to_string) |> string.join(" ")
}

/// Serializes a full script (semicolon-delimited chunks).
pub fn script_to_string(script: Script) -> String {
  let Script(chunks) = script
  list.map(chunks, chunk_to_string) |> string.join("; ")
}

// ---------------------------------------------------------------------------
// Lowering: Domain AST -> Skode Command String
// ---------------------------------------------------------------------------

/// Lowers a high-level `SkodeCommand` domain node into executable Skred command text.
pub fn command_to_string(cmd: SkodeCommand) -> String {
  case cmd {
    SetVoice(v) -> "v" <> int.to_string(v)
    SetStereo(l, r) -> "v" <> int.to_string(l) <> "; v" <> int.to_string(r)
    ResetVoices(AllVoices) -> "S-1"
    ResetVoices(Voice(v)) -> "v" <> int.to_string(v) <> " S"
    ResetVoices(Stereo(l, r)) ->
      "v" <> int.to_string(l) <> " S; v" <> int.to_string(r) <> " S"

    SetAmp(db) -> "a" <> clean_float(db)
    SetFrequency(hz) -> "f" <> clean_float(hz)
    SetMidiPitch(note, None) -> "n" <> clean_float(note)
    SetMidiPitch(note, Some(cents)) ->
      "n" <> clean_float(note) <> "," <> clean_float(cents)
    SetPan(p) -> "p" <> clean_float(p)
    SetMute(True) -> "m1"
    SetMute(False) -> "m0"
    SetGate(vel) -> "l" <> clean_float(vel)
    Trigger -> "T"

    SetWave(w) -> "w" <> int.to_string(w)
    SetWaveDirection(Forward) -> "b0"
    SetWaveDirection(Reverse) -> "b1"
    SetWaveDirection(PingPong) -> "b2"
    SetWaveLoop(True) -> "B1"
    SetWaveLoop(False) -> "B0"
    SetWaveLoopCount(count) -> "BC" <> int.to_string(count)

    Macro(RepeatSeconds(idx, count, sec, None)) ->
      int.to_string(idx)
      <> ","
      <> int.to_string(count)
      <> ","
      <> clean_float(sec)
      <> " eR"
    Macro(RepeatSeconds(idx, count, sec, Some(tag))) ->
      int.to_string(idx)
      <> ","
      <> int.to_string(count)
      <> ","
      <> clean_float(sec)
      <> ","
      <> int.to_string(tag)
      <> " eR"
    Macro(RepeatBeats(idx, count, beats, None)) ->
      int.to_string(idx)
      <> ","
      <> int.to_string(count)
      <> ","
      <> clean_float(beats)
      <> " eRR"
    Macro(RepeatBeats(idx, count, beats, Some(tag))) ->
      int.to_string(idx)
      <> ","
      <> int.to_string(count)
      <> ","
      <> clean_float(beats)
      <> ","
      <> int.to_string(tag)
      <> " eRR"
    Macro(ExpandAndQueue(idx)) -> int.to_string(idx) <> " e!"
    Macro(QueryBuffer(None)) -> "e?"
    Macro(QueryBuffer(Some(idx))) -> int.to_string(idx) <> " e?"
    Macro(StoreBuffer(idx, body)) ->
      "[" <> body <> "] " <> int.to_string(idx) <> " e>"
    Macro(DefineNamed(name, body)) ->
      "[" <> name <> "] : " <> command_to_string(body) <> " ;"
    Macro(CallNamed(name, [])) -> name
    Macro(CallNamed(name, args)) ->
      name <> " " <> { list.map(args, value_to_string) |> string.join(" ") }

    DefineMacro(name, body) ->
      "[" <> name <> "] : " <> command_to_string(body) <> " ;"
    CallMacro(name, []) -> name
    CallMacro(name, args) ->
      name <> " " <> { list.map(args, value_to_string) |> string.join(" ") }
    MacroArgPlaceholder(idx) -> "$$" <> int.to_string(idx)
    VariableRef(idx) -> "$" <> int.to_string(idx)
    StreamTarget(idx) -> "&" <> int.to_string(idx)

    SetMasterVolume(db) -> ";V" <> clean_float(db) <> ";"
    LoadWaveFile(path) -> "[" <> path <> "] /w"
    StopAll -> "*l0;S-1;V0"
    FlipVoice(AllVoices) -> "*b"
    FlipVoice(Voice(v)) -> "v" <> int.to_string(v) <> "b"
    FlipVoice(Stereo(l, r)) ->
      "v" <> int.to_string(l) <> "b; v" <> int.to_string(r) <> "b;"
    Raw(s) -> s

    DataArray(vals) -> {
      let inner = list.map(vals, value_to_string) |> string.join(" ")
      "(" <> inner <> ")"
    }
    StringLiteral(str) -> "[" <> str <> "]"
    LineComment(c) -> "# " <> c

    DelayRelative(sec, c) ->
      "+" <> clean_float(sec) <> " " <> command_to_string(c)
    DelayTicks(t, c) -> "~" <> clean_float(t) <> " " <> command_to_string(c)

    Bundle(commands) ->
      list.map(commands, command_to_string) |> string.join("; ")
  }
}

// ---------------------------------------------------------------------------
// Stereo & High-Level Domain Constructors
// ---------------------------------------------------------------------------

/// Builds a stereo amplitude volume command: "v{left}a{vol};v{right}a{vol}".
pub fn stereo_volume(left: Int, right: Int, volume: Float) -> SkodeCommand {
  Raw(
    "v"
    <> int.to_string(left)
    <> "a"
    <> clean_float(volume)
    <> ";v"
    <> int.to_string(right)
    <> "a"
    <> clean_float(volume),
  )
}

/// Builds a stereo playback speed command: "v{left}n{midi};v{right}n{midi}".
pub fn stereo_speed(left: Int, right: Int, midi_pitch: Float) -> SkodeCommand {
  Raw(
    "v"
    <> int.to_string(left)
    <> "n"
    <> clean_float(midi_pitch)
    <> ";v"
    <> int.to_string(right)
    <> "n"
    <> clean_float(midi_pitch),
  )
}

/// Builds a stereo start/stop running command: "v{left}l{0|1};v{right}l{0|1}".
pub fn stereo_run(left: Int, right: Int, running: Bool) -> SkodeCommand {
  let flag = case running {
    True -> "1"
    False -> "0"
  }
  Raw(
    "v"
    <> int.to_string(left)
    <> "l"
    <> flag
    <> ";v"
    <> int.to_string(right)
    <> "l"
    <> flag,
  )
}

/// Builds a stereo mute command: "v{left}m{0|1};v{right}m{0|1}".
pub fn stereo_mute(left: Int, right: Int, muted: Bool) -> SkodeCommand {
  let flag = case muted {
    True -> "1"
    False -> "0"
  }
  Raw(
    "v"
    <> int.to_string(left)
    <> "m"
    <> flag
    <> ";v"
    <> int.to_string(right)
    <> "m"
    <> flag,
  )
}

/// Builds a stereo direction command: "v{left}b{0|1};v{right}b{0|1}".
pub fn stereo_direction(left: Int, right: Int, reversed: Bool) -> SkodeCommand {
  let flag = case reversed {
    True -> "1"
    False -> "0"
  }
  Raw(
    "v"
    <> int.to_string(left)
    <> "b"
    <> flag
    <> ";v"
    <> int.to_string(right)
    <> "b"
    <> flag,
  )
}

/// Builds a stereo direction toggle command: "v{left}b; v{right}b;".
pub fn stereo_flip(left: Int, right: Int) -> SkodeCommand {
  Raw("v" <> int.to_string(left) <> "b; v" <> int.to_string(right) <> "b;")
}

/// Composes all parameters for a stereo voice pair into a single batch command.
pub fn track_control(
  left_voice: Int,
  right_voice: Int,
  volume: Float,
  speed: Float,
  muted: Bool,
  reversed: Bool,
  run: Bool,
) -> SkodeCommand {
  Raw(
    command_to_string(stereo_volume(left_voice, right_voice, volume))
    <> ";"
    <> command_to_string(stereo_speed(left_voice, right_voice, speed))
    <> ";"
    <> command_to_string(stereo_mute(left_voice, right_voice, muted))
    <> ";"
    <> command_to_string(stereo_direction(left_voice, right_voice, reversed))
    <> ";"
    <> command_to_string(stereo_run(left_voice, right_voice, run)),
  )
}

/// Constructs a named ANDS macro definition: `[name] : body ;`.
pub fn define_macro(name: String, body: SkodeCommand) -> SkodeCommand {
  DefineMacro(name, body)
}

/// Constructs a named ANDS macro call with arguments: `name arg0 arg1 ...`.
pub fn call_macro(name: String, args: List(Value)) -> SkodeCommand {
  CallMacro(name, args)
}

/// Represents an argument placeholder inside a macro body: `$$0` .. `$$7`.
pub fn macro_arg(idx: Int) -> SkodeCommand {
  MacroArgPlaceholder(idx)
}

/// References an ANDS variable register: `$0` .. `$127`.
pub fn variable(idx: Int) -> SkodeCommand {
  VariableRef(idx)
}

/// References an ANDS live modulation stream target: `&0` .. `&127`.
pub fn stream(idx: Int) -> SkodeCommand {
  StreamTarget(idx)
}

/// Constructs an `n>d` note-to-data conversion command that populates the active
/// data buffer with parsed note numbers, slurs, ties, and rests: `[ notation ] n>d`.
pub fn note_to_data(notation: String) -> SkodeCommand {
  Raw("[ " <> string.trim(notation) <> " ] n>d")
}

/// Constructs a note stream assignment command via `n>d /SS`:
/// `[ notation ] n>d /SS {stream_id}`.
pub fn note_stream(notation: String, stream_id: Int) -> SkodeCommand {
  Raw(
    "[ " <> string.trim(notation) <> " ] n>d /SS " <> int.to_string(stream_id),
  )
}

/// Constructs a k-synth array evaluation command: `[ code ] ks`.
pub fn ksynth_eval(code: String) -> SkodeCommand {
  Raw("[ " <> string.trim(code) <> " ] ks")
}

/// Evaluates k-synth code and loads the resulting vector into Skred's data buffer:
/// `[ code ] ks k>d`.
pub fn ksynth_to_data(code: String) -> SkodeCommand {
  Raw("[ " <> string.trim(code) <> " ] ks k>d")
}

/// Evaluates k-synth code and renders the resulting vector directly into a playable wavetable slot:
/// `[ code ] ks {wave_slot} k>w`.
pub fn ksynth_to_wavetable(code: String, wave_slot: Int) -> SkodeCommand {
  Raw(
    "[ " <> string.trim(code) <> " ] ks " <> int.to_string(wave_slot) <> " k>w",
  )
}

// ---------------------------------------------------------------------------
// Parser: Skode & ANDS Text -> AST
// ---------------------------------------------------------------------------

/// Error encountered during Skode / ANDS tokenization and parsing.
pub type ParseError {
  ParseError(message: String, position: Int)
}

fn is_digit(c: String) -> Bool {
  case c {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

fn is_atom_char(c: String) -> Bool {
  case c {
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z"
    | "A"
    | "B"
    | "C"
    | "D"
    | "E"
    | "F"
    | "G"
    | "H"
    | "I"
    | "J"
    | "K"
    | "L"
    | "M"
    | "N"
    | "O"
    | "P"
    | "Q"
    | "R"
    | "S"
    | "T"
    | "U"
    | "V"
    | "W"
    | "X"
    | "Y"
    | "Z" -> True
    "!"
    | "%"
    | "^"
    | "*"
    | "="
    | ":"
    | "\""
    | "'"
    | "<"
    | ">"
    | "?"
    | "/"
    | "\\"
    | "|"
    | "`" -> True
    _ -> False
  }
}

fn is_number_char(c: String) -> Bool {
  is_digit(c) || c == "." || c == "e" || c == "E"
}

fn skip_separators(chars: List(String), pos: Int) -> #(List(String), Int) {
  case chars {
    [" ", ..rest] | ["\t", ..rest] | [",", ..rest] ->
      skip_separators(rest, pos + 1)
    _ -> #(chars, pos)
  }
}

fn skip_tie_chars(chars: List(String), pos: Int) -> #(List(String), Int) {
  case chars {
    [".", ..rest] | ["_", ..rest] -> skip_tie_chars(rest, pos + 1)
    _ -> #(chars, pos)
  }
}

fn skip_rest_chars(chars: List(String), pos: Int) -> #(List(String), Int) {
  case chars {
    ["-", ..rest] -> skip_rest_chars(rest, pos + 1)
    _ -> #(chars, pos)
  }
}

fn parse_number_literal(s: String) -> Result(Float, Nil) {
  let normalized = case s {
    "." | "-." -> ""
    "-." <> rest -> "-0." <> rest
    "." <> rest -> "0." <> rest
    _ -> s
  }
  case float.parse(normalized) {
    Ok(f) -> Ok(f)
    Error(_) -> {
      case int.parse(normalized) {
        Ok(i) -> Ok(int.to_float(i))
        Error(_) -> Error(Nil)
      }
    }
  }
}

fn read_digits_int(
  chars: List(String),
  pos: Int,
  acc: List(String),
) -> #(List(String), Int, Int) {
  case chars {
    [c, ..rest] -> {
      case is_digit(c) {
        True -> read_digits_int(rest, pos + 1, [c, ..acc])
        False -> {
          let s = string.join(list.reverse(acc), "")
          let n = result.unwrap(int.parse(s), 0)
          #(chars, pos, n)
        }
      }
    }
    [] -> {
      let s = string.join(list.reverse(acc), "")
      let n = result.unwrap(int.parse(s), 0)
      #(chars, pos, n)
    }
  }
}

fn read_number(
  chars: List(String),
  pos: Int,
  acc: List(String),
) -> Result(#(List(String), Int, Float), ParseError) {
  case chars {
    [c, ..rest] -> {
      case is_number_char(c) {
        True -> read_number(rest, pos + 1, [c, ..acc])
        False -> {
          let s = string.join(list.reverse(acc), "")
          case parse_number_literal(s) {
            Ok(f) -> Ok(#(chars, pos, f))
            Error(_) -> Error(ParseError("Invalid number format: " <> s, pos))
          }
        }
      }
    }
    [] -> {
      let s = string.join(list.reverse(acc), "")
      case parse_number_literal(s) {
        Ok(f) -> Ok(#(chars, pos, f))
        Error(_) -> Error(ParseError("Invalid number format: " <> s, pos))
      }
    }
  }
}

fn read_bracketed(
  chars: List(String),
  pos: Int,
  acc: List(String),
) -> Result(#(List(String), Int, String), ParseError) {
  case chars {
    ["]", ..rest] -> Ok(#(rest, pos + 1, string.join(list.reverse(acc), "")))
    [c, ..rest] -> read_bracketed(rest, pos + 1, [c, ..acc])
    [] -> Error(ParseError("Unterminated string literal: missing ']'", pos))
  }
}

fn read_comment(
  chars: List(String),
  pos: Int,
  acc: List(String),
) -> #(List(String), Int, String) {
  case chars {
    ["\n", ..] | ["\r", ..] | [";", ..] -> #(
      chars,
      pos,
      string.trim(string.join(list.reverse(acc), "")),
    )
    [c, ..rest] -> read_comment(rest, pos + 1, [c, ..acc])
    [] -> #(chars, pos, string.trim(string.join(list.reverse(acc), "")))
  }
}

fn read_array_values(
  chars: List(String),
  pos: Int,
  acc: List(Value),
) -> Result(#(List(String), Int, List(Value)), ParseError) {
  let #(clean_chars, next_pos) = skip_separators(chars, pos)
  case clean_chars {
    [")", ..rest] -> Ok(#(rest, next_pos + 1, list.reverse(acc)))
    [] -> Error(ParseError("Unterminated data array: missing ')'", next_pos))
    ["$", "$", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
    -> {
      let #(r2, p2, idx) = read_digits_int([c, ..rest], next_pos + 2, [])
      read_array_values(r2, p2, [MacroArg(idx), ..acc])
    }
    ["$", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
    -> {
      let #(r2, p2, idx) = read_digits_int([c, ..rest], next_pos + 1, [])
      read_array_values(r2, p2, [Variable(idx), ..acc])
    }
    ["&", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
    -> {
      let #(r2, p2, idx) = read_digits_int([c, ..rest], next_pos + 1, [])
      read_array_values(r2, p2, [Stream(idx), ..acc])
    }
    ["@", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
    -> {
      let #(r2, p2, idx) = read_digits_int([c, ..rest], next_pos + 1, [])
      read_array_values(r2, p2, [ReturnRef(idx), ..acc])
    }
    [".", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
    -> {
      use #(r2, p2, f) <- result.try(
        read_number([c, ..rest], next_pos + 1, ["."]),
      )
      read_array_values(r2, p2, [Num(f), ..acc])
    }
    [".", ..rest] | ["_", ..rest] -> {
      let #(r2, p2) = skip_tie_chars(rest, next_pos + 1)
      read_array_values(r2, p2, [Tie, ..acc])
    }
    ["-", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
      || c == "."
    -> {
      use #(r2, p2, f) <- result.try(
        read_number([c, ..rest], next_pos + 1, ["-"]),
      )
      read_array_values(r2, p2, [Num(f), ..acc])
    }
    ["-", ..rest] -> {
      let #(r2, p2) = skip_rest_chars(rest, next_pos + 1)
      read_array_values(r2, p2, [Rest, ..acc])
    }
    ["e", ..rest] -> {
      read_array_values(rest, next_pos + 1, [Rest, ..acc])
    }
    [c, ..rest] -> {
      case is_digit(c) {
        True -> {
          use #(r2, p2, f) <- result.try(read_number(rest, next_pos + 1, [c]))
          read_array_values(r2, p2, [Num(f), ..acc])
        }
        False ->
          Error(ParseError(
            "Unexpected character in data array: " <> c,
            next_pos,
          ))
      }
    }
  }
}

fn read_atom_name(
  chars: List(String),
  pos: Int,
  acc: List(String),
) -> #(List(String), Int, String) {
  case chars {
    [c, ..rest] -> {
      case is_atom_char(c) {
        True -> read_atom_name(rest, pos + 1, [c, ..acc])
        False -> #(chars, pos, string.join(list.reverse(acc), ""))
      }
    }
    [] -> #(chars, pos, string.join(list.reverse(acc), ""))
  }
}

fn read_atom_args(
  chars: List(String),
  pos: Int,
  acc: List(Value),
) -> #(List(String), Int, List(Value)) {
  case chars {
    // Immediate number without separator
    ["-", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
      || c == "."
    -> {
      case read_number([c, ..rest], pos + 1, ["-"]) {
        Ok(#(r2, p2, f)) -> read_atom_args_loop(r2, p2, [Num(f), ..acc])
        Error(_) -> #(chars, pos, list.reverse(acc))
      }
    }
    [".", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
    -> {
      case read_number([c, ..rest], pos + 1, ["."]) {
        Ok(#(r2, p2, f)) -> read_atom_args_loop(r2, p2, [Num(f), ..acc])
        Error(_) -> #(chars, pos, list.reverse(acc))
      }
    }
    [c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
    -> {
      case read_number(rest, pos + 1, [c]) {
        Ok(#(r2, p2, f)) -> read_atom_args_loop(r2, p2, [Num(f), ..acc])
        Error(_) -> #(chars, pos, list.reverse(acc))
      }
    }
    _ -> read_atom_args_loop(chars, pos, acc)
  }
}

fn read_atom_args_loop(
  chars: List(String),
  pos: Int,
  acc: List(Value),
) -> #(List(String), Int, List(Value)) {
  let #(clean, next_pos) = skip_separators(chars, pos)
  case clean {
    ["-", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
      || c == "."
    -> {
      case read_number([c, ..rest], next_pos + 1, ["-"]) {
        Ok(#(r2, p2, f)) -> read_atom_args_loop(r2, p2, [Num(f), ..acc])
        Error(_) -> #(clean, next_pos, list.reverse(acc))
      }
    }
    [".", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
    -> {
      case read_number([c, ..rest], next_pos + 1, ["."]) {
        Ok(#(r2, p2, f)) -> read_atom_args_loop(r2, p2, [Num(f), ..acc])
        Error(_) -> #(clean, next_pos, list.reverse(acc))
      }
    }
    [c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
    -> {
      case read_number(rest, next_pos + 1, [c]) {
        Ok(#(r2, p2, f)) -> read_atom_args_loop(r2, p2, [Num(f), ..acc])
        Error(_) -> #(clean, next_pos, list.reverse(acc))
      }
    }
    ["$", "$", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
    -> {
      let #(r2, p2, idx) = read_digits_int([c, ..rest], next_pos + 2, [])
      read_atom_args_loop(r2, p2, [MacroArg(idx), ..acc])
    }
    ["$", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
    -> {
      let #(r2, p2, idx) = read_digits_int([c, ..rest], next_pos + 1, [])
      read_atom_args_loop(r2, p2, [Variable(idx), ..acc])
    }
    ["&", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
    -> {
      let #(r2, p2, idx) = read_digits_int([c, ..rest], next_pos + 1, [])
      read_atom_args_loop(r2, p2, [Stream(idx), ..acc])
    }
    _ -> #(clean, next_pos, list.reverse(acc))
  }
}

fn parse_chunk_elements(
  chars: List(String),
  pos: Int,
  pending_args: List(Value),
  acc: List(Element),
) -> Result(#(List(String), Int, List(Element)), ParseError) {
  let #(clean, next_pos) = skip_separators(chars, pos)
  case clean {
    [] -> {
      let final_acc = case pending_args {
        [] -> acc
        _ -> [Atom("", list.reverse(pending_args)), ..acc]
      }
      Ok(#([], next_pos, list.reverse(final_acc)))
    }
    [";", ..rest] -> {
      let final_acc = case pending_args {
        [] -> acc
        _ -> [Atom("", list.reverse(pending_args)), ..acc]
      }
      Ok(#(rest, next_pos + 1, list.reverse(final_acc)))
    }
    ["\n", ..rest] | ["\r", ..rest] -> {
      let final_acc = case pending_args {
        [] -> acc
        _ -> [Atom("", list.reverse(pending_args)), ..acc]
      }
      Ok(#(rest, next_pos + 1, list.reverse(final_acc)))
    }
    ["#", ..rest] -> {
      let #(r2, p2, c) = read_comment(rest, next_pos + 1, [])
      parse_chunk_elements(r2, p2, pending_args, [Comment(c), ..acc])
    }
    ["[", ..rest] -> {
      use #(r2, p2, str_content) <- result.try(
        read_bracketed(rest, next_pos + 1, []),
      )
      let #(r3, p3) = skip_separators(r2, p2)
      case r3 {
        [":", ..r4] -> {
          // Macro definition: [name] : body ;
          use #(r5, p5, body_elements) <- result.try(
            parse_chunk_elements(r4, p3 + 1, [], []),
          )
          let macro_el = MacroDef(str_content, body_elements)
          Ok(#(r5, p5, list.reverse([macro_el, ..acc])))
        }
        _ -> {
          parse_chunk_elements(r2, p2, pending_args, [Str(str_content), ..acc])
        }
      }
    }
    ["(", ..rest] -> {
      use #(r2, p2, vals) <- result.try(
        read_array_values(rest, next_pos + 1, []),
      )
      parse_chunk_elements(r2, p2, pending_args, [Arr(vals), ..acc])
    }
    ["+", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
      || c == "."
    -> {
      use #(r2, p2, amt) <- result.try(
        read_number([c, ..rest], next_pos + 1, []),
      )
      use #(r3, p3, def_els) <- result.try(parse_chunk_elements(r2, p2, [], []))
      let defer_el = Defer(RelativeSeconds, amt, def_els)
      Ok(#(r3, p3, list.reverse([defer_el, ..acc])))
    }
    ["~", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
      || c == "."
    -> {
      use #(r2, p2, amt) <- result.try(
        read_number([c, ..rest], next_pos + 1, []),
      )
      use #(r3, p3, def_els) <- result.try(parse_chunk_elements(r2, p2, [], []))
      let defer_el = Defer(TempoTicks, amt, def_els)
      Ok(#(r3, p3, list.reverse([defer_el, ..acc])))
    }
    ["$", "$", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
    -> {
      let #(r2, p2, idx) = read_digits_int([c, ..rest], next_pos + 2, [])
      parse_chunk_elements(r2, p2, pending_args, [MacroArgRef(idx), ..acc])
    }
    ["$", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
    -> {
      let #(r2, p2, idx) = read_digits_int([c, ..rest], next_pos + 1, [])
      parse_chunk_elements(r2, p2, pending_args, [VarRefElement(idx), ..acc])
    }
    ["&", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
    -> {
      let #(r2, p2, idx) = read_digits_int([c, ..rest], next_pos + 1, [])
      parse_chunk_elements(r2, p2, pending_args, [StreamRefElement(idx), ..acc])
    }
    ["-", c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
      || c == "."
    -> {
      use #(r2, p2, f) <- result.try(
        read_number([c, ..rest], next_pos + 1, ["-"]),
      )
      parse_chunk_elements(r2, p2, [Num(f), ..pending_args], acc)
    }
    [c, ..rest]
      if c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
      || c == "."
    -> {
      use #(r2, p2, f) <- result.try(read_number(rest, next_pos + 1, [c]))
      parse_chunk_elements(r2, p2, [Num(f), ..pending_args], acc)
    }
    [c, ..rest] -> {
      case is_atom_char(c) {
        True -> {
          let #(r2, p2, atom_name) = read_atom_name(rest, next_pos + 1, [c])
          let #(r3, p3, following_args) = read_atom_args(r2, p2, [])
          let all_args = list.append(list.reverse(pending_args), following_args)
          let element = Atom(atom_name, all_args)
          parse_chunk_elements(r3, p3, [], [element, ..acc])
        }
        False -> Error(ParseError("Unexpected character: " <> c, next_pos))
      }
    }
  }
}

fn parse_script_loop(
  chars: List(String),
  pos: Int,
  acc: List(Chunk),
) -> Result(Script, ParseError) {
  let #(clean, next_pos) = skip_separators(chars, pos)
  case clean {
    [] -> Ok(Script(list.reverse(acc)))
    [";", ..rest] | ["\n", ..rest] | ["\r", ..rest] ->
      parse_script_loop(rest, next_pos + 1, acc)
    _ -> {
      use #(remaining, end_pos, elements) <- result.try(
        parse_chunk_elements(clean, next_pos, [], []),
      )
      let new_acc = case elements {
        [] -> acc
        _ -> [Chunk(elements), ..acc]
      }
      parse_script_loop(remaining, end_pos, new_acc)
    }
  }
}

/// Parses a full Skode / ANDS script (composed of semicolon- or newline-delimited chunks) into an AST `Script`.
pub fn parse(input: String) -> Result(Script, ParseError) {
  let chars = string.to_graphemes(input)
  parse_script_loop(chars, 0, [])
}

/// Parses a single execution chunk into an AST `Chunk`.
pub fn parse_chunk(input: String) -> Result(Chunk, ParseError) {
  use script <- result.try(parse(input))
  case script {
    Script([]) -> Ok(Chunk([]))
    Script([first, ..]) -> Ok(first)
  }
}

/// Parses a single syntactic element into an AST `Element`.
pub fn parse_element(input: String) -> Result(Element, ParseError) {
  use chunk <- result.try(parse_chunk(input))
  case chunk {
    Chunk([first, ..]) -> Ok(first)
    Chunk([]) -> Error(ParseError("No syntactic elements found", 0))
  }
}

fn single_element_to_command(el: Element) -> SkodeCommand {
  case el {
    Atom("v", [Num(v)]) -> SetVoice(float.round(v))
    Atom("a", [Num(db)]) -> SetAmp(db)
    Atom("f", [Num(hz)]) -> SetFrequency(hz)
    Atom("n", [Num(note)]) -> SetMidiPitch(note, None)
    Atom("n", [Num(note), Num(cents)]) -> SetMidiPitch(note, Some(cents))
    Atom("p", [Num(pan)]) -> SetPan(pan)
    Atom("m", [Num(m)]) -> SetMute(m != 0.0)
    Atom("l", [Num(vel)]) -> SetGate(vel)
    Atom("T", []) -> Trigger
    Atom("w", [Num(w)]) -> SetWave(float.round(w))
    Atom("b", [Num(0.0)]) -> SetWaveDirection(Forward)
    Atom("b", [Num(1.0)]) -> SetWaveDirection(Reverse)
    Atom("b", [Num(2.0)]) -> SetWaveDirection(PingPong)
    Atom("b", []) -> FlipVoice(AllVoices)
    Atom("B", [Num(0.0)]) -> SetWaveLoop(False)
    Atom("B", [Num(1.0)]) -> SetWaveLoop(True)
    Atom("BC", [Num(c)]) -> SetWaveLoopCount(float.round(c))
    Atom("*l", [Num(0.0)]) -> StopAll
    Atom("S", [Num(-1.0)]) -> ResetVoices(AllVoices)
    Atom("V", [Num(db)]) -> SetMasterVolume(db)
    MacroDef(name, body_elements) -> {
      let cmds = elements_to_commands(body_elements)
      let body = case cmds {
        [single] -> single
        _ -> Bundle(cmds)
      }
      DefineMacro(name, body)
    }
    Defer(RelativeSeconds, sec, deferred_elements) -> {
      let cmds = elements_to_commands(deferred_elements)
      let body = case cmds {
        [single] -> single
        _ -> Bundle(cmds)
      }
      DelayRelative(sec, body)
    }
    Defer(TempoTicks, ticks, deferred_elements) -> {
      let cmds = elements_to_commands(deferred_elements)
      let body = case cmds {
        [single] -> single
        _ -> Bundle(cmds)
      }
      DelayTicks(ticks, body)
    }
    Arr(vals) -> DataArray(vals)
    Str(s) -> StringLiteral(s)
    Comment(c) -> LineComment(c)
    VarRefElement(idx) -> VariableRef(idx)
    StreamRefElement(idx) -> StreamTarget(idx)
    MacroArgRef(idx) -> MacroArgPlaceholder(idx)
    _ -> Raw(element_to_string(el))
  }
}

fn elements_to_commands(elements: List(Element)) -> List(SkodeCommand) {
  case elements {
    [] -> []
    [Str(path), Atom("/w", _), ..rest] -> [
      LoadWaveFile(path),
      ..elements_to_commands(rest)
    ]
    [Str(path), Atom("/ls", _), ..rest] | [Str(path), Atom("/l", _), ..rest] -> [
      Raw("[" <> path <> "] /ls"),
      ..elements_to_commands(rest)
    ]
    [Str(code), Atom("/ks", _), ..rest] | [Str(code), Atom("ks", _), ..rest] -> [
      ksynth_eval(code),
      ..elements_to_commands(rest)
    ]
    [Str(notes), Atom("n>d", _), ..rest] -> [
      note_to_data(notes),
      ..elements_to_commands(rest)
    ]
    [first, ..rest] -> [
      single_element_to_command(first),
      ..elements_to_commands(rest)
    ]
  }
}

/// Parses Skode ASCII command text into a list of high-level semantic `SkodeCommand` nodes.
pub fn parse_command(input: String) -> Result(List(SkodeCommand), ParseError) {
  use script <- result.try(parse(input))
  let Script(chunks) = script
  let all_commands =
    list.flat_map(chunks, fn(chunk) {
      let Chunk(elements) = chunk
      elements_to_commands(elements)
    })
  Ok(all_commands)
}
