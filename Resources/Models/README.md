# Local symbolic music models

These are trained **note-generation weights**, not instrument recordings. Playback uses
the macOS system DLS instrument. This directory contains no WAV, MP3, SoundFont or sound bank.
All three models run offline using Swift and Apple's Accelerate framework. No runtime downloads,
Python, browser, TensorFlow library, or external service are used by the app.

## Provenance

- Piano Genie autoregressive delta-time decoder, 2 x 128 LSTM, float32 (1,161,568 bytes).
  Official checkpoint:
  https://storage.googleapis.com/magentadata/js/checkpoints/piano_genie/model/epiano/stp_iq_auto_contour_dt_166006/
  https://magenta.withgoogle.com/pianogenie
- MusicRNN `chord_pitches_improv` (ImprovRNN), 3 x 256 LSTM, float32 (5,601,432 bytes).
  Official checkpoint:
  https://storage.googleapis.com/magentadata/js/checkpoints/music_rnn/chord_pitches_improv/
  https://github.com/magenta/magenta-js/tree/master/music/src/music_rnn

- DrumsRNN `drum_kit_rnn`, 3 x 256 LSTM with 32-step attention and a six-bit counter,
  float32 (11,871,400 bytes). Official checkpoint:
  https://storage.googleapis.com/magentadata/js/checkpoints/music_rnn/drum_kit_rnn/
  https://github.com/magenta/magenta/tree/main/magenta/models/drums_rnn
  Native inference also adapts Magenta.js music_rnn/attention.ts and core/aux_inputs.ts
  under the same Apache-2.0 license. The regression fixture covers attention history
  rollover and the 64-step binary counter rollover.

Weights are kept in their original TF.js manifest/shard format. `SHA256SUMS` records
the downloaded files and is checked when building. The app only loads these local files.

The Swift inference implementation is adapted from Magenta.js by Google Inc.
(Copyright 2018 Google Inc.), licensed under Apache License 2.0. The full upstream
license is included in `LICENSE.txt`. Original source:
https://github.com/magenta/magenta-js/tree/master/music/src/piano_genie
https://github.com/magenta/magenta-js/tree/master/music/src/music_rnn

Changes: native float32 matrix/vector operations, checkpoint loading, recurrent state,
sampling and note-event adaptation for SparkFX Keyboard. TensorFlow's i/j/f/o LSTM
gate convention and +1 forget bias are preserved. Numerical regression fixtures in
`Tests/NeuralReference.json` are produced with TensorFlow.js CPU operations.

## User-facing behavior

Piano Genie chooses pitches for input events, optionally continuing briefly. Its
training is piano-oriented; choosing a different playback instrument does not retrain it.
MusicRNN generates a monophonic melody conditioned on a four-chord progression.
Its optional bass/chords/drums are a small procedural arranger. Gentle/Pop/Electronic
are arrangement choices, not separately genre-trained models. No Suno-style audio or
vocal generation is performed. No typed text or audio is sent anywhere.

Drums Only uses the trained drum model plus a procedural backbone and density filter.
Typing-rate estimation changes the playback clock at bar boundaries; it is not a learned
beat detector. Only macOS General MIDI percussion is used, with no melodic tracks.
