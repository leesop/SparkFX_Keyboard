import Foundation

/// File-free metal/EDM loops and input-triggered guitar/electronic notes.
/// All state belongs to the render thread. Voice pools and the sine table are
/// allocated at initialization, never in the audio callback.
final class ModernSynth {
    private struct Note {
        var active = false
        var phase: Double = 0
        var increment: Double = 0
        var age: Float = 0
        var envelope: Float = 0
        var decay: Float = 0
        var left: Float = 0
        var right: Float = 0
    }

    private static let tableSize = 2048
    private let sine: [Float]
    private let sampleRate: Double
    private let dt: Double
    private let attackFrames: Float
    private let guitars: [MetalGuitarVoice]
    private let guitarAmp: MetalGuitarAmp
    private var electronics = [Note](repeating: Note(), count: 8)
    private var guitarCursor = 0
    private var electronicCursor = 0
    private var noteIndex = 0
    private static let guitarNotes = [0, 0, 3, 0, 5, 0, 7, 0]
    private static let notes = [0, 3, 5, 7, 10, 12, 7, 5]
    private static let metalRiff = [0, 0, 0, 7, 0, 0, 3, 5, 0, 0, 10, 7, 0, 3, 7, 0]
    private static let edmRiff = [0, 0, 7, 10, 0, 12, 7, 3, 0, 0, 7, 10, 5, 3, 7, 12]
    private var voice: AmbientVoice = .wind
    private var step = 0
    private var stepFrame: Double = 0
    private var phase: Double = 0
    private var fifthPhase: Double = 0
    private var leadPhase: Double = 0
    private var kickPhase: Double = 0
    private var increment: Double = 0
    private var noiseState: UInt32 = 0x7F4A_7C15
    private var hatLowpass: Float = 0

    private(set) var guitarStrikeCount = 0
    private(set) var electronicStrikeCount = 0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        dt = 1 / sampleRate
        attackFrames = Float(sampleRate * 0.004)
        guitars = (0..<4).map { MetalGuitarVoice(sampleRate: sampleRate, seed: UInt32($0 + 1) &* 0x85EB_CA6B) }
        guitarAmp = MetalGuitarAmp(sampleRate: sampleRate)
        sine = (0...Self.tableSize).map { Float(sin(2 * .pi * Double($0) / Double(Self.tableSize))) }
    }

    func configure(voice: AmbientVoice, guitar: Bool, electronic: Bool) {
        if self.voice != voice {
            self.voice = voice
            step = 0
            stepFrame = 0
            phase = 0
            fifthPhase = 0
            leadPhase = 0
            kickPhase = 0
            updatePitch()
        }
        if !guitar {
            guitarAmp.reset()
            for guitar in guitars { guitar.stop() }
        }
        if !electronic {
            for index in electronics.indices { electronics[index].active = false }
        }
    }

    func noteInput(count: Int, guitar: Bool, electronic: Bool) {
        for _ in 0..<min(count, 4) {
            let semitone = Self.notes[noteIndex % Self.notes.count]
            let guitarSemitone = Self.guitarNotes[noteIndex]
            let palmMuted = noteIndex % 4 == 1 || noteIndex % 4 == 2
            let pan: Float = noteIndex % 2 == 0 ? -0.2 : 0.2
            noteIndex = (noteIndex + 1) % Self.notes.count
            if guitar {
                // Drop-D power chords, with independent physical string takes.
                guitars[guitarCursor].pluck(frequency: 73.4162 * pow(2, Double(guitarSemitone) / 12),
                                             palmMuted: palmMuted, pan: pan)
                guitarCursor = (guitarCursor + 1) % guitars.count
                guitarStrikeCount += 1
            }
            if electronic {
                electronics[electronicCursor] = note(frequency: 330 * pow(2, Double(semitone) / 12),
                                                      tau: 0.16, gain: 0.04, pan: -pan)
                electronicCursor = (electronicCursor + 1) % electronics.count
                electronicStrikeCount += 1
            }
        }
    }

    func nextBackground() -> (Float, Float) {
        let bpm: Double
        switch voice {
        case .metal: bpm = 112
        case .edm: bpm = 128
        default: return (0, 0)
        }
        let stepFrames = sampleRate * 60 / (bpm * 2)
        if stepFrame >= stepFrames {
            stepFrame -= stepFrames
            step = (step + 1) % 16
            updatePitch()
        }
        let age = stepFrame * dt
        let attack = Float(min(age / 0.004, 1))
        phase = wrapped(phase + increment)
        fifthPhase = wrapped(fifthPhase + increment * 1.4983)
        leadPhase = wrapped(leadPhase + increment * 4.003)
        stepFrame += 1

        if voice == .metal {
            // Palm-muted A power chords: a short pick attack, rounded overdrive,
            // and a longer accent every four eighth notes.
            let envelope = attack * Float(exp(-age / (step % 4 == 0 ? 0.19 : 0.095)))
            let body = wave(phase) * 0.62 + wave(phase * 2) * 0.24 + wave(phase * 3) * 0.16
            let fifth = wave(fifthPhase) * 0.42 + wave(fifthPhase * 2) * 0.14
            let driven = tanhf((body + fifth) * 2.2) * 0.48 * envelope
            let shimmer = wave(leadPhase) * envelope * 0.035
            return (driven + shimmer, driven - shimmer)
        }

        // EDM: syncopated harmonic bass, a quiet arpeggio, synthesized kick,
        // snare and high-passed noise hats. No drum samples are used.
        let gate = attack * Float(exp(-age / 0.13))
        let bass = (wave(phase) * 0.65 + wave(phase * 2) * 0.2 + wave(phase * 3) * 0.1) * gate * 0.32
        let lead = wave(leadPhase + Double(wave(leadPhase * 2)) * 0.06) * gate * 0.09
        let beatAge = (Double(step % 2) * stepFrames + stepFrame) * dt
        let kickFrequency = 46 + 105 * exp(-beatAge / 0.025)
        kickPhase = wrapped(kickPhase + kickFrequency * dt)
        let kick = wave(kickPhase) * Float(exp(-beatAge / 0.09)) * 0.28 * Float(min(beatAge / 0.002, 1))
        let noise = nextNoise()
        hatLowpass += (noise - hatLowpass) * 0.38
        let hat = (noise - hatLowpass) * Float(exp(-age / 0.022)) * 0.055 * attack
        let snare = (step % 8 == 2 || step % 8 == 6)
            ? noise * Float(exp(-age / 0.065)) * 0.085 * attack : 0
        return (bass + lead + kick + hat + snare, bass - lead * 0.3 + kick - hat * 0.7 + snare)
    }

    func nextKeys() -> (Float, Float) {
        var left: Float = 0
        var right: Float = 0
        var guitarLeft: Float = 0
        var guitarRight: Float = 0
        for guitar in guitars {
            let sample = guitar.next()
            guitarLeft += sample.0
            guitarRight += sample.1
        }
        (left, right) = guitarAmp.next(left: guitarLeft, right: guitarRight)
        for index in electronics.indices where electronics[index].active {
            let phase = electronics[index].phase
            let brightness = electronics[index].envelope
            let fm = wave(phase * 2.01) * 0.21 * brightness
            let value = wave(phase + Double(fm)) * min(electronics[index].age / attackFrames, 1) * brightness
            left += value * electronics[index].left
            right += value * electronics[index].right
            advance(&electronics[index])
        }
        return (left, right)
    }

    private func note(frequency: Double, tau: Double, gain: Float, pan: Float) -> Note {
        Note(active: true, phase: 0, increment: frequency * dt, age: 0, envelope: 1,
             decay: Float(exp(-dt / tau)), left: gain * (1 - max(pan, 0)), right: gain * (1 + min(pan, 0)))
    }

    private func advance(_ note: inout Note) {
        note.phase = wrapped(note.phase + note.increment)
        note.age += 1
        note.envelope *= note.decay
        if note.envelope < 0.001 { note.active = false }
    }

    private func updatePitch() {
        let semitone = voice == .metal ? Self.metalRiff[step] : Self.edmRiff[step]
        increment = 55 * pow(2, Double(semitone) / 12) * dt
    }

    private func wave(_ phase: Double) -> Float {
        let position = wrapped(phase) * Double(Self.tableSize)
        let index = Int(position)
        let fraction = Float(position - Double(index))
        return sine[index] + (sine[index + 1] - sine[index]) * fraction
    }

    private func wrapped(_ phase: Double) -> Double { phase - floor(phase) }

    private func nextNoise() -> Float {
        noiseState ^= noiseState << 13
        noiseState ^= noiseState >> 17
        noiseState ^= noiseState << 5
        return Float(Int32(bitPattern: noiseState)) / Float(Int32.max)
    }
}
