import AVFoundation
import AudioToolbox

/// The system DLS instrument owns its sound bank. No instrument samples are bundled.
final class SystemMIDIOutput {
    let graph = AVAudioEngine()
    private let instrument: AVAudioUnitMIDIInstrument
    private let reverb = AVAudioUnitReverb()
    private let limiter: AVAudioUnitEffect
    private(set) var running = false

    init(offline: Bool = false) throws {
        var description = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice,
            componentSubType: kAudioUnitSubType_DLSSynth, componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard AudioComponentFindNext(nil, &description) != nil else { throw NeuralError.audio(-1) }
        instrument = AVAudioUnitMIDIInstrument(audioComponentDescription: description)
        limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        graph.attach(instrument); graph.attach(reverb); graph.attach(limiter)
        reverb.loadFactoryPreset(.mediumHall); reverb.wetDryMix = 14
        graph.connect(instrument, to: reverb, format: format)
        graph.connect(reverb, to: limiter, format: format)
        graph.connect(limiter, to: graph.mainMixerNode, format: format)
        if offline { try graph.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096) }
        setVolume(0.5)
    }
    func start() throws {
        guard !graph.isRunning else { running = true; return }
        try graph.start(); running = true
    }
    func stop() { allNotesOff(); graph.stop(); running = false }
    func setVolume(_ value: Float) { graph.mainMixerNode.outputVolume = min(1, max(0, value)) * 0.35 }
    func programs(_ settings: NeuralSettings, resolvedInstrument: NeuralInstrument? = nil) {
        allNotesOff()
        setMelodyInstrument(resolvedInstrument ?? settings.instrument)
        instrument.sendProgramChange(33, onChannel: 1) // Fingered bass.
        instrument.sendProgramChange(settings.arrangement == .gentle ? 88 : 4, onChannel: 2)
    }
    func setMelodyInstrument(_ value: NeuralInstrument) {
        precondition(value != .automatic, "Automatic instruments must be resolved by the scheduler")
        instrument.sendController(64, withValue: 0, onChannel: 0)
        instrument.sendController(123, withValue: 0, onChannel: 0)
        instrument.sendController(120, withValue: 0, onChannel: 0)
        instrument.sendProgramChange(UInt8(value.rawValue), onChannel: 0)
    }
    func note(_ pitch: UInt8, velocity: UInt8, channel: UInt8) {
        instrument.startNote(pitch, withVelocity: velocity, onChannel: channel)
    }
    func off(_ pitch: UInt8, channel: UInt8) { instrument.stopNote(pitch, onChannel: channel) }
    func allNotesOff() {
        for channel: UInt8 in [0, 1, 2, 9] {
            instrument.sendController(64, withValue: 0, onChannel: channel)
            instrument.sendController(123, withValue: 0, onChannel: channel)
            instrument.sendController(120, withValue: 0, onChannel: channel)
        }
    }
    deinit { graph.stop() }
}

/// All inference, MIDI scheduling and model state live on this one worker queue.
/// AVAudioEngine's render callback never waits for a model or touches its memory.
final class NeuralMusicEngine {
    private static let instrumentChangeInterval: Double = 240
    private static let pianoContinuationSeconds: Double = 15
    enum Status: Equatable { case off, loading, ready, failed(String) }
    private(set) var status: Status = .off // Main-thread UI snapshot.
    var onStatusChange: (() -> Void)?
    private let queue = DispatchQueue(label: "com.sparkfx.neural-music", qos: .userInitiated)
    private let offline: Bool
    private var revision = 0 // Main-thread only; prevents stale UI completions.
    private var mode: SoundMode?
    private var settings = NeuralSettings()
    private var piano: PianoGenieModel?
    private var rnn: MusicRNNModel?
    private var drums: DrumsRNNModel?
    private var drumTempo = DrumTempoTracker()
    private var lastDrumEvent = 0
    private var drumAccent = false
    private var emittedChannels = 0
    private var output: SystemMIDIOutput?
    private var timer: DispatchSourceTimer?
    private var random = NeuralRandom()
    private var instrumentRandom = NeuralRandom()
    private var currentInstrument: NeuralInstrument = .piano
    private var nextInstrumentChange: Double?
    private struct Note: Hashable { let pitch: UInt8; let channel: UInt8 }
    private var notes: [Note: Double] = [:]
    private var lastInput = -Double.infinity
    private var lastPianoNote = -Double.infinity
    private var nextAutoNote = Double.infinity
    private var nextStep = Double.infinity
    private var step = 0
    private var lastEvent = 2 + 12 // Middle C, encoded relative to MIDI 48.
    private var melody: UInt8?
    private var button = 3
    private var activity: Float = 0
    private var inferenceCount = 0
    private var lastFailure: String?

    init(offline: Bool = false, seed: UInt64? = nil) {
        self.offline = offline
        if let seed {
            random.state = seed
            instrumentRandom.state = seed ^ 0xA47E5D19C3B28061
        }
    }
    deinit { timer?.cancel(); output?.stop() }

    func configure(mode: SoundMode?, settings newSettings: NeuralSettings = NeuralSettings()) {
        revision += 1
        let request = revision
        let selected = mode?.isNeural == true ? mode : nil
        if selected != nil && status != .ready { status = .loading }
        if selected == nil { status = .off }
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let changed = selected != self.mode || self.lastFailure != nil
                if changed {
                    self.silence()
                    self.piano = nil; self.rnn = nil; self.drums = nil
                    self.emittedChannels = 0
                    self.mode = selected
                    self.lastFailure = nil
                    if selected == .pianoGenie {
                        self.piano = try PianoGenieModel(directory: NeuralWeights.directory("piano-genie"))
                    } else if selected == .musicRNN {
                        self.rnn = try MusicRNNModel(directory: NeuralWeights.directory("music-rnn"))
                    } else if selected == .drumsRNN {
                        self.drums = try DrumsRNNModel(directory: NeuralWeights.directory("drums-rnn"))
                    }
                    if selected != nil && self.output == nil { self.output = try SystemMIDIOutput(offline: self.offline) }
                }
                let revoice = changed || self.settings.instrument != newSettings.instrument ||
                    self.settings.arrangement != newSettings.arrangement || self.settings.accompaniment != newSettings.accompaniment
                let resetRNN = changed || self.settings.arrangement != newSettings.arrangement ||
                    (selected == .drumsRNN && self.settings.drumStyle != newSettings.drumStyle)
                if self.settings.tempo != newSettings.tempo { self.drumTempo.reset(base: newSettings.tempo) }
                if changed || self.settings.instrument != newSettings.instrument {
                    self.currentInstrument = newSettings.instrument == .automatic
                        ? self.randomInstrument(excluding: self.currentInstrument) : newSettings.instrument
                    self.nextInstrumentChange = nil
                }
                self.settings = newSettings
                if selected != nil {
                    if revoice {
                        self.output?.programs(newSettings, resolvedInstrument: self.currentInstrument)
                        self.notes.removeAll(); self.melody = nil
                    }
                    self.output?.setVolume(newSettings.volume)
                    if resetRNN { self.resetModels() }
                } else { self.output = nil }
                self.publish(selected == nil ? .off : .ready, revision: request)
            } catch {
                self.silence(); self.piano = nil; self.rnn = nil; self.drums = nil; self.output = nil
                self.lastFailure = error.localizedDescription
                self.publish(.failed(error.localizedDescription), revision: request)
            }
        }
    }

    /// Only timing and an eight-button index are consumed. No typed text is read or saved.
    func noteInput(button: Int, mouse: Bool, timestamp: Double = ProcessInfo.processInfo.systemUptime) {
        queue.async { [weak self] in self?.input(button: button, mouse: mouse, at: timestamp) }
    }

    private func publish(_ value: Status, revision request: Int? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self, request == nil || request == self.revision else { return }
            self.status = value
            self.onStatusChange?()
        }
    }

    private func resetModels() {
        piano?.reset(); rnn?.reset(); drums?.reset()
        drumTempo.reset(base: settings.tempo); drumAccent = false
        lastPianoNote = -.infinity
        step = 0; lastEvent = 14
        if let drums {
            for event in settings.drumStyle.primer.dropLast() { _ = drums.logits(previousEvent: event) }
            lastDrumEvent = settings.drumStyle.primer.last!
        }
        if let rnn {
            // A short original primer, never a prerecorded song. Warm states only.
            let chord = settings.arrangement.chords[0]
            let base = chord.root + 14
            for event in [base, 0, 1, 0, base + (chord.minor ? 3 : 4), 0, 1, 0,
                          base + 7, 0, 0, 1, base, 0, 0, 1] {
                _ = rnn.logits(previousEvent: event, nextChord: settings.arrangement.chords[0])
                lastEvent = event
            }
        }
    }

    private func input(button newButton: Int, mouse: Bool, at time: Double) {
        guard mode != nil, lastFailure == nil, let output else { return }
        // Bound work under fast bursts; never replay a backlog of old keystrokes.
        if !offline && ProcessInfo.processInfo.systemUptime - time > 0.3 { return }
        guard time - lastInput >= 0.035 else { return }
        let inputInterval = time - lastInput
        let waking = !output.running
        do { try output.start() }
        catch { lastFailure = error.localizedDescription; silence(); publish(.failed(error.localizedDescription)); return }
        if waking {
            resetModels()
            nextStep = time; nextAutoNote = time + 0.4
        }
        lastInput = time
        if mode == .drumsRNN {
            drumTempo.input(interval: inputInterval)
            drumAccent = drumAccent || mouse
        }
        rotateInstrumentIfNeeded(at: time)
        activity = min(1, activity + 0.16)
        button = min(7, max(0, newButton))
        output.setVolume(settings.volume)
        if mode == .pianoGenie {
            playPiano(at: time, accented: mouse)
            nextAutoNote = time + 0.36
        } else if mode == .musicRNN && mouse && settings.accompaniment {
            play(42, channel: 9, velocity: 48, duration: 0.1, at: time)
        }
        startTimer()
    }

    private func startTimer() {
        guard timer == nil, !offline else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
        source.setEventHandler { [weak self] in self?.tick(at: ProcessInfo.processInfo.systemUptime) }
        timer = source; source.resume()
    }

    private func playPiano(at time: Double, accented: Bool = false) {
        guard let piano else { return }
        let delta = time - lastPianoNote
        let pitch = piano.next(button: button, delta: delta.isFinite ? delta : 10,
            temperature: settings.variation.temperature, range: settings.register.range, random: &random)
        inferenceCount += 1
        play(pitch, channel: 0, velocity: UInt8(min(96, 55 + Int(activity * 24) + (accented ? 10 : 0))),
             duration: min(0.85, max(0.22, delta.isFinite ? delta * 1.4 : 0.5)), at: time)
        lastPianoNote = time
    }

    private func tick(at time: Double) {
        guard let output, output.running else { return }
        let expired = notes.filter { $0.value <= time }.map(\.key)
        for note in expired { output.off(note.pitch, channel: note.channel); notes.removeValue(forKey: note) }
        let idle = max(0, time - lastInput)
        activity *= 0.996
        let continuing = mode == .pianoGenie && settings.continuation
        let stopAfter = continuing ? Self.pianoContinuationSeconds + 3 : 7
        let fadeSeconds: Double = continuing ? 7 : 4
        let fade = Float(max(0, min(1, (stopAfter - idle) / fadeSeconds)))
        output.setVolume(settings.volume * fade)
        if idle >= stopAfter { silence(); return }
        rotateInstrumentIfNeeded(at: time)
        if mode == .pianoGenie {
            if settings.continuation && idle < Self.pianoContinuationSeconds && time >= nextAutoNote {
                playPiano(at: time)
                nextAutoNote = time + 0.3 + Double(1 - activity) * 0.25
            }
        } else if (mode == .musicRNN || mode == .drumsRNN) && time >= nextStep && idle < 6 {
            if mode == .drumsRNN && step % 16 == 0 {
                drumTempo.beginBar(followInput: settings.followInputTempo, base: settings.tempo)
            }
            let bpm = mode == .drumsRNN ? drumTempo.bpm : Double(settings.tempo)
            let interval = 60 / bpm / 4
            // After a sleep or scheduling stall, skip missed beats instead of emitting a burst.
            if time - nextStep > interval * 2 { nextStep = time }
            if mode == .drumsRNN { playDrumStep(at: time) }
            else { playRNNStep(at: time, interval: interval) }
            nextStep += interval
        }
    }

    private func randomInstrument(excluding current: NeuralInstrument) -> NeuralInstrument {
        let choices = NeuralInstrument.fixed.filter { $0 != current }
        return choices[min(choices.count - 1, Int(instrumentRandom.unit() * Float(choices.count)))]
    }

    /// No timer runs solely to rotate silent instruments. An overdue change is made
    /// once on the next input; ordinary settings edits and idle stops keep the deadline.
    private func rotateInstrumentIfNeeded(at time: Double) {
        guard mode != .drumsRNN, settings.instrument == .automatic else { return }
        guard let deadline = nextInstrumentChange else {
            nextInstrumentChange = time + Self.instrumentChangeInterval
            return
        }
        guard time >= deadline else { return }
        currentInstrument = randomInstrument(excluding: currentInstrument)
        output?.setMelodyInstrument(currentInstrument)
        notes = notes.filter { $0.key.channel != 0 }
        melody = nil
        nextInstrumentChange = time + Self.instrumentChangeInterval
    }

    private func playDrumStep(at time: Double) {
        guard let drums else { return }
        let position = step % 16
        let temperature = min(1.1, settings.variation.temperature * (0.85 + activity * 0.35))
        let generated = drums.next(previousEvent: lastDrumEvent, temperature: temperature, random: &random)
        let event = settings.drumDensity.filter(generated | settings.drumStyle.anchor(at: position), position: position)
        lastDrumEvent = event; inferenceCount += 1
        for (bit, pitch) in DrumsRNNModel.pitches.enumerated() where event & (1 << bit) != 0 {
            let accent = (position % 4 == 0 ? 8 : 0) + (drumAccent ? 10 : 0)
            let velocity = min(96, 42 + Int(activity * 24) + accent)
            play(pitch, channel: 9, velocity: UInt8(velocity), duration: bit >= 7 ? 0.6 : 0.18, at: time)
        }
        drumAccent = false; step += 1
    }

    private func playRNNStep(at time: Double, interval: Double) {
        guard let rnn else { return }
        let chord = settings.arrangement.chords[(step / 16) % 4]
        let event = rnn.next(previousEvent: lastEvent, chord: chord,
                             temperature: settings.variation.temperature, random: &random)
        inferenceCount += 1; lastEvent = event
        switch event {
        case 0:
            if let melody { notes[Note(pitch: melody, channel: 0)] = time + interval * 1.5 }
        case 1: releaseMelody()
        default:
            releaseMelody()
            let pitch = UInt8(event - 2 + 48)
            melody = pitch
            play(pitch, channel: 0, velocity: UInt8(55 + Int(activity * 25)), duration: interval * 1.5, at: time)
        }
        if settings.accompaniment { accompany(chord, at: time, interval: interval) }
        step += 1
    }

    private func accompany(_ chord: MusicChord, at time: Double, interval: Double) {
        let position = step % 16
        if position == 0 || position == 8 {
            play(UInt8(36 + chord.root), channel: 1, velocity: 48, duration: interval * 3, at: time)
        }
        if position == 0 {
            for pitch in chord.pitches { play(UInt8(48 + pitch), channel: 2, velocity: 32, duration: interval * 13, at: time) }
        }
        guard settings.arrangement != .gentle else { return }
        if position % 4 == 0 {
            let drum: UInt8 = settings.arrangement == .electronic || position % 8 == 0 ? 36 : 38
            play(drum, channel: 9, velocity: 48, duration: 0.12, at: time)
        }
        if position % 2 == 0 && (activity > 0.3 || settings.arrangement == .electronic) {
            play(42, channel: 9, velocity: 30, duration: 0.06, at: time)
        }
    }

    private func play(_ pitch: UInt8, channel: UInt8, velocity: UInt8, duration: Double, at time: Double) {
        emittedChannels |= 1 << Int(channel)
        let note = Note(pitch: pitch, channel: channel)
        if notes[note] != nil { output?.off(pitch, channel: channel) }
        if notes.count >= 12, let oldest = notes.min(by: { $0.value < $1.value })?.key {
            output?.off(oldest.pitch, channel: oldest.channel); notes.removeValue(forKey: oldest)
        }
        output?.note(pitch, velocity: velocity, channel: channel)
        notes[note] = time + duration
    }

    private func releaseMelody() {
        if let melody { output?.off(melody, channel: 0); notes.removeValue(forKey: Note(pitch: melody, channel: 0)) }
        melody = nil
    }

    private func silence() {
        timer?.cancel(); timer = nil
        output?.stop(); notes.removeAll(); melody = nil
        lastInput = -.infinity; nextStep = .infinity; nextAutoNote = .infinity; activity = 0
    }

    func stop() { configure(mode: nil) }

    // Offline verification uses the same inference, scheduling and system instrument.
    // These calls never open the default audio device when initialized with offline: true.
    func synchronize() { queue.sync {} }
    func advanceOffline(to time: Double) { precondition(offline); queue.sync { tick(at: time) } }
    var debugState: (mode: SoundMode?, running: Bool, notes: Int, inferences: Int, failure: String?, instrument: NeuralInstrument, drumBPM: Double, channels: Int) {
        queue.sync { (mode, output?.running ?? false, notes.count, inferenceCount, lastFailure, currentInstrument, drumTempo.bpm, emittedChannels) }
    }
    func renderOffline(frames: AVAudioFrameCount) throws -> [Float] {
        precondition(offline)
        return try queue.sync {
            guard let graph = output?.graph, output?.running == true else { return [] }
            let buffer = AVAudioPCMBuffer(pcmFormat: graph.manualRenderingFormat, frameCapacity: 4096)!
            var result: [Float] = []
            var remaining = frames
            var retries = 0
            while remaining > 0 {
                let count = min(remaining, 4096)
                let status = try graph.renderOffline(count, to: buffer)
                guard status == .success else {
                    retries += 1
                    if retries > 8 { throw NeuralError.audio(-2) }
                    continue
                }
                guard buffer.frameLength > 0 else { throw NeuralError.audio(-3) }
                for frame in 0..<Int(buffer.frameLength) { result.append(buffer.floatChannelData![0][frame]) }
                remaining -= buffer.frameLength
            }
            return result
        }
    }
}
