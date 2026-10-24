
private func checkModernAudio() throws {
    let sampleRate: Double = 48000
    // Input-driven effects must be silent until an event, and decay after it.
    for guitar in [true, false] {
        let synth = ModernSynth(sampleRate: sampleRate)
        synth.configure(voice: .pad, guitar: guitar, electronic: !guitar)
        for _ in 0..<480 {
            let sample = synth.nextKeys()
            try check(sample.0 == 0 && sample.1 == 0, "No key sound before input")
        }
        synth.noteInput(count: 1, guitar: guitar, electronic: !guitar)
        var early: Float = 0, late: Float = 0
        var attackEnergy: Double = 0, highEnergy: Double = 0, lowpass: Double = 0
        let toneCoef = 1 - exp(-2 * Double.pi * 1200 / sampleRate)
        for frame in 0..<144000 {
            let sample = synth.nextKeys()
            try check(sample.0.isFinite && sample.1.isFinite, "Finite key output")
            if frame < 12000 {
                let x = Double(sample.0)
                lowpass += (x - lowpass) * toneCoef
                attackEnergy += x * x
                highEnergy += (x - lowpass) * (x - lowpass)
            }
            if frame < 24000 { early = max(early, abs(sample.0), abs(sample.1)) }
            if frame > 120000 { late = max(late, abs(sample.0), abs(sample.1)) }
        }
        try check(early > 0.01 && late < early * 0.01, "Key attack and natural decay")
        if guitar {
            try check(sqrt(attackEnergy / 12000) > 0.05, "Driven guitar has a substantial attack")
            try check(highEnergy / attackEnergy > 0.035, "Driven guitar retains bright distorted harmonics")
            print("PASS driven guitar RMS=\(sqrt(attackEnergy/12000)) high-band ratio=\(highEnergy/attackEnergy)")
        }
        try check(synth.guitarStrikeCount == (guitar ? 1 : 0) && synth.electronicStrikeCount == (guitar ? 0 : 1), "Key routing")
        synth.noteInput(count: 100, guitar: guitar, electronic: !guitar)
        synth.configure(voice: .pad, guitar: false, electronic: false)
        let muted = synth.nextKeys()
        try check(muted.0 == 0 && muted.1 == 0, "Disabled key effect clears old voices")
        print("PASS \(guitar ? "guitar" : "electronic") key attack, decay, event routing and disable")
    }

    var fingerprints: [Double] = []
    for voice in [AmbientVoice.metal, .edm] {
        let synth = ModernSynth(sampleRate: sampleRate)
        synth.configure(voice: voice, guitar: false, electronic: false)
        var energy: Double = 0
        var peak: Float = 0
        for _ in 0..<144000 {
            let (left, right) = synth.nextBackground()
            try check(left.isFinite && right.isFinite, "Finite loop output")
            peak = max(peak, abs(left), abs(right))
            energy += Double(left * left + right * right)
        }
        try check(energy > 100 && peak < 0.9, "New loop is audible with headroom")
        fingerprints.append(energy)
        print("PASS \(voice.storedValue) loop peak=\(peak) energy=\(energy)")
    }
    try check(abs(fingerprints[0] - fingerprints[1]) > 100, "Metal and EDM produce distinct signals")

    // Stress the complete mix, including the reverb, at far above normal typing rate.
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    for voice in [AmbientVoice.metal, .edm] {
        let engine = AmbientEngine()
        let graph = engine.audioGraph
        try graph.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        engine.setVoice(voice)
        engine.setGrainsEnabled(true)
        engine.setChimesEnabled(true)
        engine.setGuitarEnabled(true)
        engine.setElectronicEnabled(true)
        engine.setPulseBPM(90)
        engine.setMaxLevel(1)
        engine.setEnabled(true)
        defer { engine.setEnabled(false); graph.stop() }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var peak: Float = 0
        var firstEnergy: Double = 0, lastEnergy: Double = 0
        for block in 0..<240 {
            if block < 120 { for _ in 0..<8 { engine.noteInput() } }
            if block == 160 { engine.setEnabled(false) }
            let result = try graph.renderOffline(4096, to: buffer)
            try check(result == .success, "Stress render")
            for channel in 0..<2 {
                for frame in 0..<Int(buffer.frameLength) {
                    let sample = buffer.floatChannelData![channel][frame]
                    try check(sample.isFinite, "No stress NaN or infinity")
                    peak = max(peak, abs(sample))
                    if block < 120 { firstEnergy += Double(sample * sample) }
                    if block > 220 { lastEnergy += Double(sample * sample) }
                }
            }
        }
        print("Measured stress mix \(voice.storedValue): peak=\(peak)")
        try check(peak < 1, "Entire stressed mix stays below clipping")
        try check(firstEnergy > 1 && lastEnergy < firstEnergy * 0.001, "Off fades all layers including reverb")
        print("PASS full \(voice.storedValue) stress mix peak=\(peak), all layers fade off")
    }
}
