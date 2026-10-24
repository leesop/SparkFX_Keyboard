import Foundation

enum NeuralInstrument: Int, CaseIterable {
    case automatic = -1
    case piano = 0, electricPiano = 4, musicBox = 10, vibraphone = 11, organ = 16
    case guitar = 24, strings = 48, saxophone = 65, flute = 73, lead = 80
    static var fixed: [NeuralInstrument] { allCases.filter { $0 != .automatic } }
    var key: String {
        switch self {
        case .automatic: return "automatic"
        case .piano: return "piano"
        case .electricPiano: return "electricPiano"
        case .musicBox: return "musicBox"
        case .vibraphone: return "vibraphone"
        case .organ: return "organ"
        case .guitar: return "guitar"
        case .strings: return "strings"
        case .saxophone: return "saxophone"
        case .flute: return "flute"
        case .lead: return "lead"
        }
    }
}

enum DrumStyle: String, CaseIterable {
    case rock, dance, halftime
    /// Original one-bar starters. Bit 0: kick, 1: snare, 2: closed hi-hat.
    var primer: [Int] {
        switch self {
        case .rock: return [5, 0, 4, 0, 6, 0, 4, 0, 5, 0, 4, 1, 6, 0, 4, 0]
        case .dance: return [5, 0, 4, 0, 7, 0, 8, 0, 5, 0, 4, 0, 7, 0, 8, 0]
        case .halftime: return [5, 0, 0, 4, 4, 0, 4, 0, 6, 0, 0, 4, 4, 0, 4, 0]
        }
    }
    func anchor(at position: Int) -> Int {
        switch self {
        case .rock: return position % 8 == 0 ? 1 : (position % 8 == 4 ? 2 : 0)
        case .dance: return position % 4 == 0 ? (position % 8 == 4 ? 3 : 1) : 0
        case .halftime: return position == 0 ? 1 : (position == 8 ? 2 : 0)
        }
    }
}

enum DrumDensity: String, CaseIterable {
    case sparse, balanced, busy
    func filter(_ event: Int, position: Int) -> Int {
        var mask = event & 511
        if self == .sparse {
            mask &= 7
            if position % 2 != 0 { mask &= 3 }
        }
        let limit = self == .busy ? 5 : (self == .sparse ? 3 : 4)
        var result = 0, count = 0
        for bit in 0..<9 where mask & (1 << bit) != 0 {
            if count < limit { result |= 1 << bit; count += 1 }
        }
        // Closed and open hi-hats should not strike together.
        if result & 4 != 0 { result &= ~8 }
        return result
    }
}

/// Robust input-rate estimate, bounded to a musical tempo and changed only per bar.
struct DrumTempoTracker {
    private var intervals: [Double] = []
    private(set) var target: Double = 90
    private(set) var bpm: Double = 90
    mutating func reset(base: Int) { intervals.removeAll(); target = Double(base); bpm = target }
    mutating func input(interval: Double) {
        guard interval.isFinite, interval >= 0.05, interval <= 1.5 else { return }
        intervals.append(interval)
        if intervals.count > 12 { intervals.removeFirst() }
        guard intervals.count >= 3 else { return }
        let sorted = intervals.sorted()
        let median = (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
        target = min(160, max(70, 60 + 12 / median))
    }
    mutating func beginBar(followInput: Bool, base: Int) {
        if followInput { bpm += min(12, max(-12, target - bpm)) }
        else { bpm = Double(base) }
    }
}

enum NeuralRegister: String, CaseIterable {
    case low, middle, high
    var range: ClosedRange<Int> {
        switch self {
        case .low: return 45...72
        case .middle: return 55...84
        case .high: return 67...96
        }
    }
}

enum NeuralVariation: String, CaseIterable {
    case calm, balanced, adventurous
    var temperature: Float {
        switch self {
        case .calm: return 0.35
        case .balanced: return 0.65
        case .adventurous: return 0.95
        }
    }
}

/// These are arrangement styles, not claims of separately genre-trained models.
enum NeuralArrangement: String, CaseIterable {
    case gentle, pop, electronic
    var chords: [MusicChord] {
        switch self {
        case .gentle: return [.init(root: 9, minor: true), .init(root: 5, minor: false),
                              .init(root: 0, minor: false), .init(root: 7, minor: false)]
        case .pop: return [.init(root: 0, minor: false), .init(root: 7, minor: false),
                           .init(root: 9, minor: true), .init(root: 5, minor: false)]
        case .electronic: return [.init(root: 0, minor: true), .init(root: 8, minor: false),
                                  .init(root: 3, minor: false), .init(root: 10, minor: false)]
        }
    }
}

struct NeuralSettings: Equatable {
    var instrument: NeuralInstrument = .piano
    var register: NeuralRegister = .middle
    var variation: NeuralVariation = .balanced
    var arrangement: NeuralArrangement = .gentle
    var tempo: Int = 90
    var accompaniment = true
    var continuation = true
    var volume: Float = 0.5
    var drumStyle: DrumStyle = .rock
    var drumDensity: DrumDensity = .balanced
    var followInputTempo = true
    static let tempos = [72, 90, 110, 128]
}

extension SoundMode {
    var isNeural: Bool { self == .pianoGenie || self == .musicRNN || self == .drumsRNN }
}

extension Prefs {
    static func neuralSettings(_ mode: SoundMode) -> NeuralSettings {
        let prefix = "neural.\(mode.rawValue)."
        var value = NeuralSettings()
        value.instrument = NeuralInstrument(rawValue: defaults.integer(forKey: prefix + "instrument")) ?? .piano
        value.register = NeuralRegister(rawValue: defaults.string(forKey: prefix + "register") ?? "") ?? .middle
        value.variation = NeuralVariation(rawValue: defaults.string(forKey: prefix + "variation") ?? "") ?? .balanced
        value.arrangement = NeuralArrangement(rawValue: defaults.string(forKey: prefix + "arrangement") ?? "") ?? .gentle
        value.drumStyle = DrumStyle(rawValue: defaults.string(forKey: prefix + "drumStyle") ?? "") ?? .rock
        value.drumDensity = DrumDensity(rawValue: defaults.string(forKey: prefix + "drumDensity") ?? "") ?? .balanced
        if defaults.object(forKey: prefix + "followInputTempo") != nil {
            value.followInputTempo = defaults.bool(forKey: prefix + "followInputTempo")
        }
        let tempo = defaults.integer(forKey: prefix + "tempo")
        value.tempo = NeuralSettings.tempos.contains(tempo) ? tempo : 90
        if defaults.object(forKey: prefix + "accompaniment") != nil {
            value.accompaniment = defaults.bool(forKey: prefix + "accompaniment")
        }
        if defaults.object(forKey: prefix + "continuation") != nil {
            value.continuation = defaults.bool(forKey: prefix + "continuation")
        }
        if defaults.object(forKey: prefix + "volume") != nil {
            let stored = defaults.float(forKey: prefix + "volume")
            value.volume = volumeOptions.min { abs($0 - stored) < abs($1 - stored) } ?? 0.5
        }
        return value
    }

    static func setNeuralSettings(_ value: NeuralSettings, for mode: SoundMode) {
        let prefix = "neural.\(mode.rawValue)."
        defaults.set(value.instrument.rawValue, forKey: prefix + "instrument")
        defaults.set(value.register.rawValue, forKey: prefix + "register")
        defaults.set(value.variation.rawValue, forKey: prefix + "variation")
        defaults.set(value.arrangement.rawValue, forKey: prefix + "arrangement")
        defaults.set(value.tempo, forKey: prefix + "tempo")
        defaults.set(value.accompaniment, forKey: prefix + "accompaniment")
        defaults.set(value.continuation, forKey: prefix + "continuation")
        defaults.set(value.volume, forKey: prefix + "volume")
        defaults.set(value.drumStyle.rawValue, forKey: prefix + "drumStyle")
        defaults.set(value.drumDensity.rawValue, forKey: prefix + "drumDensity")
        defaults.set(value.followInputTempo, forKey: prefix + "followInputTempo")
    }
}
