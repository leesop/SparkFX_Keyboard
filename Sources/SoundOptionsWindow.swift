import AppKit

enum AmbientKeyEffect: String, CaseIterable {
    case grains, chimes, guitar, electronic, beat
    var enabled: Bool {
        switch self {
        case .grains: return Prefs.ambientGrains
        case .chimes: return Prefs.ambientChimes
        case .guitar: return Prefs.ambientGuitar
        case .electronic: return Prefs.ambientElectronic
        case .beat: return Prefs.ambientBPM > 0
        }
    }
}

/// Typed UI actions keep controls independent of menu item representations.
enum SoundOptionsAction {
    case mode(SoundMode), volume(Float), ambientVoice(AmbientVoice), chooseLoop
    case ambientEffect(AmbientKeyEffect, Bool)
    case soundEnabled(Trigger, Bool), soundPath(Trigger, String), chooseSound(Trigger), clearSounds(Trigger)
    case neural(NeuralSettings), retryNeural
}

private final class SoundControlTarget: NSObject {
    let action: (NSControl) -> Void
    init(_ action: @escaping (NSControl) -> Void) { self.action = action }
    @objc func invoke(_ sender: NSControl) { action(sender) }
}

private final class SoundDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// One persistent, nonmodal window. Updating values never replaces the focused control.
final class SoundOptionsWindowController: NSWindowController {
    var onAction: ((SoundOptionsAction) -> Void)?
    private var displayedMode: SoundMode?
    private var controls: [String: NSControl] = [:]
    private var persistentTargets: [SoundControlTarget] = []
    private var targets: [SoundControlTarget] = []
    private var refreshers: [() -> Void] = []
    private let body = NSStackView()
    private let modePicker = NSPopUpButton()
    private let volumePicker = NSSegmentedControl(labels: ["25%", "50%", "75%", "100%"], trackingMode: .selectOne, target: nil, action: nil)
    private let scroll = NSScrollView()
    private var statusLabel: NSTextField?
    private var retryButton: NSButton?
    private var neuralStatus: NeuralMusicEngine.Status = .off

    init(rememberFrame: Bool = true) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "SparkFX Keyboard — \(L("options.title"))"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 560, height: 420)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        if rememberFrame { window.setFrameAutosaveName("SparkFX.SoundOptions") }
        super.init(window: window)
        buildWindow()
        refresh(neuralStatus: .off)
        if !rememberFrame || !window.setFrameUsingName("SparkFX.SoundOptions") { window.center() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func bind(_ control: NSControl, id: String, persistent: Bool = false,
                      action: @escaping (NSControl) -> Void) {
        control.identifier = NSUserInterfaceItemIdentifier(id)
        controls[id] = control
        let target = SoundControlTarget(action)
        control.target = target; control.action = #selector(SoundControlTarget.invoke(_:))
        if persistent { persistentTargets.append(target) } else { targets.append(target) }
    }

    private func text(_ value: String, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: secondary ? 12 : 13)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func row(_ title: String, _ control: NSView) -> NSStackView {
        let label = text(title)
        label.setAccessibilityLabel(title)
        label.widthAnchor.constraint(equalToConstant: 108).isActive = true
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 12
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if let control = control as? NSControl { control.setAccessibilityLabel(title) }
        return row
    }

    private func buildWindow() {
        guard let root = window?.contentView else { return }
        let heading = text(L("options.title")); heading.font = .systemFont(ofSize: 22, weight: .semibold)
        let subtitle = text(L("options.autosave"), secondary: true)
        modePicker.addItems(withTitles: SoundMode.allCases.map { L($0.titleKey) })
        bind(modePicker, id: "mode", persistent: true) { [weak self] control in
            let index = (control as! NSPopUpButton).indexOfSelectedItem
            guard SoundMode.allCases.indices.contains(index) else { return }
            self?.onAction?(.mode(SoundMode.allCases[index]))
        }
        bind(volumePicker, id: "volume", persistent: true) { [weak self] control in
            let index = (control as! NSSegmentedControl).selectedSegment
            guard Prefs.volumeOptions.indices.contains(index) else { return }
            self?.onAction?(.volume(Prefs.volumeOptions[index]))
        }
        let modeRow = row(L("sound.type"), modePicker)
        let volumeRow = row(L("menu.sound.volume"), volumePicker)
        let separator = NSBox(); separator.boxType = .separator
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        let document = SoundDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        body.orientation = .vertical; body.alignment = .leading; body.spacing = 20
        body.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(body)
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            body.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12),
            body.topAnchor.constraint(equalTo: document.topAnchor),
            body.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -16),
        ])
        let close = NSButton(title: L("options.close"), target: self, action: #selector(closeOptions))
        close.bezelStyle = .rounded; close.keyEquivalent = "\u{1b}"
        for view in [heading, subtitle, modeRow, volumeRow, separator, scroll, close] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),
            subtitle.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            subtitle.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6),
            modeRow.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            modeRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            modeRow.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 18),
            volumeRow.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            volumeRow.trailingAnchor.constraint(equalTo: modeRow.trailingAnchor),
            volumeRow.topAnchor.constraint(equalTo: modeRow.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: modeRow.trailingAnchor),
            separator.topAnchor.constraint(equalTo: volumeRow.bottomAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: modeRow.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 20),
            scroll.bottomAnchor.constraint(equalTo: close.topAnchor, constant: -12),
            close.trailingAnchor.constraint(equalTo: modeRow.trailingAnchor),
            close.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
        ])
    }

    @objc private func closeOptions() { close() }

    func refresh(neuralStatus: NeuralMusicEngine.Status) {
        self.neuralStatus = neuralStatus
        let mode = Prefs.soundMode
        modePicker.selectItem(at: SoundMode.allCases.firstIndex(of: mode)!)
        let volume: Float
        switch mode {
        case .off: volume = 0.5
        case .ambient: volume = Prefs.ambientMaxLevel
        case .custom: volume = Prefs.soundVolume
        case .pianoGenie, .musicRNN, .drumsRNN: volume = Prefs.neuralSettings(mode).volume
        }
        volumePicker.isEnabled = mode != .off
        volumePicker.selectedSegment = Prefs.volumeOptions.firstIndex(of: volume) ?? 1
        if displayedMode != mode {
            displayedMode = mode
            for view in body.arrangedSubviews { body.removeArrangedSubview(view); view.removeFromSuperview() }
            controls = controls.filter { ["mode", "volume"].contains($0.key) }
            targets.removeAll(); refreshers.removeAll(); statusLabel = nil; retryButton = nil
            switch mode {
            case .off: addBody(text(L("options.off"), secondary: true))
            case .ambient: buildAmbient()
            case .custom: buildCustom()
            case .pianoGenie, .musicRNN: buildNeural(mode)
            case .drumsRNN: buildDrums()
            }
            scroll.contentView.scroll(to: .zero)
        }
        refreshers.forEach { $0() }
        updateStatus()
    }

    private func addBody(_ view: NSView) {
        body.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
    }
    private func section(_ title: String, views: [NSView]) {
        let heading = text(title); heading.font = .systemFont(ofSize: 13, weight: .semibold)
        let stack = NSStackView(views: [heading] + views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        addBody(stack)
    }

    private func popup<T: Equatable>(_ id: String, values: [T], titles: [String],
                                    selected: @escaping () -> T, action: @escaping (T) -> Void) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: titles)
        bind(popup, id: id) { control in
            let index = (control as! NSPopUpButton).indexOfSelectedItem
            guard values.indices.contains(index) else { return }
            action(values[index])
        }
        refreshers.append { [weak popup] in
            if let index = values.firstIndex(of: selected()) { popup?.selectItem(at: index) }
        }
        return popup
    }

    private func checkbox(_ id: String, title: String, value: @escaping () -> Bool,
                          action: @escaping (Bool) -> Void) -> NSButton {
        let check = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        bind(check, id: id) { action((($0 as! NSButton).state == .on)) }
        refreshers.append { [weak check] in check?.state = value() ? .on : .off }
        return check
    }

    private func buildAmbient() {
        let voices = AmbientVoice.builtIn.map(\.storedValue) + ["file"]
        let picker = popup("ambient.voice", values: voices,
            titles: AmbientVoice.builtIn.map { L("ambient.\($0.storedValue)") } + [L("ambient.loop")],
            selected: { if case .loop = Prefs.ambientVoice { return "file" }; return Prefs.ambientVoice.storedValue }) { [weak self] value in
                if value == "file" { self?.onAction?(.chooseLoop) }
                else if let voice = AmbientVoice.builtIn.first(where: { $0.storedValue == value }) {
                    self?.onAction?(.ambientVoice(voice))
                }
            }
        let path = text("", secondary: true)
        path.isSelectable = true
        path.lineBreakMode = .byTruncatingMiddle; path.maximumNumberOfLines = 1
        refreshers.append { [weak path] in
            if case .loop(let value) = Prefs.ambientVoice {
                path?.stringValue = value; path?.toolTip = value; path?.isHidden = false
            } else { path?.isHidden = true }
        }
        section(L("ambient.loopSettings"), views: [row(L("options.loop"), picker), path])
        let effects = AmbientKeyEffect.allCases.map { effect in
            checkbox("ambient.\(effect.rawValue)", title: L("ambient.\(effect.rawValue)"),
                value: { effect.enabled }) { [weak self] enabled in self?.onAction?(.ambientEffect(effect, enabled)) }
        }
        section(L("ambient.keyEffects"), views: effects)
    }

    private func buildCustom() {
        for trigger in Trigger.allCases {
            let prefix = trigger == .keyboard ? "keyboard" : "mouse"
            let enabled = checkbox("\(prefix).enabled", title: L("options.soundEnabled"),
                value: { Prefs.sound(trigger).isEnabled }) { [weak self] value in self?.onAction?(.soundEnabled(trigger, value)) }
            let source = NSPopUpButton()
            bind(source, id: "\(prefix).source") { [weak self] control in
                guard let path = (control as! NSPopUpButton).selectedItem?.representedObject as? String else { return }
                self?.onAction?(.soundPath(trigger, path))
            }
            let path = text("", secondary: true)
            path.isSelectable = true; path.maximumNumberOfLines = 1; path.lineBreakMode = .byTruncatingMiddle
            let choose = NSButton(title: L("menu.sound.choose"), target: nil, action: nil)
            choose.bezelStyle = .rounded
            bind(choose, id: "\(prefix).choose") { [weak self] _ in self?.onAction?(.chooseSound(trigger)) }
            let clear = NSButton(title: L("menu.sound.clear"), target: nil, action: nil)
            clear.bezelStyle = .rounded
            bind(clear, id: "\(prefix).clear") { [weak self] _ in self?.onAction?(.clearSounds(trigger)) }
            let buttons = NSStackView(views: [choose, clear]); buttons.spacing = 8
            refreshers.append { [weak source, weak path, weak clear] in
                let setting = Prefs.sound(trigger)
                var paths = Prefs.recentSounds(trigger)
                if let current = setting.path, !paths.contains(current) { paths.insert(current, at: 0) }
                source?.removeAllItems()
                if paths.isEmpty { source?.addItem(withTitle: L("menu.sound.none")) }
                for value in paths {
                    source?.addItem(withTitle: SoundSetting.displayName(forPath: value))
                    source?.lastItem?.representedObject = value; source?.lastItem?.toolTip = value
                }
                if let selected = setting.path, let index = paths.firstIndex(of: selected) { source?.selectItem(at: index) }
                source?.isEnabled = !paths.isEmpty
                path?.stringValue = setting.path ?? L("options.noFile"); path?.toolTip = setting.path
                clear?.isEnabled = !Prefs.recentSounds(trigger).isEmpty
            }
            section(L(trigger.titleKey), views: [enabled, row(L("options.file"), source), path, buttons])
        }
    }

    private func updateNeural(_ change: (inout NeuralSettings) -> Void) {
        guard Prefs.soundMode.isNeural else { return }
        var settings = Prefs.neuralSettings(Prefs.soundMode)
        change(&settings); onAction?(.neural(settings))
    }

    private func buildNeural(_ mode: SoundMode) {
        addBody(text(L(mode == .pianoGenie ? "options.pianoDescription" : "options.rnnDescription"), secondary: true))
        let instrument = popup("neural.instrument", values: NeuralInstrument.allCases,
            titles: NeuralInstrument.allCases.map { L("neural.instrument.\($0.key)") },
            selected: { Prefs.neuralSettings(mode).instrument }) { [weak self] value in self?.updateNeural { $0.instrument = value } }
        var rows: [NSView] = [row(L("neural.instrument"), instrument)]
        if mode == .pianoGenie {
            let register = popup("neural.register", values: NeuralRegister.allCases,
                titles: NeuralRegister.allCases.map { L("neural.register.\($0.rawValue)") },
                selected: { Prefs.neuralSettings(mode).register }) { [weak self] value in self?.updateNeural { $0.register = value } }
            rows.append(row(L("neural.register"), register))
        } else {
            let arrangement = popup("neural.arrangement", values: NeuralArrangement.allCases,
                titles: NeuralArrangement.allCases.map { L("neural.arrangement.\($0.rawValue)") },
                selected: { Prefs.neuralSettings(mode).arrangement }) { [weak self] value in self?.updateNeural { $0.arrangement = value } }
            let tempo = popup("neural.tempo", values: NeuralSettings.tempos,
                titles: NeuralSettings.tempos.map { "\($0) BPM" },
                selected: { Prefs.neuralSettings(mode).tempo }) { [weak self] value in self?.updateNeural { $0.tempo = value } }
            rows += [row(L("neural.arrangement"), arrangement), row(L("neural.tempo"), tempo)]
        }
        let variation = popup("neural.variation", values: NeuralVariation.allCases,
            titles: NeuralVariation.allCases.map { L("neural.variation.\($0.rawValue)") },
            selected: { Prefs.neuralSettings(mode).variation }) { [weak self] value in self?.updateNeural { $0.variation = value } }
        rows.append(row(L("neural.variation"), variation))
        if mode == .pianoGenie {
            rows.append(checkbox("neural.continuation", title: L("neural.continuation"),
                value: { Prefs.neuralSettings(mode).continuation }) { [weak self] value in self?.updateNeural { $0.continuation = value } })
        } else {
            rows.append(checkbox("neural.accompaniment", title: L("neural.accompaniment"),
                value: { Prefs.neuralSettings(mode).accompaniment }) { [weak self] value in self?.updateNeural { $0.accompaniment = value } })
        }
        section(L("options.performance"), views: rows)
        buildModelStatus()
    }

    private func buildDrums() {
        let mode = SoundMode.drumsRNN
        addBody(text(L("options.drumsDescription"), secondary: true))
        let style = popup("drums.style", values: DrumStyle.allCases,
            titles: DrumStyle.allCases.map { L("drums.style.\($0.rawValue)") },
            selected: { Prefs.neuralSettings(mode).drumStyle }) { [weak self] value in self?.updateNeural { $0.drumStyle = value } }
        let tempo = popup("drums.tempo", values: NeuralSettings.tempos,
            titles: NeuralSettings.tempos.map { "\($0) BPM" },
            selected: { Prefs.neuralSettings(mode).tempo }) { [weak self] value in self?.updateNeural { $0.tempo = value } }
        let follow = checkbox("drums.followTempo", title: L("drums.followTempo"),
            value: { Prefs.neuralSettings(mode).followInputTempo }) { [weak self] value in self?.updateNeural { $0.followInputTempo = value } }
        let density = popup("drums.density", values: DrumDensity.allCases,
            titles: DrumDensity.allCases.map { L("drums.density.\($0.rawValue)") },
            selected: { Prefs.neuralSettings(mode).drumDensity }) { [weak self] value in self?.updateNeural { $0.drumDensity = value } }
        let variation = popup("neural.variation", values: NeuralVariation.allCases,
            titles: NeuralVariation.allCases.map { L("neural.variation.\($0.rawValue)") },
            selected: { Prefs.neuralSettings(mode).variation }) { [weak self] value in self?.updateNeural { $0.variation = value } }
        section(L("drums.rhythm"), views: [row(L("drums.style"), style), row(L("drums.baseTempo"), tempo), follow,
            row(L("drums.density"), density), row(L("neural.variation"), variation)])
        buildModelStatus()
    }

    private func buildModelStatus() {
        let status = text("", secondary: true); statusLabel = status
        let retry = NSButton(title: L("neural.retry"), target: nil, action: nil); retry.bezelStyle = .rounded
        bind(retry, id: "neural.retry") { [weak self] _ in self?.onAction?(.retryNeural) }
        retryButton = retry
        let stack = NSStackView(views: [status, retry]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        addBody(stack)
    }

    private func updateStatus() {
        retryButton?.isHidden = true
        switch neuralStatus {
        case .loading: statusLabel?.stringValue = L("neural.loading")
        case .failed(let message):
            statusLabel?.stringValue = "\(L("neural.failed"))\n\(message)"
            retryButton?.isHidden = false
        default: statusLabel?.stringValue = L("options.ready")
        }
    }

    // Stable identifiers are also used by window/control integration checks.
    func control(_ identifier: String) -> NSControl? { controls[identifier] }
}
