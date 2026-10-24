import Foundation

/// 앰비언트 음색.
enum AmbientVoice: Equatable {
    /// 필터를 통과시킨 노이즈. 바람·빗소리 느낌에 낮은 드론을 얹는다.
    case wind
    /// 살짝 어긋난 사인파를 겹친 따뜻한 패드.
    case pad
    case metal
    case edm
    /// 사용자가 고른 루프 파일.
    case loop(String)

    var storedValue: String {
        switch self {
        case .wind: return "wind"
        case .pad: return "pad"
        case .metal: return "metal"
        case .edm: return "edm"
        case .loop(let path): return "loop:\(path)"
        }
    }

    static let builtIn: [AmbientVoice] = [.wind, .pad, .metal, .edm]

    static func fromStoredValue(_ value: String) -> AmbientVoice {
        if value.hasPrefix("loop:") { return .loop(String(value.dropFirst("loop:".count))) }
        return builtIn.first { $0.storedValue == value } ?? .wind
    }

}

/// 풍경 하나. 부분음마다 감쇠가 달라서 배열로 들고 있는다.
private final class ChimeVoice {
    var isActive = false
    var phases = [Double](repeating: 0, count: AmbientSynth.chimeRatios.count)
    var levels = [Float](repeating: 0, count: AmbientSynth.chimeRatios.count)
    var increments = [Double](repeating: 0, count: AmbientSynth.chimeRatios.count)
    var decays = [Float](repeating: 1, count: AmbientSynth.chimeRatios.count)
    var gainLeft: Float = 1
    var gainRight: Float = 1

    /// 살아 있는 부분음이 하나도 없으면 꺼진 것으로 본다.
    func refreshActive() {
        isActive = levels.contains { $0 > 0.0002 }
    }
}

/// 앰비언트 소리를 만드는 DSP.
///
/// 일부러 `AVAudioEngine`과 떼어 두었다. 소리를 들을 수 없는 환경에서도 오프라인으로 렌더해
/// "활동량이 늘면 커지는가", "입력이 끊기면 1분쯤에 사라지는가"를 수치로 확인할 수 있게 하기 위해서다.
final class AmbientSynth {
    /// 오디오 스레드로 넘어오는 제어 값. 모두 값 타입이라 복사해 두고 쓰면 된다.
    struct Params {
        var voice: AmbientVoice = .wind
        /// 꺼져 있으면 소리를 내지 않는다. 켜고 끌 때 뚝 끊기지 않도록 서서히 여닫는다.
        var isEnabled: Bool = false
        var maxLevel: Float = 0.5
        /// 입력이 들어올 때마다 1씩 늘어난다. 렌더 쪽은 늘어난 만큼 활동량을 더한다.
        var eventCount: UInt64 = 0
        /// 클릭 소리가 날 때마다 1씩 늘어난다. 앰비언트를 잠깐 눌러 주는 데 쓴다.
        var duckCount: UInt64 = 0
        /// 입력마다 음 하나를 띄우는 알갱이를 켤지.
        var grainsEnabled: Bool = false
        /// 배경을 이 박자로 맥동시킨다. 0이면 박자 없음.
        var pulseBPM: Float = 0
        /// 어떤 음색 위에도 처마 풍경 소리를 얹는다. 바람(활동량)이 세면 자주 울린다.
        var chimesEnabled: Bool = false
        var guitarEnabled: Bool = false
        var electronicEnabled: Bool = false
    }

    /// 띄우는 음 하나. 클릭마다 새로 만들어 오래된 것부터 버린다.
    private struct Grain {
        var isActive = false
        var phase: Double = 0
        var increment: Double = 0
        var age: Float = 0
        var decayLevel: Float = 0
        var decayCoef: Float = 0
        var gainLeft: Float = 0
        var gainRight: Float = 0
    }

    /// 활동량이 잦아드는 시간 상수(초). 이만큼 빠르게 줄어야 타건에 반응하는 느낌이 난다.
    private static let activityTau: Float = 1.5
    /// 입력이 끊긴 뒤 사라지기까지의 시간 상수(초). 약 30초에 걸쳐 잦아든다.
    private static let idleTau: Float = 12
    /// 이만큼(초당 입력 수)이면 최대로 본다.
    private static let rateForFullLevel: Float = 8
    /// 활동량이 차오르는 데 걸리는 시간(초). 타건에 바로 반응해야 하므로 짧다.
    private static let levelRise: Float = 0.35
    /// 활동량이 잦아드는 시간(초). 타건이 멈춘 뒤 서서히 물러나야 하므로 길다.
    private static let levelFall: Float = 6
    private static let duckTau: Float = 0.02
    private static let duckDepth: Float = 0.45
    private static let duckHold: Float = 0.08
    /// 아무리 조용해도 남겨 두는 바닥 음량. 유휴 페이드가 이 위에 곱해진다.
    /// 너무 낮으면 활동량에 따른 변화가 잘 안 들린다.
    private static let minGain: Float = 0.15
    /// 동시에 살아 있을 수 있는 알갱이 수. 넘치면 가장 오래된 것을 밀어낸다.
    private static let grainVoices = 16
    /// 알갱이 하나의 크기. 최대 음량에서도 클리핑하지 않도록 잡았다.
    private static let grainGain: Float = 0.11
    /// 알갱이가 잦아드는 시간(초).
    private static let grainDecayTau: Float = 0.45
    private static let grainAttack: Float = 0.005
    /// A 단조 펜타토닉 두 옥타브. 알갱이는 이 위를 무작위 걸음으로 오간다.
    private static let grainScale: [Int] = [0, 3, 5, 7, 10, 12, 15, 17, 19, 22]
    /// 출력 리미터. 이 아래에서는 거의 그대로 두고, 넘어서면 부드럽게 눌러 준다.
    /// 배경음·알갱이·풍경이 우연히 겹쳐도 찢어지지 않게 하는 안전장치다.
    private static let limiterKnee: Float = 0.45
    private static let limiterCeiling: Float = 0.88
    /// 동시에 울릴 수 있는 풍경 수.
    private static let chimeVoices = 6
    /// 풍경 하나의 크기. 최대 음량에서도 클리핑하지 않도록 잡았다.
    private static let chimeGain: Float = 0.10
    /// 풍경이 울리는 빈도(초당). 조용할 때와 바쁠 때.
    private static let chimeRestRate: Float = 0.12
    private static let chimeActiveRate: Float = 1.1
    /// 풍경의 세 음. A 단조 화음의 높은 자리.
    private static let chimePitches: [Double] = [880, 1046.5, 1318.5]
    /// 종의 부분음 비율과, 부분음마다 다른 감쇠 시간(초)·크기. 높은 배음일수록 빨리 사라진다.
    fileprivate static let chimeRatios: [Double] = [1.0, 2.0, 2.76, 5.4]
    private static let chimeTaus: [Float] = [3.4, 2.1, 1.3, 0.7]
    private static let chimeGains: [Float] = [1.0, 0.5, 0.26, 0.14]
    /// 박자를 탈 때 눌리는 깊이와, 눌린 뒤 풀리는 시간(초).
    private static let pulseDepth: Float = 0.5
    private static let pulseDecayTau: Float = 0.12

    /// 살짝 어긋난 사인 성부들로 이루어진 A 단조 화음.
    private static let padRatios: [Double] = [1.0, 1.003, 1.189, 1.192, 1.498, 2.0]

    let sampleRate: Double
    private let modern: ModernSynth

    // MARK: 렌더 스레드만 건드리는 상태
    private var activity: Float = 0
    private var idleSeconds: Float = 0
    private var duckAge: Float = 1000
    private var duckValue: Float = 0
    private var seenEvents: UInt64 = 0
    private var seenDucks: UInt64 = 0
    private var level: Float = 0
    private var maxLevel: Float = 0.5
    private var idleFactor: Float = 0
    private var duckFactor: Float = 1
    private var enabledGain: Float = 0
    private var rngLeft: UInt32 = 0x9E37_79B9
    private var rngRight: UInt32 = 0x85EB_CA6B
    private var rumbleLeft: Float = 0
    private var rumbleRight: Float = 0
    private var lowpassLeft: Float = 0
    private var lowpassRight: Float = 0
    private var padPhaseLeft = [Double](repeating: 0, count: AmbientSynth.padRatios.count)
    private var padPhaseRight = [Double](repeating: 0, count: AmbientSynth.padRatios.count)
    private var lfoPhase: Double = 0
    private var dronePhase: Double = 0
    private var loopLeft: [Float] = []
    private var loopRight: [Float] = []
    private var loopPosition: Double = 0
    private var grains = [Grain](repeating: Grain(), count: AmbientSynth.grainVoices)
    private var grainCursor = 0
    private var grainScaleIndex = 4
    private var grainRng: UInt32 = 0x1234_5678
    private let chimes = (0..<AmbientSynth.chimeVoices).map { _ in ChimeVoice() }
    private var chimeCursor = 0
    private var chimeAccumulator: Float = 0
    private var chimeRng: UInt32 = 0x51ED_2789
    private var beatAge: Float = 1000
    private var beatAccumulator: Float = 0
    private var pulseFactor: Float = 1

    /// 마지막으로 그린 블록의 최대 크기. 진단·검증용.
    private(set) var lastRenderPeak: Float = 0
    /// 지금까지 울린 풍경 횟수. 진단·검증용.
    private(set) var chimeStrikeCount: Int = 0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        modern = ModernSynth(sampleRate: sampleRate)
        // 좌우 성부를 조금 어긋나게 시작해 패드가 넓게 퍼지게 한다.
        for index in padPhaseRight.indices {
            padPhaseRight[index] = 0.7 + Double(index) * 0.5
        }
    }

    /// 루프 파일을 엔진 샘플레이트의 좌우 채널로 받아 둔다.
    func setLoop(left: [Float], right: [Float]) {
        loopLeft = left
        loopRight = right
        loopPosition = 0
    }

    var hasLoop: Bool { !loopLeft.isEmpty }

    /// 프레임 수만큼 만들어 좌우 버퍼에 채운다.
    func render(frames: Int, params: Params, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        let dt = Float(1 / sampleRate)
        modern.configure(voice: params.voice, guitar: params.guitarEnabled, electronic: params.electronicEnabled)
        // 엔벨로프는 이 블록을 한 번에 갱신하므로 블록 길이만큼 시간이 흘러야 한다.
        // 샘플 단위 dt를 넘기면 엔벨로프가 블록 크기만큼 느려진다.
        updateEnvelopes(dt: Float(frames) / Float(sampleRate), params: params)

        // 활동량에 따라 밝기가 300Hz~10kHz 사이를 오간다.
        let cutoff = 300 * powf(33, level)
        let cutoffCoef = 1 - expf(-2 * .pi * cutoff * dt)
        let rumbleCoef = onepoleCoef(55, dt)
        let step = 2 * Double.pi / sampleRate
        let gain = currentGain

        var peak: Float = 0

        for frame in 0..<frames {
            var sampleLeft: Float = 0
            var sampleRight: Float = 0

            switch params.voice {
            case .wind:
                let left_noise = nextNoise(&rngLeft)
                let right_noise = nextNoise(&rngRight)
                // 낮은 성분을 빼서 바람 같은 숨소리를 만든다.
                rumbleLeft += (left_noise - rumbleLeft) * rumbleCoef
                rumbleRight += (right_noise - rumbleRight) * rumbleCoef
                lowpassLeft += (left_noise - rumbleLeft - lowpassLeft) * cutoffCoef
                lowpassRight += (right_noise - rumbleRight - lowpassRight) * cutoffCoef

                // 아래에 낮은 드론(A1 + E2)을 얹어 따뜻하게 받친다.
                dronePhase += step * 55
                if dronePhase > 2 * .pi { dronePhase -= 2 * .pi }
                let drone = Float(sin(dronePhase) * 0.5 + sin(dronePhase * 1.5) * 0.35)
                    * 0.07 * (0.4 + level)

                // 뒤에 리버브가 더해지므로 최대 음량에서도 클리핑하지 않도록 여유를 남긴다.
                sampleLeft = lowpassLeft * 0.55 + drone
                sampleRight = lowpassRight * 0.55 + drone

            case .pad:
                lfoPhase += step * 0.07
                if lfoPhase > 2 * .pi { lfoPhase -= 2 * .pi }
                var sumLeft: Float = 0
                var sumRight: Float = 0
                for index in padPhaseLeft.indices {
                    let increment = step * 110 * Self.padRatios[index]
                    padPhaseLeft[index] = wrap(padPhaseLeft[index] + increment)
                    padPhaseRight[index] = wrap(padPhaseRight[index] + increment)
                    // 성부마다 아주 느리게 흔들어 숨 쉬는 느낌을 준다.
                    let breath = 0.75 + 0.25 * sin(lfoPhase + Double(index) * 1.3)
                    sumLeft += Float(sin(padPhaseLeft[index]) * breath)
                    sumRight += Float(sin(padPhaseRight[index]) * breath)
                }
                let scale = 0.8 / Float(padPhaseLeft.count)
                lowpassLeft += (sumLeft * scale - lowpassLeft) * cutoffCoef
                lowpassRight += (sumRight * scale - lowpassRight) * cutoffCoef
                sampleLeft = lowpassLeft
                sampleRight = lowpassRight

            case .metal, .edm:
                (sampleLeft, sampleRight) = modern.nextBackground()

            case .loop:
                let (loopL, loopR) = nextLoopSample()
                lowpassLeft += (loopL - lowpassLeft) * cutoffCoef
                lowpassRight += (loopR - lowpassRight) * cutoffCoef
                sampleLeft = lowpassLeft
                sampleRight = lowpassRight
            }

            var outLeft = sampleLeft * pulseFactor * gain
            var outRight = sampleRight * pulseFactor * gain

            var (keyLeft, keyRight) = modern.nextKeys()
            if params.grainsEnabled {
                mixGrains(into: &keyLeft, into: &keyRight, dt: dt)
            }
            if params.chimesEnabled {
                mixChimes(into: &keyLeft, into: &keyRight)
            }

            outLeft += keyLeft * enabledGain * idleFactor
            outRight += keyRight * enabledGain * idleFactor

            outLeft = limit(outLeft)
            outRight = limit(outRight)
            left[frame] = outLeft
            right[frame] = outRight
            peak = max(peak, max(abs(outLeft), abs(outRight)))
        }

        lastRenderPeak = peak
    }

    // MARK: - 엔벨로프

    private var currentGain: Float {
        let base = Self.minGain + level * (maxLevel - Self.minGain)
        return base * idleFactor * duckFactor * enabledGain
    }

    private func updateEnvelopes(dt: Float, params: Params) {
        maxLevel = params.maxLevel

        // 켜고 끌 때 튀지 않도록 0.15초쯤에 걸쳐 여닫는다.
        let enabledTarget: Float = params.isEnabled ? 1 : 0
        enabledGain += (enabledTarget - enabledGain) * (1 - expf(-dt / 0.15))

        let newEvents = params.eventCount &- seenEvents
        seenEvents = params.eventCount
        if newEvents > 0 {
            activity += Float(min(newEvents, 16))
            idleSeconds = 0
            if params.isEnabled {
                modern.noteInput(count: Int(min(newEvents, 4)), guitar: params.guitarEnabled, electronic: params.electronicEnabled)
            }
            if params.grainsEnabled && params.isEnabled {
                // 한 블록에 너무 많이 몰리면 소리가 뭉개진다.
                for _ in 0..<min(newEvents, 4) { spawnGrain() }
            }
        }

        let newDucks = params.duckCount &- seenDucks
        seenDucks = params.duckCount
        if newDucks > 0 {
            duckAge = 0
        }

        // 활동량은 지수적으로 잦아들고, 그 적분이 곧 "지금 얼마나 바쁜가"가 된다.
        activity *= expf(-dt / Self.activityTau)
        let rate = activity / Self.activityTau
        let target = min(rate / Self.rateForFullLevel, 1)
        let levelTau = target > level ? Self.levelRise : Self.levelFall
        level += (target - level) * (1 - expf(-dt / levelTau))

        idleSeconds += dt
        idleFactor = expf(-idleSeconds / Self.idleTau)

        duckAge += dt
        duckValue += ((duckAge < Self.duckHold ? 1 : 0) - duckValue) * (1 - expf(-dt / Self.duckTau))
        duckFactor = 1 - Self.duckDepth * duckValue

        // 풍경: 바람이 세면(활동량이 크면) 자주 울린다. 어떤 음색 위에도 얹힌다.
        if params.chimesEnabled && params.isEnabled {
            chimeAccumulator += (Self.chimeRestRate + Self.chimeActiveRate * level) * dt
            var strikes = 0
            while chimeAccumulator >= 1, strikes < 4 {
                chimeAccumulator -= 1
                strikeChime(strength: 0.55 + 0.45 * nextUniform(&chimeRng))
                strikes += 1
            }
        }

        // 박자: 일정 간격마다 배경을 한 번씩 눌렀다 놓는다.
        if params.pulseBPM > 1 {
            let beatSeconds = 60 / params.pulseBPM
            beatAccumulator += dt
            if beatAccumulator >= beatSeconds {
                beatAccumulator -= beatSeconds
                beatAge = 0
            }
            beatAge += dt
            pulseFactor = 1 - Self.pulseDepth * expf(-beatAge / Self.pulseDecayTau)
        } else {
            pulseFactor = 1
        }
    }

    /// 입력 하나에 음을 하나 띄운다. 무작위 걸음으로 음정을 고르고 좌우로 살짝 민다.
    private func spawnGrain() {
        let step = Int(nextUniform(&grainRng) * 5) - 2
        grainScaleIndex = min(max(grainScaleIndex + step, 0), Self.grainScale.count - 1)
        let semitone = Double(Self.grainScale[grainScaleIndex])
        let frequency = 220 * pow(2, semitone / 12)
        let pan = nextUniform(&grainRng) * 0.6 - 0.3

        var grain = Grain()
        grain.isActive = true
        grain.increment = 2 * .pi * frequency / sampleRate
        grain.decayLevel = 1
        grain.decayCoef = expf(-Float(1 / sampleRate) / Self.grainDecayTau)
        grain.gainLeft = Self.grainGain * (1 - max(pan, 0))
        grain.gainRight = Self.grainGain * (1 + min(pan, 0))

        grains[grainCursor] = grain
        grainCursor = (grainCursor + 1) % grains.count
    }

    /// 풍경을 한 번 울린다. 세기와 음정이 매번 조금씩 다르다.
    private func strikeChime(strength: Float) {
        let pitchIndex = min(Int(nextUniform(&chimeRng) * Float(Self.chimePitches.count)),
                             Self.chimePitches.count - 1)
        // 바람이 세게 불면 음이 아주 살짝 흔들린다.
        let detune = Double(nextUniform(&chimeRng) - 0.5) * 0.006
        let base = Self.chimePitches[pitchIndex] * (1 + detune)

        let voice = chimes[chimeCursor]
        chimeCursor = (chimeCursor + 1) % chimes.count
        voice.isActive = true
        chimeStrikeCount += 1
        for index in Self.chimeRatios.indices {
            voice.phases[index] = 0
            voice.increments[index] = 2 * .pi * base * Self.chimeRatios[index] / sampleRate
            voice.decays[index] = expf(-Float(1 / sampleRate) / Self.chimeTaus[index])
            voice.levels[index] = strength * Self.chimeGain * Self.chimeGains[index]
        }
        let pan = nextUniform(&chimeRng) * 0.5 - 0.25
        voice.gainLeft = 1 - max(pan, 0)
        voice.gainRight = 1 + min(pan, 0)
    }

    /// 울리고 있는 풍경들을 합쳐 좌우로 돌려준다.
    private func mixChimes(into left: inout Float, into right: inout Float) {
        for voice in chimes where voice.isActive {
            var sample: Float = 0
            for index in Self.chimeRatios.indices {
                sample += Float(sin(voice.phases[index])) * voice.levels[index]
                voice.phases[index] += voice.increments[index]
                if voice.phases[index] > 2 * .pi { voice.phases[index] -= 2 * .pi }
                voice.levels[index] *= voice.decays[index]
            }
            left += sample * voice.gainLeft
            right += sample * voice.gainRight
            voice.refreshActive()
        }
    }
    private func nextUniform(_ state: inout UInt32) -> Float {
        (nextNoise(&state) + 1) / 2
    }

    /// 살아 있는 알갱이들을 합쳐 좌우로 돌려준다.
    private func mixGrains(into left: inout Float, into right: inout Float, dt: Float) {
        let attackFrames = max(Self.grainAttack / dt, 1)
        for index in grains.indices where grains[index].isActive {
            let envelope = min(grains[index].age / attackFrames, 1) * grains[index].decayLevel
            let sample = Float(sin(grains[index].phase) + 0.3 * sin(grains[index].phase * 2)) * envelope
            left += sample * grains[index].gainLeft
            right += sample * grains[index].gainRight

            grains[index].phase += grains[index].increment
            if grains[index].phase > 2 * .pi { grains[index].phase -= 2 * .pi }
            grains[index].age += 1
            grains[index].decayLevel *= grains[index].decayCoef
            if grains[index].decayLevel < 0.001 { grains[index].isActive = false }
        }
    }

    // MARK: - 소리 재료

    /// 부드러운 리미터. knee 아래는 그대로, 위는 tanh로 눌러 ceiling을 넘지 않는다.
    private func limit(_ value: Float) -> Float {
        let knee = Self.limiterKnee
        guard abs(value) > knee else { return value }
        let sign: Float = value < 0 ? -1 : 1
        let range = Self.limiterCeiling - knee
        return sign * (knee + range * tanhf((abs(value) - knee) / range))
    }

    private func onepoleCoef(_ hz: Float, _ dt: Float) -> Float {
        1 - expf(-2 * .pi * hz * dt)
    }

    private func wrap(_ phase: Double) -> Double {
        phase > 2 * .pi ? phase - 2 * .pi : phase
    }

    private func nextNoise(_ state: inout UInt32) -> Float {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Float(Int32(bitPattern: state)) / Float(Int32.max)
    }

    /// 루프를 선형 보간으로 읽는다. 끝에 닿으면 처음으로 돌아간다.
    private func nextLoopSample() -> (Float, Float) {
        guard !loopLeft.isEmpty else { return (0, 0) }

        let index = Int(loopPosition)
        let next = (index + 1) % loopLeft.count
        let fraction = Float(loopPosition - Double(index))
        let leftSample = loopLeft[index] + (loopLeft[next] - loopLeft[index]) * fraction
        let rightSample = loopRight.indices.contains(next)
            ? loopRight[index] + (loopRight[next] - loopRight[index]) * fraction
            : leftSample

        loopPosition += 1
        if loopPosition >= Double(loopLeft.count) { loopPosition = 0 }
        return (leftSample, rightSample)
    }
}
