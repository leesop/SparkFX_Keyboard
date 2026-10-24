import AVFoundation

private func checkNeuralModels() throws {
    struct Reference: Decodable {
        struct Piano: Decodable { let button: Int; let delta: Double; let accepted: Int; let logits: [Float] }
        struct RNN: Decodable { let event: Int; let root: Int; let minor: Bool; let logits: [Float] }
        struct Drums: Decodable { let event: Int; let logits: [Float]? }
        let piano: [Piano]; let rnn: [RNN]; let drums: [Drums]
    }
    let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf:
        Bundle.main.resourceURL!.appendingPathComponent("NeuralReference.json")))
    let piano = try PianoGenieModel(directory: NeuralWeights.directory("piano-genie"))
    let rnn = try MusicRNNModel(directory: NeuralWeights.directory("music-rnn"))
    let drums = try DrumsRNNModel(directory: NeuralWeights.directory("drums-rnn"))
    var maxError: Float = 0
    for sample in reference.piano {
        let logits = piano.logits(button: sample.button, delta: sample.delta)
        let error = zip(logits, sample.logits).map { abs($0 - $1) }.max()!
        maxError = max(maxError, error)
        try check(error < 0.0001, "Piano Genie matches TensorFlow.js CPU logits, error=\(error)")
        piano.accept(pianoKey: sample.accepted)
    }
    piano.reset()
    try check(zip(piano.logits(button: reference.piano[0].button, delta: reference.piano[0].delta), reference.piano[0].logits)
        .allSatisfy { abs($0 - $1) < 0.0001 }, "Piano Genie reset clears recurrent history")
    for sample in reference.rnn {
        let logits = rnn.logits(previousEvent: sample.event, nextChord: MusicChord(root: sample.root, minor: sample.minor))
        let error = zip(logits, sample.logits).map { abs($0 - $1) }.max()!
        maxError = max(maxError, error)
        try check(error < 0.0001, "MusicRNN matches TensorFlow.js CPU logits, error=\(error)")
    }
    rnn.reset()
    for sample in reference.drums {
        let logits = drums.logits(previousEvent: sample.event)
        if let expected = sample.logits {
            let error = zip(logits, expected).map { abs($0 - $1) }.max()!
            maxError = max(maxError, error)
            try check(error < 0.0002, "DrumsRNN matches TensorFlow attention/counter, error=\(error)")
        }
    }
    drums.reset()
    try check(zip(drums.logits(previousEvent: reference.drums[0].event), reference.drums[0].logits!)
        .allSatisfy { abs($0 - $1) < 0.0002 }, "Drum reset clears attention and binary counter")
    let start = ProcessInfo.processInfo.systemUptime
    var random = NeuralRandom(state: 42)
    for i in 0..<200 {
        let pitch = piano.next(button: i % 8, delta: 0.1, temperature: 0.65, range: 55...84, random: &random)
        try check((55...84).contains(Int(pitch)), "Piano Genie respects register")
    }
    let pianoMS = (ProcessInfo.processInfo.systemUptime - start) * 1000 / 200
    let rnnStart = ProcessInfo.processInfo.systemUptime
    var previous = 14
    for i in 0..<200 {
        previous = rnn.next(previousEvent: previous, chord: NeuralArrangement.pop.chords[(i/16)%4], temperature: 0.65, random: &random)
        try check((0..<38).contains(previous), "MusicRNN event range")
    }
    let rnnMS = (ProcessInfo.processInfo.systemUptime - rnnStart) * 1000 / 200
    let drumStart = ProcessInfo.processInfo.systemUptime
    previous = 5
    for _ in 0..<200 {
        previous = drums.next(previousEvent: previous, temperature: 0.65, random: &random)
        try check((0..<512).contains(previous), "DrumsRNN event range")
    }
    let drumMS = (ProcessInfo.processInfo.systemUptime - drumStart) * 1000 / 200
    print(String(format: "PASS neural numerical parity (max error %.8f), reset, ranges; inference PG %.3f / RNN %.3f / Drums %.3f ms", maxError, pianoMS, rnnMS, drumMS))
}

private func checkNeuralPlayback() throws {
    for instrument in NeuralInstrument.fixed {
        let output = try SystemMIDIOutput(offline: true)
        var settings = NeuralSettings(); settings.instrument = instrument
        output.programs(settings)
        try output.start()
        output.note(60, velocity: 80, channel: 0)
        let buffer = AVAudioPCMBuffer(pcmFormat: output.graph.manualRenderingFormat, frameCapacity: 4096)!
        var peak: Float = 0
        for _ in 0..<4 {
            let status = try output.graph.renderOffline(4096, to: buffer)
            try check(status == .success, "System instrument renders offline")
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(buffer.floatChannelData![0][i])) }
        }
        try check(peak > 0.00001 && peak <= 1, "macOS \(instrument.key) produces finite audible output: \(peak)")
        output.stop()
    }
    let previewRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SPARKFX_TEST_OUTPUT"] ?? NSTemporaryDirectory())
    for mode in [SoundMode.pianoGenie, .musicRNN, .drumsRNN] {
        let engine = NeuralMusicEngine(offline: true, seed: 42)
        var settings = NeuralSettings()
        settings.arrangement = .pop
        engine.configure(mode: mode, settings: settings); engine.synchronize()
        try check(engine.debugState.failure == nil, "\(mode) initializes with bundled weights and system instrument")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let previewURL = previewRoot.appendingPathComponent("\(mode.rawValue)-preview.caf")
        let file = try AVAudioFile(forWriting: previewURL, settings: format.settings)
        var peak: Float = 0, energy: Double = 0, count = 0
        let frames = mode == .pianoGenie ? 1300 : 750
        for i in 0..<frames { // 6 seconds typing + complete idle fade, no speaker output.
            let time = 100 + Double(i) * 0.02
            if i < 300 && i % 6 == 0 {
                engine.noteInput(button: (i / 6) % 8, mouse: i % 24 == 0, timestamp: time)
                engine.synchronize()
            }
            engine.advanceOffline(to: time)
            let samples = try engine.renderOffline(frames: 960)
            if samples.isEmpty { continue }
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
            buffer.frameLength = AVAudioFrameCount(samples.count)
            for (index, value) in samples.enumerated() {
                try check(value.isFinite, "\(mode) no NaN / Inf")
                buffer.floatChannelData![0][index] = value
                peak = max(peak, abs(value)); energy += Double(value * value); count += 1
            }
            try file.write(from: buffer)
            try check(engine.debugState.notes <= 12, "Bounded polyphony")
        }
        try check(peak > 0.001 && peak <= 1 && energy > 0, "\(mode) produces bounded actual audio, peak=\(peak)")
        try check(!engine.debugState.running && engine.debugState.notes == 0, "\(mode) idle stops audio and clears notes")
        let inferences = engine.debugState.inferences
        engine.advanceOffline(to: 200)
        try check(engine.debugState.inferences == inferences, "No inference while idle")
        engine.noteInput(button: 4, mouse: false, timestamp: 201); engine.synchronize()
        engine.advanceOffline(to: 201)
        try check(engine.debugState.running && engine.debugState.inferences > inferences, "Wake restarts playing")
        for i in 0..<200 { engine.noteInput(button: i%8, mouse: false, timestamp: 201 + Double(i)*0.001) }
        engine.synchronize()
        try check(engine.debugState.notes <= 12 && engine.debugState.inferences < inferences + 10, "Input storm is rate-limited")
        engine.configure(mode: nil); engine.synchronize()
        engine.noteInput(button: 3, mouse: true, timestamp: 202); engine.synchronize()
        try check(engine.debugState.mode == nil && !engine.debugState.running && engine.debugState.notes == 0,
                  "Switching off blocks queued input and clears notes")
        print(String(format: "PASS %@: system MIDI, input, continuation, polyphony, idle/wake, switch-off; peak %.4f RMS %.4f", mode.rawValue, peak, sqrt(energy/Double(count))))
    }

    // Same seeded performance through the complete audio path at each user volume.
    for mode in [SoundMode.pianoGenie, .musicRNN, .drumsRNN] {
        var fullRMS: Double = 0
        for volume in [Float(1), 0.75, 0.5, 0.25] {
            let engine = NeuralMusicEngine(offline: true, seed: 123)
            var settings = NeuralSettings(); settings.volume = volume
            engine.configure(mode: mode, settings: settings); engine.synchronize()
            engine.noteInput(button: 3, mouse: false, timestamp: 100); engine.synchronize()
            engine.advanceOffline(to: 100)
            let samples = try engine.renderOffline(frames: 12000)
            try check(!samples.isEmpty, "Volume test has audio")
            let rms = sqrt(samples.reduce(0) { $0 + Double($1 * $1) } / Double(samples.count))
            if volume == 1 { fullRMS = rms }
            try check(fullRMS > 0.00001 && abs(rms / fullRMS - Double(volume)) < 0.035,
                      "\(mode) relative master volume \(volume), measured \(rms / fullRMS)")
            engine.configure(mode: nil); engine.synchronize()
        }
    }
    print("PASS all system instruments and both models' 25/50/75/100% relative volume")
    try checkAutomaticInstrumentsAndContinuation()
    try checkDrumTempoAndPlayback()
}

private func checkDrumTempoAndPlayback() throws {
    try check(NeuralInstrument.fixed.count == 10, "Ten actual instruments plus Automatic")
    var slow = DrumTempoTracker(), fast = DrumTempoTracker()
    slow.reset(base: 90); fast.reset(base: 90)
    for _ in 0..<12 { slow.input(interval: 0.5); fast.input(interval: 0.125) }
    fast.input(interval: 1.4) // One pause should not dominate the median.
    for _ in 0..<8 { slow.beginBar(followInput: true, base: 90); fast.beginBar(followInput: true, base: 90) }
    try check(fast.bpm > slow.bpm + 30 && fast.bpm <= 160 && slow.bpm >= 70, "Typing-rate tempo is robust and bounded")
    fast.beginBar(followInput: false, base: 128)
    try check(fast.bpm == 128, "Manual drum tempo overrides activity")
    for density in DrumDensity.allCases {
        for event in 0..<512 {
            let mask = density.filter(event, position: 3)
            try check(mask < 512 && !(mask & 4 != 0 && mask & 8 != 0), "Valid mutually exclusive hi-hats")
            try check(mask.nonzeroBitCount <= (density == .busy ? 5 : density == .sparse ? 3 : 4), "Bounded drum density")
        }
    }
    let engine = NeuralMusicEngine(offline: true, seed: 87)
    var settings = NeuralSettings()
    engine.configure(mode: .drumsRNN, settings: settings); engine.synchronize()
    try check(engine.debugState.failure == nil, "Actual drum model loads")
    var slowBPM: Double = 0, fastBPM: Double = 0, previousBPM = 90.0
    var peak: Float = 0
    for i in 0..<1500 {
        let time = 100 + Double(i) * 0.02
        let input = i < 500 ? i % 25 == 0 : (i < 1000 && i % 6 == 0)
        if input { engine.noteInput(button: 3, mouse: false, timestamp: time); engine.synchronize() }
        engine.advanceOffline(to: time)
        let bpm = engine.debugState.drumBPM
        try check(abs(bpm - previousBPM) <= 12.0001, "No abrupt tempo jumps")
        previousBPM = bpm
        if i == 499 { slowBPM = bpm }; if i == 999 { fastBPM = bpm }
        let samples = try engine.renderOffline(frames: 960)
        for sample in samples { try check(sample.isFinite, "Drum mix finite"); peak = max(peak, abs(sample)) }
        try check(engine.debugState.notes <= 12, "Bounded drum polyphony")
    }
    try check(fastBPM > slowBPM + 12, "Integrated drum clock follows faster typing")
    try check(engine.debugState.channels == 1 << 9, "Drums only never emits a melodic channel")
    try check(peak > 0.001 && peak < 1, "Real macOS drum audio is audible without clipping")
    try check(!engine.debugState.running && engine.debugState.notes == 0, "Drum idle stops and clears notes")
    settings.followInputTempo = false; settings.tempo = 128; settings.drumStyle = .dance; settings.drumDensity = .busy
    engine.configure(mode: .drumsRNN, settings: settings); engine.synchronize()
    engine.noteInput(button: 4, mouse: true, timestamp: 200); engine.synchronize(); engine.advanceOffline(to: 200)
    try check(engine.debugState.running && engine.debugState.drumBPM == 128 && engine.debugState.channels == 1 << 9,
              "Drum style/density/manual tempo apply and wake safely")
    engine.configure(mode: .pianoGenie); engine.synchronize()
    try check(!engine.debugState.running && engine.debugState.notes == 0 && engine.debugState.channels == 0,
              "Leaving drum mode clears its voices and state")
    engine.configure(mode: nil); engine.synchronize()
    print("PASS 10 instruments, DrumsRNN-only playback, density, input tempo, manual override, idle and mode switch")
}

private func checkAutomaticInstrumentsAndContinuation() throws {
    for mode in [SoundMode.pianoGenie, .musicRNN] {
        let engine = NeuralMusicEngine(offline: true, seed: 41)
        var settings = NeuralSettings(); settings.instrument = .automatic
        engine.configure(mode: mode, settings: settings); engine.synchronize()
        engine.noteInput(button: 3, mouse: false, timestamp: 100); engine.synchronize()
        let first = engine.debugState.instrument
        try check(NeuralInstrument.fixed.contains(first), "Automatic resolves to a real instrument")
        // Editing unrelated settings must not postpone the four-minute deadline.
        settings.volume = 0.75
        engine.configure(mode: mode, settings: settings); engine.synchronize()
        engine.noteInput(button: 4, mouse: false, timestamp: 339.9); engine.synchronize()
        engine.advanceOffline(to: 339.99)
        try check(engine.debugState.instrument == first, "Automatic keeps instrument before four minutes")
        engine.advanceOffline(to: 340.01)
        let second = engine.debugState.instrument
        try check(second != first && NeuralInstrument.fixed.contains(second), "Automatic switches to a different instrument at four minutes")
        let samples = try engine.renderOffline(frames: 4096)
        try check(!samples.isEmpty && samples.allSatisfy(\.isFinite), "Instrument transition renders safely")
        engine.advanceOffline(to: 380)
        try check(!engine.debugState.running && engine.debugState.instrument == second, "Idle stops audio without changing the chosen instrument")
        engine.noteInput(button: 2, mouse: false, timestamp: 650); engine.synchronize()
        try check(engine.debugState.instrument != second, "Overdue automatic instrument changes on wake")
        settings.instrument = .strings
        engine.configure(mode: mode, settings: settings); engine.synchronize()
        engine.noteInput(button: 3, mouse: false, timestamp: 900); engine.synchronize()
        engine.noteInput(button: 4, mouse: false, timestamp: 1141); engine.synchronize()
        engine.advanceOffline(to: 1141)
        try check(engine.debugState.instrument == .strings, "Fixed instrument cancels automatic rotation")
        engine.configure(mode: nil); engine.synchronize()
    }

    let engine = NeuralMusicEngine(offline: true, seed: 42)
    var settings = NeuralSettings()
    engine.configure(mode: .pianoGenie, settings: settings); engine.synchronize()
    engine.noteInput(button: 3, mouse: false, timestamp: 100); engine.synchronize()
    let initial = engine.debugState.inferences
    for time in [103.0, 110, 114.9] {
        let before = engine.debugState.inferences
        engine.advanceOffline(to: time)
        try check(engine.debugState.running && engine.debugState.inferences > before, "Piano Genie continues generating for fifteen seconds")
    }
    let continued = engine.debugState.inferences
    try check(continued > initial, "Continuation actually invokes the model")
    let audio = try engine.renderOffline(frames: 4096)
    try check(audio.contains { abs($0) > 0.00001 }, "Extended continuation remains audible")
    engine.advanceOffline(to: 115.1)
    try check(engine.debugState.inferences == continued, "No new notes after fifteen-second continuation")
    engine.advanceOffline(to: 118.1)
    try check(!engine.debugState.running && engine.debugState.notes == 0, "Extended continuation ends after its fade")
    settings.continuation = false
    engine.configure(mode: .pianoGenie, settings: settings); engine.synchronize()
    engine.noteInput(button: 4, mouse: false, timestamp: 200); engine.synchronize()
    let direct = engine.debugState.inferences
    engine.advanceOffline(to: 203.5)
    try check(engine.debugState.inferences == direct, "Disabling continuation stops automatic notes")
    engine.advanceOffline(to: 207.1)
    try check(!engine.debugState.running, "Continuation-off retains original idle stop")
    engine.configure(mode: nil); engine.synchronize()
    print("PASS four-minute instrument rotation, no repeated instruments, idle/wake, fixed selection and fifteen-second continuation")
}

extension AppDelegate {
    private func checkNeuralWindow(_ controller: SoundOptionsWindowController) throws {
        for mode in [SoundMode.pianoGenie, .musicRNN] {
            try selectOption(controller, "mode", index: SoundMode.allCases.firstIndex(of: mode)!)
            neural.synchronize()
            try check(Prefs.soundMode == mode && !ambient.isEnabled && preparedSound(for: .keyboard) == nil,
                      "Neural mode excludes legacy audio")
            try check(neural.debugState.mode == mode && neural.debugState.failure == nil, "Correct real model loads")
            let instruments = controller.control("neural.instrument") as! NSPopUpButton
            try check(instruments.itemTitles.first == L("neural.instrument.automatic"), "Automatic is offered in each model")
            try selectOption(controller, "neural.instrument", index: 0)
            neural.synchronize()
            try check(Prefs.neuralSettings(mode).instrument == .automatic && neural.debugState.instrument != .automatic,
                      "Automatic persists and is resolved before sending MIDI")
            try selectOption(controller, "neural.instrument", index: NeuralInstrument.allCases.firstIndex(of: .electricPiano)!)
            try check(Prefs.neuralSettings(mode).instrument == .electricPiano, "Instrument setting persists")
            if mode == .pianoGenie {
                try selectOption(controller, "neural.register", index: 2)
                try setOption(controller, "neural.continuation", enabled: false)
                try check(Prefs.neuralSettings(mode).register == .high && !Prefs.neuralSettings(mode).continuation,
                          "Piano register and continuation")
                try check(controller.control("neural.tempo") == nil, "Piano timing follows input")
            } else {
                try selectOption(controller, "neural.arrangement", index: 2)
                try selectOption(controller, "neural.tempo", index: 3)
                try setOption(controller, "neural.accompaniment", enabled: false)
                try check(Prefs.neuralSettings(mode).arrangement == .electronic && Prefs.neuralSettings(mode).tempo == 128 &&
                          !Prefs.neuralSettings(mode).accompaniment, "MusicRNN arrangement, tempo and accompaniment")
                try check(controller.control("neural.register") == nil, "No stale Piano Genie controls")
            }
            let originalControl = controller.control("neural.variation")!
            try selectOption(controller, "neural.variation", index: 2)
            try setVolumeOption(controller, index: 3)
            neural.synchronize()
            controller.refresh(neuralStatus: .ready)
            try check(Prefs.neuralSettings(mode).volume == 1 && Prefs.neuralSettings(mode).variation == .adventurous,
                      "Model volume and variation persist")
            try check(controller.control("neural.variation") === originalControl, "Value/status refresh preserves controls and focus")
            try saveOptionsSnapshot(controller, mode: mode.rawValue)
        }
        try selectOption(controller, "mode", index: SoundMode.allCases.firstIndex(of: .drumsRNN)!)
        neural.synchronize()
        try check(neural.debugState.mode == .drumsRNN && neural.debugState.failure == nil && !ambient.isEnabled,
                  "Drums-only routes to its trained model")
        try check(controller.control("neural.instrument") == nil && controller.control("neural.accompaniment") == nil,
                  "Drums-only hides melody and accompaniment controls")
        try selectOption(controller, "drums.style", index: 2)
        try selectOption(controller, "drums.density", index: 2)
        try selectOption(controller, "drums.tempo", index: 3)
        try setOption(controller, "drums.followTempo", enabled: false)
        try setVolumeOption(controller, index: 2)
        neural.synchronize()
        let drumSettings = Prefs.neuralSettings(.drumsRNN)
        try check(drumSettings.drumStyle == .halftime && drumSettings.drumDensity == .busy && drumSettings.tempo == 128 &&
                  !drumSettings.followInputTempo && drumSettings.volume == 0.75, "Drum controls persist independently")
        controller.refresh(neuralStatus: .ready)
        try saveOptionsSnapshot(controller, mode: "drumsRNN")
        try selectOption(controller, "mode", index: 3)
        neural.synchronize()
        try check(Prefs.neuralSettings(.pianoGenie).register == .high && !Prefs.neuralSettings(.pianoGenie).continuation &&
                  (controller.control("neural.register") as! NSPopUpButton).indexOfSelectedItem == 2,
                  "Each model remembers its independent controls")
        controller.refresh(neuralStatus: .failed("Test failure"))
        try check(controller.control("neural.retry")?.isHidden == false, "Model error offers retry in the window")
        controller.refresh(neuralStatus: .ready)
        try check(controller.control("neural.retry")?.isHidden == true, "Recovery hides retry")
        print("PASS both AI settings windows, independent values, live controls, status/retry and mode routing")
    }
}

private func sendOption(_ control: NSControl?) throws {
    guard let control, let action = control.action else { throw CheckFailure.failed("Missing option control") }
    try check(NSApp.sendAction(action, to: control.target, from: control), "Window control dispatches action")
}
private func selectOption(_ controller: SoundOptionsWindowController, _ id: String, index: Int) throws {
    let popup = controller.control(id) as! NSPopUpButton
    popup.selectItem(at: index)
    try sendOption(popup)
}
private func setOption(_ controller: SoundOptionsWindowController, _ id: String, enabled: Bool) throws {
    let checkbox = controller.control(id) as! NSButton
    checkbox.state = enabled ? .on : .off
    try sendOption(checkbox)
}
private func setVolumeOption(_ controller: SoundOptionsWindowController, index: Int) throws {
    let volume = controller.control("volume") as! NSSegmentedControl
    volume.selectedSegment = index
    try sendOption(volume)
}
private func saveOptionsSnapshot(_ controller: SoundOptionsWindowController, mode: String) throws {
    guard let root = controller.window?.contentView else { return }
    root.layoutSubtreeIfNeeded()
    let controls = ["mode", "volume", "ambient.voice", "keyboard.source", "neural.instrument", "neural.variation"]
    for id in controls {
        if let control = controller.control(id) {
            try check(control.frame.width > 60 && control.frame.height > 10, "Control has a usable frame: \(id)")
        }
    }
    // Check the smallest supported size and scrolling with longer option groups.
    let originalSize = root.frame.size
    controller.window?.setContentSize(NSSize(width: 560, height: 420))
    root.layoutSubtreeIfNeeded()
    let scroll = root.subviews.compactMap { $0 as? NSScrollView }.first!
    let document = scroll.documentView!
    if document.frame.height > scroll.contentView.bounds.height {
        let bottom = document.frame.height - scroll.contentView.bounds.height
        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        root.layoutSubtreeIfNeeded()
        try check(scroll.contentView.bounds.minY > 0, "Long settings can scroll at minimum window size")
        scroll.contentView.scroll(to: .zero)
    }
    try check((controller.control("volume")?.frame.width ?? 0) >= 200, "Volume stays usable at minimum width")
    controller.window?.setContentSize(originalSize)
    root.layoutSubtreeIfNeeded()
    if let folder = ProcessInfo.processInfo.environment["SPARKFX_TEST_OUTPUT"],
       let image = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
        root.cacheDisplay(in: root.bounds, to: image)
        if let data = image.representation(using: .png, properties: [:]) {
            let lang = Bundle.main.preferredLocalizations.first ?? "unknown"
            try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("sound-options-\(mode)-\(lang).png"))
        }
    }
}
