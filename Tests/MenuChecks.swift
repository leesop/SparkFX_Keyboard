// Appended to AppDelegate.swift by run.sh so tests can inspect private menu actions.
import AVFoundation

private enum CheckFailure: Error {
    case failed(String)
}

private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw CheckFailure.failed(message) }
}

extension AppDelegate {
    static func runMenuChecks() throws {
        let domain = "com.sparkfx.tests.\(UUID().uuidString)"
        Prefs.defaults = UserDefaults(suiteName: domain)!
        defer {
            Prefs.defaults.removePersistentDomain(forName: domain)
            Prefs.defaults = .standard
        }
        try check(Prefs.effectSize == .small, "Default visual size")
        try check(Prefs.visualEffect == .fireworks, "Existing fireworks remain the default")
        Prefs.defaults.set("off", forKey: "effectSize")
        try check(Prefs.visualEffect == .none && Prefs.effectSize == .small, "Legacy off maps to None with normal size")
        Prefs.effectSize = .medium
        try check(Prefs.visualEffect == .none && Prefs.effectSize == .medium, "Changing size does not reenable legacy off")
        Prefs.visualEffect = .ripple
        Prefs.effectSize = .small
        try check(Prefs.visualEffect == .ripple && Prefs.effectSize == .small, "Effect and size persist independently")
        Prefs.defaults.removePersistentDomain(forName: domain)
        try check(Prefs.soundMode == .off, "Default sound mode")
        try check(Prefs.ambientVoice == .pad, "Default ambient voice")
        try check(!Prefs.ambientGuitar && !Prefs.ambientElectronic, "New key effects default off")
        for voice in [AmbientVoice.metal, .edm] {
            Prefs.ambientVoice = voice
            try check(Prefs.ambientVoice == voice, "New loop voice round-trips")
        }
        Prefs.ambientVoice = .pad
        try check(Prefs.soundVolume == 0.5 && Prefs.ambientMaxLevel == 0.5, "Default volumes")
        Prefs.defaults.set("large", forKey: "effectSize")
        try check(Prefs.effectSize == .medium, "Legacy large maps to the largest menu size")
        Prefs.defaults.set(120, forKey: "ambient.bpm")
        try check(Prefs.ambientBPM == 90, "Legacy beat maps to 90")
        Prefs.defaults.set(0.7, forKey: "sound.volume")
        try check(Prefs.soundVolume == 0.75, "Legacy volume maps to a visible choice")
        Prefs.defaults.set(true, forKey: "ambient.enabled")
        try check(Prefs.soundMode == .ambient, "Legacy ambient migration")
        Prefs.soundMode = .off
        try check(Prefs.soundMode == .off, "Explicit None overrides old ambient state")
        Prefs.defaults.removePersistentDomain(forName: domain)

        let app = AppDelegate()
        let status = app.makeStatusItem()
        defer { NSStatusBar.system.removeStatusItem(status) }
        let root = status.menu!
        try check(root.numberOfItems == 9, "Top-level menu count")
        try check(!root.items[0].isEnabled && root.items[0].title.contains("1.5") && root.items[0].title.contains("(6)"), "App/version label")
        let expected = ["menu.permission", "menu.effect", "menu.audio", "menu.other"]
        for (index, key) in expected.enumerated() {
            try check(root.items[index + 2].title == L(key), "Top-level order: \(key)")
        }
        try check(root.items[1].isSeparatorItem && root.items[6].isSeparatorItem, "Top-level separators")
        try check(root.items[7].title == L("menu.about") && root.items[8].title == L("menu.quit"), "About/Quit order")
        for accessibility in [false, true] {
            for inputMonitoring in [false, true] {
                app.refreshPermissionItems(accessibility: accessibility, inputMonitoring: inputMonitoring)
                try check(app.permissionItem.isHidden == (accessibility && inputMonitoring),
                          "Permissions hidden only when both are granted")
                try check(app.accessibilityStatusItem.state == (accessibility ? .on : .off),
                          "Accessibility status check")
                try check(app.inputMonitoringStatusItem.state == (inputMonitoring ? .on : .off),
                          "Input monitoring status check")
            }
        }
        let visual = root.items[3].submenu!
        try check(visual.items.map(\.title) == [L("visual.type"), L("visual.size")], "Separate type and size menus")
        let kinds = visual.items[0].submenu!
        let sizes = visual.items[1].submenu!
        try check(kinds.items.map(\.title) == [L("visual.kind.none"), L("visual.kind.fireworks"), L("visual.kind.ripple")],
                  "None, Fireworks, Water Droplets choices")
        try check(sizes.items.map(\.title) == [L("effect.small"), L("effect.medium")], "Normal and large choices only")
        try check(kinds.items[1].state == .on && sizes.items[0].state == .on, "Fireworks and normal are selected")
        app.selectVisualEffect(kinds.items[2])
        app.selectEffectSize(sizes.items[1])
        app.refreshMenu()
        try check(Prefs.visualEffect == .ripple && Prefs.effectSize == .medium, "Ripple and large actions")
        try check(kinds.items[2].state == .on && sizes.items[1].state == .on, "Ripple and large checkmarks")
        app.selectVisualEffect(kinds.items[0])
        app.selectEffectSize(sizes.items[0])
        try check(Prefs.visualEffect == .none && Prefs.effectSize == .small, "Size while off stays off")
        app.selectVisualEffect(kinds.items[1])
        try check(Prefs.visualEffect == .fireworks, "Can return to existing fireworks")
        let audioItem = root.items[4]
        try check(audioItem.submenu == nil && audioItem.action != nil && audioItem.isEnabled,
                  "Top-level Sound Settings directly opens a window")
        // Prepare offline audio before exercising mode changes. Never play through speakers.
        let graph = app.ambient.audioGraph
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        try graph.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        let controller = SoundOptionsWindowController(rememberFrame: false)
        controller.onAction = { [weak app] action in app?.applySoundOption(action) }
        app.soundOptions = controller
        try check(NSApp.sendAction(audioItem.action!, to: audioItem.target, from: audioItem), "Direct sound settings action opens window")
        try check((controller.control("mode") as! NSPopUpButton).itemTitles == SoundMode.allCases.map { L($0.titleKey) },
                  "All sound types are chosen inside the window")
        defer { controller.close(); app.neural.stop(); app.neural.synchronize() }
        let originalWindow = controller.window
        try check(originalWindow?.isVisible == true, "Options opens as an independent nonmodal window")
        app.showSoundOptions()
        try check(controller.window === originalWindow && app.soundOptions === controller, "Repeated opens reuse one window")
        let volume = controller.control("volume") as! NSSegmentedControl
        try check(!volume.isEnabled && controller.control("ambient.voice") == nil, "Off state has no stale controls")

        try selectOption(controller, "mode", index: 1)
        try check(app.ambient.isEnabled && Prefs.soundMode == .ambient, "Window mode selector reaches engine")
        try check(controller.control("ambient.voice") != nil && volume.isEnabled && volume.selectedSegment == 1,
                  "Ambient controls and default volume")
        for (index, raw) in [(2, "metal"), (3, "edm")] {
            try selectOption(controller, "ambient.voice", index: index)
            try check(Prefs.ambientVoice.storedValue == raw && app.ambient.voice.storedValue == raw,
                      "Loop control updates stored choice and engine")
        }
        for effect in AmbientKeyEffect.allCases {
            try setOption(controller, "ambient.\(effect.rawValue)", enabled: true)
            try check(effect.enabled, "Ambient effect checkbox applies")
        }
        try check(app.ambient.grainsEnabled && app.ambient.chimesEnabled && app.ambient.guitarEnabled &&
                  app.ambient.electronicEnabled && app.ambient.pulseBPM == 90, "All key effects reach engine")
        try setOption(controller, "ambient.guitar", enabled: false)
        try check(!Prefs.ambientGuitar && Prefs.ambientElectronic, "Key effects stay independent")
        try setVolumeOption(controller, index: 2)
        try check(Prefs.ambientMaxLevel == 0.75 && app.ambient.maxLevel == 0.75, "Window volume reaches ambient output")
        app.restoreAmbient()
        try check(!app.ambient.guitarEnabled && app.ambient.electronicEnabled && app.ambient.voice == .edm,
                  "Ambient settings restore after reopening")
        try saveOptionsSnapshot(controller, mode: "ambient")

        Prefs.setSound(.keyboard, SoundSetting(path: "/tmp/remembered.wav", isEnabled: true))
        Prefs.noteUsedSound(.keyboard, path: "/tmp/remembered.wav")
        try check(app.preparedSound(for: .keyboard) == nil, "Ambient mode blocks custom sounds")
        app.setSoundMode(.custom) // Backend mode changes also refresh the window.
        try check(!app.ambient.isEnabled && Prefs.soundMode == .custom, "Custom mode disables ambient")
        try check((controller.control("mode") as! NSPopUpButton).indexOfSelectedItem == 2,
                  "Mode and window stay synchronized")
        let source = controller.control("keyboard.source") as! NSPopUpButton
        try check(source.selectedItem?.representedObject as? String == "/tmp/remembered.wav", "Remembered sound appears")
        try check(controller.control("mouse.choose") != nil && controller.control("ambient.voice") == nil,
                  "Only custom controls are visible")
        try setOption(controller, "keyboard.enabled", enabled: false)
        try check(Prefs.sound(.keyboard).activePath == nil && Prefs.sound(.keyboard).path != nil, "Disable preserves chosen path")
        try setVolumeOption(controller, index: 3)
        try check(Prefs.soundVolume == 1, "Custom volume action")
        try saveOptionsSnapshot(controller, mode: "custom")
        try app.checkNeuralWindow(controller)
        app.setSoundMode(.off); app.neural.synchronize()
        try check(!app.ambient.isEnabled && app.preparedSound(for: .keyboard) == nil, "None is silent")
        try check(!volume.isEnabled && controller.control("neural.instrument") == nil, "None clears model-specific controls")
        try check(Prefs.sound(.keyboard).path == "/tmp/remembered.wav", "Mode changes preserve files")
        controller.close()
        try check(!controller.window!.isVisible && Prefs.soundMode == .off, "Closing does not change the selected mode")
        app.showSoundOptions()
        try check(app.soundOptions?.window === originalWindow && controller.window!.isVisible, "Closed window reopens")
        let other = root.items[5].submenu!
        try check(other.items.map(\.title) == [L("menu.caret"), L("menu.login")], "Other settings order")
        // Login registration is deliberately not triggered by automated tests.
        print("PASS permissions, menu order, independent sound options window, all controls, mode synchronization, persistence and reopening")
    }
}

private func checkAudioMix() throws {
    let sampleRate: Double = 48000
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    // A generated loop exercises file playback without using any copyrighted asset.
    let loopURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sparkfx-loop-\(UUID().uuidString).caf")
    defer { try? FileManager.default.removeItem(at: loopURL) }
    let loopBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
    loopBuffer.frameLength = 48000
    for frame in 0..<48000 {
        let value = Float(sin(Double(frame) * 2 * .pi * 220 / sampleRate)) * 0.5
        loopBuffer.floatChannelData![0][frame] = value
        loopBuffer.floatChannelData![1][frame] = value
    }
    let file = try AVAudioFile(forWriting: loopURL, settings: format.settings)
    try file.write(from: loopBuffer)

    for voice in AmbientVoice.builtIn + [.loop(loopURL.path)] {
        var reference: [Float] = []
        for volume in [Float(1), 0.75, 0.5, 0.25] {
            let engine = AmbientEngine()
            let graph = engine.audioGraph
            try graph.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
            if case .loop = voice {
                try check(engine.loadLoop(url: loopURL), "Generated loop loads")
            }
            engine.setVoice(voice)
            engine.setGrainsEnabled(true)
            engine.setChimesEnabled(true)
            engine.setGuitarEnabled(true)
            engine.setElectronicEnabled(true)
            engine.setPulseBPM(90)
            engine.setMaxLevel(volume)
            engine.setEnabled(true)
            defer { engine.setEnabled(false); graph.stop() }
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
            var samples: [Float] = []
            var peak: Float = 0
            for block in 0..<120 {
                if block % 2 == 0 { engine.noteInput() }
                let state = try graph.renderOffline(4096, to: buffer)
                try check(state == .success, "Offline render succeeds")
                for channel in 0..<2 {
                    let values = UnsafeBufferPointer(start: buffer.floatChannelData![channel], count: Int(buffer.frameLength))
                    for value in values {
                        try check(value.isFinite, "Audio contains no NaN/Inf")
                        peak = max(peak, abs(value))
                    }
                    samples.append(contentsOf: values)
                }
            }
            try check(peak > 0 && peak < 1, "Mix is audible and does not clip")
            if volume == 1 { reference = samples }
            else {
                try check(samples.count == reference.count, "Same render duration")
                let error = zip(samples, reference).map { abs($0 - $1 * volume) }.max()!
                try check(error < 0.0001, "Whole mix scales with relative volume: \(error)")
            }
            print("PASS offline audio \(voice.storedValue.hasPrefix("loop:") ? "loop" : voice.storedValue) volume=\(volume) peak=\(peak)")
        }
    }
}

private func checkRipples() throws {
    try check(RippleEmitter.radius(size: .medium, trigger: .mouse) > RippleEmitter.radius(size: .small, trigger: .mouse),
              "Large ripple has larger radius")
    try check(RippleEmitter.radius(size: .small, trigger: .keyboard) < RippleEmitter.radius(size: .small, trigger: .mouse),
              "Keyboard ripples are smaller")
    let emitter = RippleEmitter()
    // Attach to a real, offscreen AppKit window to exercise Core Animation's
    // presentation tree without covering the user's desktop.
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 240, height: 200),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 200))
    view.wantsLayer = true
    emitter.layer.frame = view.bounds
    view.layer!.addSublayer(emitter.layer)
    window.contentView = view
    window.orderFrontRegardless()
    defer { window.orderOut(nil); window.close() }
    let point = CGPoint(x: 120, y: 100)
    emitter.burst(at: point, size: .small, trigger: .keyboard, displayScale: 2)
    let first = emitter.layer.sublayers!.first!
    emitter.burst(at: point, size: .medium, trigger: .mouse, displayScale: 2)
    try check(emitter.layer.sublayers!.count == 2 && first.superlayer === emitter.layer,
              "Overlapping input keeps prior ripples alive")
    let burst = emitter.layer.sublayers!.last!
    try check(burst.position == point, "Ripple centered at input position")
    let rings = burst.sublayers!.filter { $0.name?.hasPrefix("ripple-") == true }
    try check(rings.count == 3, "Three concentric rings")
    var previousStart: CFTimeInterval = 0
    for ring in rings {
        let shape = ring as! CAShapeLayer
        let spread = shape.animation(forKey: "spread") as! CAAnimationGroup
        try check(spread.beginTime > previousStart, "Rings start in order")
        previousStart = spread.beginTime
        let grow = spread.animations!.first as! CABasicAnimation
        let fade = spread.animations!.last as! CAKeyframeAnimation
        let from = grow.fromValue as! CGPath
        let to = grow.toValue as! CGPath
        try check(from.boundingBox.width < to.boundingBox.width, "Ring expands")
        try check(abs(to.boundingBox.midX - burst.bounds.midX) < 0.001 &&
                  abs(to.boundingBox.midY - burst.bounds.midY) < 0.001, "Rings share a center")
        try check((fade.values!.last as! NSNumber).floatValue == 0, "Ring fades completely")
        try check(shape.contentsScale == 2 && shape.opacity == 0, "Retina scale and invisible resting state")
    }
    CATransaction.flush()
    RunLoop.current.run(until: Date().addingTimeInterval(0.14))
    let liveRing = rings[0] as! CAShapeLayer
    guard let early = liveRing.presentation(), let earlyPath = early.path else {
        throw CheckFailure.failed("Live ripple presentation is available")
    }
    let earlyWidth = earlyPath.boundingBox.width
    try check(early.opacity > 0 && earlyWidth > 4, "Actual compositor shows a visible growing ring")
    RunLoop.current.run(until: Date().addingTimeInterval(0.12))
    try check((liveRing.presentation()?.path?.boundingBox.width ?? 0) > earlyWidth,
              "Actual compositor continues expanding the circle")
    for _ in 0..<50 { emitter.burst(at: point, size: .small, trigger: .mouse, displayScale: 2) }
    try check(emitter.layer.sublayers!.count == RippleEmitter.maximumBursts, "Burst count remains bounded")
    RunLoop.current.run(until: Date().addingTimeInterval(RippleEmitter.lifetime + 0.12))
    try check(emitter.layer.sublayers?.isEmpty ?? true, "Completed ripples remove their layers")
    emitter.burst(at: point, size: .small, trigger: .mouse, displayScale: 2)
    emitter.clear()
    try check(emitter.layer.sublayers?.isEmpty ?? true, "Changing effects can clear all ripples")
    print("PASS live Core Animation ripple, expansion, timing, centering, sizes, overlapping input, bounded layers and cleanup")
}

@main
struct MenuTestRunner {
    static func main() throws {
        setvbuf(stdout, nil, _IONBF, 0)
        if CommandLine.arguments.contains("--neural-only") {
            try checkNeuralModels()
            try checkNeuralPlayback()
            return
        }
        if !CommandLine.arguments.contains("--audio-only") {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            try AppDelegate.runMenuChecks()
            try checkRipples()
        }
        if !CommandLine.arguments.contains("--visual-only") {
            try checkNeuralModels()
            try checkNeuralPlayback()
            try checkModernAudio()
            try checkAudioMix()
        }
    }
}
