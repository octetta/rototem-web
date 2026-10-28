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
