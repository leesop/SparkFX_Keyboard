// Native inference adapted from Magenta.js (Copyright 2018 Google Inc., Apache-2.0).
// Model sources and license: Resources/Models/README.md and LICENSE.txt.
import Foundation
import Accelerate

enum NeuralError: LocalizedError {
    case resources, weights, audio(OSStatus)
    var errorDescription: String? {
        switch self {
        case .resources: return L("neural.error.resources")
        case .weights: return L("neural.error.weights")
        case .audio(let status): return L("neural.error.audio") + " (\(status))"
        }
    }
}

/// Loads only local, float32 TF.js checkpoints. No network or TensorFlow runtime.
final class NeuralWeights {
    struct Tensor { let shape: [Int]; let values: [Float] }
    private struct Group: Decodable {
        struct Weight: Decodable { let name: String; let shape: [Int]; let dtype: String }
        let paths: [String]; let weights: [Weight]
    }
    private var tensors: [String: Tensor] = [:]

    init(directory: URL) throws {
        let groups = try JSONDecoder().decode([Group].self, from:
            Data(contentsOf: directory.appendingPathComponent("weights_manifest.json")))
        for group in groups {
            var data = Data()
            for path in group.paths {
                guard !path.contains("/"), !path.contains("..") else { throw NeuralError.weights }
                data.append(try Data(contentsOf: directory.appendingPathComponent(path)))
            }
            var offset = 0
            for weight in group.weights {
                guard weight.dtype == "float32", !weight.shape.isEmpty,
                      weight.shape.allSatisfy({ $0 > 0 && $0 <= 4096 }) else { throw NeuralError.weights }
                let count = weight.shape.reduce(1, *)
                guard count <= 8_000_000, offset + count * 4 <= data.count else { throw NeuralError.weights }
                // Files are little-endian float32; copy avoids relying on Data alignment.
                var values = [Float](repeating: 0, count: count)
                _ = values.withUnsafeMutableBytes { data.copyBytes(to: $0, from: offset..<(offset + count * 4)) }
                guard values.allSatisfy(\.isFinite) else { throw NeuralError.weights }
                tensors[weight.name] = Tensor(shape: weight.shape, values: values)
                offset += count * 4
            }
            guard offset == data.count else { throw NeuralError.weights }
        }
    }

    func tensor(_ name: String, shape: [Int]) throws -> [Float] {
        guard let tensor = tensors[name], tensor.shape == shape else { throw NeuralError.weights }
        return tensor.values
    }

    static func directory(_ name: String) throws -> URL {
        guard let root = Bundle.main.resourceURL else { throw NeuralError.resources }
        let url = root.appendingPathComponent("Models/\(name)", isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("weights_manifest.json").path)
        else { throw NeuralError.resources }
        return url
    }
}

private struct NeuralDense {
    let rows: Int, columns: Int
    let weights: [Float], bias: [Float]
    init(_ store: NeuralWeights, _ kernel: String, _ biasName: String, _ rows: Int, _ columns: Int) throws {
        self.rows = rows; self.columns = columns
        weights = try store.tensor(kernel, shape: [rows, columns])
        bias = try store.tensor(biasName, shape: [columns])
    }
    init(weights: [Float], rows: Int, columns: Int) {
        self.weights = weights; self.rows = rows; self.columns = columns
        bias = Array(repeating: 0, count: columns)
    }
    func call(_ input: [Float]) -> [Float] {
        precondition(input.count == rows)
        var result = bias
        cblas_sgemv(CblasRowMajor, CblasTrans, Int32(rows), Int32(columns),
                    1, weights, Int32(columns), input, 1, 1, &result, 1)
        return result
    }
}

/// TensorFlow basicLSTMCell gate order is i, j, f, o; forget bias is +1.
private final class NeuralLSTM {
    let units: Int
    private let dense: NeuralDense
    private var cell: [Float], hidden: [Float]
    init(_ weights: NeuralWeights, prefix: String, inputs: Int, units: Int) throws {
        self.units = units
        dense = try NeuralDense(weights, prefix + "kernel", prefix + "bias", inputs + units, units * 4)
        cell = Array(repeating: 0, count: units)
        hidden = cell
    }
    func reset() { cell = Array(repeating: 0, count: units); hidden = cell }
    var stateFeatures: [Float] { cell + hidden }
    func call(_ input: [Float]) -> [Float] {
        let gates = dense.call(input + hidden)
        for i in 0..<units {
            let incoming = 1 / (1 + exp(-gates[i]))
            let forget = 1 / (1 + exp(-(gates[2 * units + i] + 1)))
            let outgoing = 1 / (1 + exp(-gates[3 * units + i]))
            cell[i] = cell[i] * forget + incoming * tanh(gates[units + i])
            hidden[i] = tanh(cell[i]) * outgoing
        }
        return hidden
    }
}

struct NeuralRandom {
    var state: UInt64 = UInt64.random(in: 1...UInt64.max)
    mutating func unit() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(state >> 40) / Float(1 << 24)
    }
    mutating func sample(_ logits: [Float], temperature: Float, allowed: [Int]? = nil) -> Int {
        let choices = allowed ?? Array(logits.indices)
        let peak = choices.map { logits[$0] }.max() ?? 0
        let probabilities = choices.map { exp((logits[$0] - peak) / max(0.05, temperature)) }
        var value = unit() * probabilities.reduce(0, +)
        for (index, p) in zip(choices, probabilities) {
            value -= p
            if value <= 0 { return index }
        }
        return choices.last ?? 0
    }
}

final class PianoGenieModel {
    private let inputProjection: NeuralDense, outputProjection: NeuralDense
    private let layers: [NeuralLSTM]
    private var previous = -1

    init(directory: URL) throws {
        let w = try NeuralWeights(directory: directory)
        let prefix = "phero_model/decoder/"
        inputProjection = try NeuralDense(w, prefix + "rnn_input/dense/kernel", prefix + "rnn_input/dense/bias", 123, 128)
        outputProjection = try NeuralDense(w, prefix + "pitches/dense/kernel", prefix + "pitches/dense/bias", 128, 88)
        layers = try (0..<2).map {
            try NeuralLSTM(w, prefix: prefix + "rnn/rnn/multi_rnn_cell/cell_\($0)/lstm_cell/", inputs: 128, units: 128)
        }
    }
    func reset() { previous = -1; layers.forEach { $0.reset() } }
    func logits(button: Int, delta: Double) -> [Float] {
        var features = [Float](repeating: 0, count: 123)
        features[0] = Float(min(7, max(0, button))) * 2 / 7 - 1
        features[1 + previous + 1] = 1
        features[90 + min(32, max(0, Int((min(10, max(0, delta)) * 31.25).rounded())))] = 1
        var h = inputProjection.call(features)
        for layer in layers { h = layer.call(h) }
        return outputProjection.call(h)
    }
    func accept(pianoKey: Int) { previous = pianoKey }
    func next(button: Int, delta: Double, temperature: Float, range: ClosedRange<Int>, random: inout NeuralRandom) -> UInt8 {
        let scores = logits(button: button, delta: delta)
        let key = random.sample(scores, temperature: temperature, allowed: range.map { $0 - 21 })
        accept(pianoKey: key)
        return UInt8(key + 21)
    }
}

struct MusicChord {
    let root: Int
    let minor: Bool
    var pitches: [Int] { [root, (root + (minor ? 3 : 4)) % 12, (root + 7) % 12] }
    var encoding: [Float] {
        var vector = [Float](repeating: 0, count: 37)
        vector[1 + root] = 1
        for pitch in pitches { vector[13 + pitch] = 1 }
        vector[25 + root] = 1
        return vector
    }
}

/// Chord-conditioned ImprovRNN: 3 x 256 LSTM, 38 melody events, MIDI C3–B5.
final class MusicRNNModel {
    private let layers: [NeuralLSTM]
    private let output: NeuralDense
    init(directory: URL) throws {
        let w = try NeuralWeights(directory: directory)
        layers = try (0..<3).map {
            try NeuralLSTM(w, prefix: "rnn/multi_rnn_cell/cell_\($0)/basic_lstm_cell/",
                           inputs: $0 == 0 ? 75 : 256, units: 256)
        }
        output = try NeuralDense(w, "fully_connected/weights", "fully_connected/biases", 256, 38)
    }
    func reset() { layers.forEach { $0.reset() } }
    func logits(previousEvent: Int, nextChord: MusicChord) -> [Float] {
        var event = [Float](repeating: 0, count: 38)
        event[min(37, max(0, previousEvent))] = 1
        var h = nextChord.encoding + event
        for layer in layers { h = layer.call(h) }
        return output.call(h)
    }
    func next(previousEvent: Int, chord: MusicChord, temperature: Float, random: inout NeuralRandom) -> Int {
        random.sample(logits(previousEvent: previousEvent, nextChord: chord), temperature: temperature)
    }
}

/// MusicRNN drum_kit_rnn: 3 x 256 LSTM with a 32-step attention wrapper,
/// 512 drum-combination events and six binary beat-counter features.
final class DrumsRNNModel {
    static let pitches: [UInt8] = [36, 38, 42, 46, 45, 48, 50, 49, 51]
    private let layers: [NeuralLSTM]
    private let inputProjection: NeuralDense, queryProjection: NeuralDense
    private let historyProjection: NeuralDense, attentionOutput: NeuralDense, output: NeuralDense
    private let attentionVector: [Float]
    private var attention = [Float](repeating: 0, count: 256)
    private var history = [[Float]](repeating: [Float](repeating: 0, count: 256), count: 32)
    private var features = [[Float]](repeating: [Float](repeating: 0, count: 256), count: 32)
    private var counter = 0

    init(directory: URL) throws {
        let w = try NeuralWeights(directory: directory)
        let prefix = "rnn/attention_cell_wrapper/"
        layers = try (0..<3).map {
            try NeuralLSTM(w, prefix: prefix + "multi_rnn_cell/cell_\($0)/basic_lstm_cell/",
                           inputs: $0 == 0 ? 518 : 256, units: 256)
        }
        inputProjection = try NeuralDense(w, prefix + "kernel", prefix + "bias", 774, 518)
        // Upstream AttentionWrapper intentionally does not add attention/bias.
        queryProjection = NeuralDense(weights: try w.tensor(prefix + "attention/kernel", shape: [1536, 256]), rows: 1536, columns: 256)
        historyProjection = NeuralDense(weights: try w.tensor(prefix + "attention/attn_w", shape: [1, 1, 256, 256]), rows: 256, columns: 256)
        attentionVector = try w.tensor(prefix + "attention/attn_v", shape: [256])
        attentionOutput = try NeuralDense(w, prefix + "attention_output_projection/kernel", prefix + "attention_output_projection/bias", 512, 256)
        output = try NeuralDense(w, "fully_connected/weights", "fully_connected/biases", 256, 512)
    }
    func reset() {
        layers.forEach { $0.reset() }; counter = 0
        attention = Array(repeating: 0, count: 256)
        history = Array(repeating: attention, count: 32); features = history
    }
    func logits(previousEvent: Int) -> [Float] {
        var input = [Float](repeating: 0, count: 518)
        input[min(511, max(0, previousEvent))] = 1
        for bit in 0..<6 { input[512 + bit] = ((counter + 1) >> bit) & 1 == 1 ? 1 : -1 }
        counter = (counter + 1) % 64
        var h = inputProjection.call(input + attention)
        for layer in layers { h = layer.call(h) }
        let query = queryProjection.call(layers.flatMap(\.stateFeatures))
        var scores = [Float](repeating: 0, count: 32)
        for t in 0..<32 {
            for i in 0..<256 { scores[t] += attentionVector[i] * tanh(features[t][i] + query[i]) }
        }
        let peak = scores.max()!
        scores = scores.map { exp($0 - peak) }
        let total = scores.reduce(0, +)
        attention = Array(repeating: 0, count: 256)
        for t in 0..<32 {
            let weight = scores[t] / total
            for i in 0..<256 { attention[i] += weight * history[t][i] }
        }
        let result = attentionOutput.call(h + attention)
        history.removeFirst(); history.append(result)
        features.removeFirst(); features.append(historyProjection.call(result))
        return output.call(result)
    }
    func next(previousEvent: Int, temperature: Float, random: inout NeuralRandom) -> Int {
        random.sample(logits(previousEvent: previousEvent), temperature: temperature)
    }
}
