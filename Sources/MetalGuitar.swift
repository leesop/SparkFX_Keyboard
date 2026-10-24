import Foundation

/// A damped travelling wave excited by a noisy pick, rather than a bank of oscillators.
/// Delay lines and excitation memory are allocated once, outside the render callback.
/// Background: https://www.dsprelated.com/freebooks/pasp/Electric_Guitars.html
private final class PickedString {
    private var buffer: [Float]
    private var excitation: [Float]
    private let mask: Int
    private let sampleRate: Double
    private var cursor = 0
    private var delay = 1
    private var fraction: Float = 0
    private var pickupOffset = 1
    private var previous: Float = 0
    private var random: UInt32

    init(sampleRate: Double, seed: UInt32) {
        self.sampleRate = sampleRate
        random = seed
        var capacity = 1
        while Double(capacity) < sampleRate / 55 + 8 { capacity *= 2 }
        mask = capacity - 1
        buffer = [Float](repeating: 0, count: capacity)
        excitation = [Float](repeating: 0, count: capacity)
    }

    func pluck(frequency: Double) {
        let period = max(2, min(sampleRate / frequency - 0.22, Double(mask - 2)))
        delay = Int(period)
        fraction = Float(period - Double(delay))
        pickupOffset = max(1, Int(period * 0.13))
        let length = delay + 2
        var mean: Float = 0
        var pickLowpass: Float = 0
        for index in 0..<length {
            random ^= random << 13
            random ^= random >> 17
            random ^= random << 5
            let noise = Float(Int32(bitPattern: random)) / Float(Int32.max)
            pickLowpass += (noise - pickLowpass) * 0.72
            excitation[index] = pickLowpass
            mean += pickLowpass
        }
        mean /= Float(length)
        let pickPosition = max(1, Int(period * 0.22))
        for index in buffer.indices {
            let a = excitation[index % length] - mean
            let b = excitation[(index + pickPosition) % length] - mean
            buffer[index] = (a - b * 0.75) * 0.7
        }
        previous = 0
        cursor = 0
    }

    func next() -> Float {
        let first = buffer[(cursor - delay) & mask]
        let second = buffer[(cursor - delay - 1) & mask]
        let value = first + (second - first) * fraction
        let pickup = value - buffer[(cursor - pickupOffset) & mask] * 0.55
        buffer[cursor] = (value * 0.78 + previous * 0.22) * 0.9985
        previous = value
        cursor = (cursor + 1) & mask
        return pickup
    }
}

/// Two independently excited takes, each with root, fifth and octave strings.
final class MetalGuitarVoice {
    private let strings: [PickedString]
    private let dt: Double
    private var age: Double = 0
    private var tau: Double = 0.26
    private var leftGain: Float = 1
    private var rightGain: Float = 1
    private(set) var isActive = false

    init(sampleRate: Double, seed: UInt32) {
        dt = 1 / sampleRate
        strings = (0..<6).map { PickedString(sampleRate: sampleRate, seed: seed &+ UInt32($0 + 1) &* 0x9E37_79B9) }
    }

    func pluck(frequency: Double, palmMuted: Bool, pan: Float) {
        let ratios: (Double, Double, Double) = (1, 1.4983, 2)
        strings[0].pluck(frequency: frequency * ratios.0)
        strings[1].pluck(frequency: frequency * ratios.1)
        strings[2].pluck(frequency: frequency * ratios.2)
        strings[3].pluck(frequency: frequency * ratios.0 * 0.996)
        strings[4].pluck(frequency: frequency * ratios.1 * 0.997)
        strings[5].pluck(frequency: frequency * ratios.2 * 0.998)
        age = 0
        tau = palmMuted ? 0.15 : 0.26
        leftGain = 1 - max(pan, 0)
        rightGain = 1 + min(pan, 0)
        isActive = true
    }

    func stop() { isActive = false }

    func next() -> (Float, Float) {
        guard isActive else { return (0, 0) }
        let attack = min(age / 0.0015, 1)
        let envelope = Float(attack * exp(-age / tau))
        var left: Float = 0, right: Float = 0
        if age >= 0 { left += strings[0].next() * 0.62 }
        if age >= 0.0015 { left += strings[1].next() * 0.44 }
        if age >= 0.0035 { left += strings[2].next() * 0.28 }
        if age >= 0.0007 { right += strings[3].next() * 0.62 }
        if age >= 0.0028 { right += strings[4].next() * 0.44 }
        if age >= 0.0046 { right += strings[5].next() * 0.28 }
        age += dt
        if age > 2.4 { isActive = false }
        return ((left * 0.88 + right * 0.12) * envelope * leftGain,
                (right * 0.88 + left * 0.12) * envelope * rightGain)
    }
}

private struct GuitarFilter {
    private let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    private var z1: Double = 0, z2: Double = 0

    init(frequency: Double, sampleRate: Double, highpass: Bool = false, gainDB: Double? = nil) {
        let w = 2 * Double.pi * frequency / sampleRate
        let cosine = cos(w), alpha = sin(w) / (2 * 0.707)
        let a0: Double
        if let gainDB {
            let a = pow(10, gainDB / 40)
            a0 = 1 + alpha / a
            b0 = (1 + alpha * a) / a0
            b1 = -2 * cosine / a0
            b2 = (1 - alpha * a) / a0
            a1 = -2 * cosine / a0
            a2 = (1 - alpha / a) / a0
        } else {
            a0 = 1 + alpha
            b0 = (highpass ? (1 + cosine) : (1 - cosine)) / (2 * a0)
            b1 = (highpass ? -(1 + cosine) : (1 - cosine)) / a0
            b2 = b0
            a1 = -2 * cosine / a0
            a2 = (1 - alpha) / a0
        }
    }

    mutating func next(_ input: Float) -> Float {
        let x = Double(input)
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return Float(y)
    }

    mutating func reset() { z1 = 0; z2 = 0 }
}

/// Two oversampled preamp stages followed by a resonant closed-back cabinet.
final class MetalGuitarAmp {
    private struct Channel {
        var tight: GuitarFilter
        var dc: GuitarFilter
        var body: GuitarFilter
        var presence: GuitarFilter
        var speaker1: GuitarFilter
        var speaker2: GuitarFilter
        var previous: Float = 0
        var midLowpass: Float = 0
        let midCoef: Float

        init(sampleRate: Double) {
            let rate = sampleRate * 2
            tight = GuitarFilter(frequency: 78, sampleRate: rate, highpass: true)
            dc = GuitarFilter(frequency: 35, sampleRate: rate, highpass: true)
            body = GuitarFilter(frequency: 145, sampleRate: rate, gainDB: 3)
            presence = GuitarFilter(frequency: 1900, sampleRate: rate, gainDB: 4)
            speaker1 = GuitarFilter(frequency: 4400, sampleRate: rate)
            speaker2 = GuitarFilter(frequency: 5800, sampleRate: rate)
            midCoef = Float(1 - exp(-2 * .pi * 1100 / rate))
        }

        mutating func next(_ input: Float) -> Float {
            var output: Float = 0
            for step in 1...2 {
                let x = previous + (input - previous) * Float(step) * 0.5
                let first = tanhf(tight.next(x) * 18)
                midLowpass += (first - midLowpass) * midCoef
                let voiced = first - midLowpass * 0.38
                let second = tanhf((voiced + 0.015) * 2.6) - tanhf(0.039)
                let cab = speaker2.next(speaker1.next(presence.next(body.next(dc.next(second)))))
                output += cab * 0.5
            }
            previous = input
            return 0.26 * tanhf(output * 0.20 / 0.26)
        }

        mutating func reset() {
            tight.reset(); dc.reset(); body.reset(); presence.reset(); speaker1.reset(); speaker2.reset()
            previous = 0
            midLowpass = 0
        }
    }

    private var left: Channel
    private var right: Channel

    init(sampleRate: Double) {
        left = Channel(sampleRate: sampleRate)
        right = Channel(sampleRate: sampleRate)
    }

    func next(left: Float, right: Float) -> (Float, Float) {
        (self.left.next(left), self.right.next(right))
    }

    func reset() { left.reset(); right.reset() }
}
