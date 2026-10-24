import AVFoundation
import os

/// 오디오 스레드와 나눠 쓰는 제어 값 상자.
/// 오디오 쪽은 절대 기다리지 않는다 — 락을 못 잡으면 직전 값을 그대로 쓴다.
private final class AmbientParamsBox {
    let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    private var params = AmbientSynth.Params(isEnabled: false)

    init() {
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    func publish(_ mutate: (inout AmbientSynth.Params) -> Void) {
        os_unfair_lock_lock(lock)
        mutate(&params)
        os_unfair_lock_unlock(lock)
    }

    func snapshot(keeping last: inout AmbientSynth.Params) {
        if os_unfair_lock_trylock(lock) {
            last = params
            os_unfair_lock_unlock(lock)
        }
    }

    var current: AmbientSynth.Params {
        os_unfair_lock_lock(lock)
        let copy = params
        os_unfair_lock_unlock(lock)
        return copy
    }
}

/// 앰비언트를 실제 소리로 낸다.
///
/// 그래프: 합성기(`AVAudioSourceNode`) → 리버브 → 출력.
/// 클릭 소리는 `NSSound`로 따로 나가므로, 클릭이 날 때 `noteClick()`으로 알려 주면
/// 앰비언트를 잠깐 눌러 준다.
final class AmbientEngine {
    private static let sampleRate: Double = 48000
    /// 리버브를 섞는 정도(%). 활동량과 무관하게 고정이라 소리가 튀지 않는다.
    private static let reverbMix: Float = 32
    /// Fixed output calibration leaves headroom for reverb and overlapping key voices.
    /// The user volume remains a relative multiplier applied to this calibrated mix.
    private static let outputHeadroom: Float = 0.65
    /// 끌 때 이만큼 기다렸다가 엔진을 멈춘다. 그래야 뚝 끊기지 않는다.
    private static let fadeOutSeconds = 0.5
    /// 루프 파일이 지나치게 길면 메모리를 많이 쓴다.
    private static let maxLoopSeconds: Double = 600

    private let format: AVAudioFormat
    private let synth: AmbientSynth
    private let box = AmbientParamsBox()
    private let synthNode: AVAudioSourceNode
    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private var isRunning = false

    private(set) var voice: AmbientVoice = .wind
    private(set) var maxLevel: Float = 0.5
    private(set) var isEnabled = false
    private(set) var grainsEnabled = false
    private(set) var chimesEnabled = false
    private(set) var guitarEnabled = false
    private(set) var electronicEnabled = false
    private(set) var pulseBPM: Float = 0
    /// 루프 파일을 읽지 못했을 때 마지막 오류 설명.
    private(set) var lastLoopError: String?

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: AmbientEngine.sampleRate, channels: 2)!
        synth = AmbientSynth(sampleRate: AmbientEngine.sampleRate)
        // 시작은 꺼진 상태. 켜 달라고 할 때 소리가 난다.
        let boxRef = box
        let synthRef = synth
        var lastSnapshot = AmbientSynth.Params(isEnabled: false)
        synthNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }

            boxRef.snapshot(keeping: &lastSnapshot)
            synthRef.render(
                frames: Int(frameCount),
                params: lastSnapshot,
                left: left,
                right: right
            )
            return noErr
        }

        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = AmbientEngine.reverbMix

        engine.attach(synthNode)
        engine.attach(reverb)
        engine.connect(synthNode, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = maxLevel * Self.outputHeadroom
    }

    deinit {
        engine.stop()
    }

    // MARK: - 설정

    func setVoice(_ newVoice: AmbientVoice) {
        guard newVoice != voice else { return }
        voice = newVoice
        publish { $0.voice = newVoice }
    }

    func setMaxLevel(_ level: Float) {
        // Scale the complete mix, including grains, chimes and reverb.
        // Synth gain stays at its calibrated default (0.5).
        maxLevel = min(max(level, 0), 1)
        engine.mainMixerNode.outputVolume = maxLevel * Self.outputHeadroom
    }

    func setGrainsEnabled(_ enabled: Bool) {
        grainsEnabled = enabled
        publish { $0.grainsEnabled = enabled }
    }

    func setChimesEnabled(_ enabled: Bool) {
        chimesEnabled = enabled
        publish { $0.chimesEnabled = enabled }
    }

    func setGuitarEnabled(_ enabled: Bool) {
        guitarEnabled = enabled
        publish { $0.guitarEnabled = enabled }
    }

    func setElectronicEnabled(_ enabled: Bool) {
        electronicEnabled = enabled
        publish { $0.electronicEnabled = enabled }
    }

    func setPulseBPM(_ bpm: Float) {
        pulseBPM = bpm
        publish { $0.pulseBPM = bpm }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        publish { $0.isEnabled = enabled }

        if enabled {
            startEngine()
            // 켤 때부터 소리가 차오르도록 방금 입력이 있었던 것으로 친다.
            noteInput()
        } else {
            // 소리가 잦아든 뒤에 엔진을 멈춘다.
            DispatchQueue.main.asyncAfter(deadline: .now() + AmbientEngine.fadeOutSeconds) { [weak self] in
                guard let self, !self.isEnabled else { return }
                self.engine.pause()
                self.engine.stop()
                self.isRunning = false
            }
        }
    }

    /// 키나 클릭이 들어왔음을 알린다. 활동량이 올라 소리가 차오른다.
    func noteInput() {
        publish { $0.eventCount &+= 1 }
    }

    /// 클릭·타건 소리가 났음을 알린다. 앰비언트를 잠깐 눌러 준다.
    func noteSoundPlayed() {
        publish { $0.duckCount &+= 1 }
    }

    // MARK: - 루프 파일

    /// 루프 파일을 읽어 합성기에 올린다. 실패하면 이유를 남기고 false.
    @discardableResult
    func loadLoop(url: URL) -> Bool {
        guard let (left, right) = AmbientEngine.readLoop(url: url, format: format) else {
            lastLoopError = url.lastPathComponent
            return false
        }
        synth.setLoop(left: left, right: right)
        lastLoopError = nil
        return true
    }

    /// 파일을 엔진 포맷의 좌우 채널로 변환해 읽는다.
    private static func readLoop(url: URL, format: AVAudioFormat) -> ([Float], [Float])? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let source = file.processingFormat
        guard source.sampleRate > 0, source.channelCount > 0,
              let converter = AVAudioConverter(from: source, to: format)
        else { return nil }

        let seconds = min(Double(file.length) / source.sampleRate, maxLoopSeconds)
        let capacity = AVAudioFrameCount(seconds * format.sampleRate) + 4096

        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(file.length)),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
        else { return nil }

        do {
            try file.read(into: input)
        } catch {
            return nil
        }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if supplied {
                outStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return input
        }
        guard status != .error, output.frameLength > 0, let channels = output.floatChannelData else { return nil }

        let frames = Int(output.frameLength)
        let left = Array(UnsafeBufferPointer(start: channels[0], count: frames))
        let right = output.format.channelCount > 1
            ? Array(UnsafeBufferPointer(start: channels[1], count: frames))
            : left
        return (left, right)
    }

    // MARK: - 엔진

    private func startEngine() {
        guard !isRunning else { return }
        do {
            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    private func publish(_ mutate: (inout AmbientSynth.Params) -> Void) {
        box.publish(mutate)
    }

    /// 검증용. 소리를 내지 않고 오프라인으로 렌더해 보려고 엔진을 그대로 내준다.
    var audioGraph: AVAudioEngine { engine }

    /// 진단용.
    var debugDescription: String {
        let snapshot = box.current
        return "voice=\(voice.storedValue) enabled=\(isEnabled) running=\(isRunning)"
            + " maxLevel=\(maxLevel) grains=\(grainsEnabled) chimes=\(chimesEnabled) guitar=\(guitarEnabled) electronic=\(electronicEnabled) bpm=\(pulseBPM)"
            + " events=\(snapshot.eventCount) ducks=\(snapshot.duckCount) loop=\(synth.hasLoop)"
    }
}
