import AppKit
import UniformTypeIdentifiers
import ServiceManagement

/// 소리 메뉴 항목이 무슨 일을 할지 담는다.
private struct SoundCommand {
    let trigger: Trigger
    /// 고른 파일. null이면 파일과 무관한 동작(끄기, 고르기, 목록 삭제).
    let path: String?
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let overlay = SparkOverlay()
    private let keyboardSound = SoundPlayer()
    private let mouseSound = SoundPlayer()
    private let ambient = AmbientEngine()

    private var statusItem: NSStatusItem!
    private var keyMonitor: Any?
    private var clickMonitor: Any?

    private var effectCheckItems: [NSMenuItem] = []
    private var effectKindItems: [NSMenuItem] = []
    private var soundModeItems: [NSMenuItem] = []
    private var audioMenu: NSMenu!
    private var audioOptionsItem: NSMenuItem!
    private var audioOptionsMenu: NSMenu!
    private var caretItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var permissionItem: NSMenuItem!
    private var accessibilityStatusItem: NSMenuItem!
    private var inputMonitoringStatusItem: NSMenuItem!

    /// 백스페이스(delete) 키. 지운 자리를 보게 되므로 커서에 바짝 붙여 터뜨린다.
    private static let backspaceKeyCode: UInt16 = 51
    /// macOS 포인터 화살표의 대략적인 크기 (pt). 왼쪽 위가 기준점이라 절반만큼 오른쪽 아래로 비킨다.
    private static let mouseArrowSize = CGSize(width: 16, height: 24)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = makeStatusItem()
        startMonitoringInput()

        if CommandLine.arguments.contains("--demo") {
            startDemoTimer()
            return
        }

        restoreAmbient()

        if CommandLine.arguments.contains("--diag") {
            runDiagnostics()
        }

        requestPermissions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    }

    // MARK: - 메뉴

    private func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, value: Any? = nil,
                            checked: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = value
        item.state = checked ? .on : .off
        return item
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = StatusIcon.make()
        item.button?.toolTip = "SparkFX Keyboard"

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        let info = Bundle.main.infoDictionary ?? [:]
        let name = info["CFBundleDisplayName"] as? String ?? "SparkFX Keyboard"
        let version = info["CFBundleShortVersionString"] as? String ?? "1.2"
        let build = info["CFBundleVersion"] as? String ?? "5"
        menu.addItem(label("\(name) \(version) (\(build))"))
        menu.addItem(.separator())
        menu.addItem(makePermissionItem())
        menu.addItem(makeEffectItem())
        menu.addItem(makeAudioItem())
        menu.addItem(makeOtherItem())
        menu.addItem(.separator())
        menu.addItem(actionItem(L("menu.about"), #selector(showAbout)))
        let quitItem = actionItem(L("menu.quit"), #selector(quit))
        quitItem.keyEquivalent = "q"
        menu.addItem(quitItem)
        item.menu = menu
        refreshMenu()
        return item
    }

    private func makeEffectItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("menu.effect"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let kindItem = NSMenuItem(title: L("visual.type"), action: nil, keyEquivalent: "")
        let kinds = NSMenu()
        kinds.autoenablesItems = false
        for kind in VisualEffect.allCases {
            let entry = actionItem(kind.title, #selector(selectVisualEffect(_:)), value: kind.rawValue)
            kinds.addItem(entry)
            effectKindItems.append(entry)
        }
        kindItem.submenu = kinds
        submenu.addItem(kindItem)

        let sizeItem = NSMenuItem(title: L("visual.size"), action: nil, keyEquivalent: "")
        let sizes = NSMenu()
        sizes.autoenablesItems = false
        for size in [EffectSize.small, .medium] {
            let entry = actionItem(size.title, #selector(selectEffectSize(_:)), value: size.rawValue)
            sizes.addItem(entry)
            effectCheckItems.append(entry)
        }
        sizeItem.submenu = sizes
        submenu.addItem(sizeItem)
        item.submenu = submenu
        return item
    }

    private func makeAudioItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("menu.audio"), action: nil, keyEquivalent: "")
        audioMenu = NSMenu()
        audioMenu.autoenablesItems = false
        audioMenu.delegate = self
        let modeItem = NSMenuItem(title: L("sound.type"), action: nil, keyEquivalent: "")
        let modes = NSMenu()
        for mode in SoundMode.allCases {
            let entry = actionItem(L(mode.titleKey), #selector(selectSoundMode(_:)), value: mode.rawValue)
            modes.addItem(entry)
            soundModeItems.append(entry)
        }
        modeItem.submenu = modes
        audioMenu.addItem(modeItem)
        audioOptionsItem = NSMenuItem(title: L("sound.options"), action: nil, keyEquivalent: "")
        audioOptionsMenu = NSMenu()
        audioOptionsMenu.autoenablesItems = false
        audioOptionsItem.submenu = audioOptionsMenu
        audioMenu.addItem(audioOptionsItem)
        item.submenu = audioMenu
        return item
    }

    /// Rebuild the selected mode's options inside a separate submenu.
    private func rebuildAudioOptions() {
        audioOptionsMenu.removeAllItems()
        audioOptionsItem.isEnabled = Prefs.soundMode != .off
        switch Prefs.soundMode {
        case .off: break
        case .ambient: appendAmbientOptions(to: audioOptionsMenu)
        case .custom:
            for trigger in Trigger.allCases {
                if trigger == .mouse { audioOptionsMenu.addItem(.separator()) }
                audioOptionsMenu.addItem(label(L(trigger.titleKey)))
                appendSoundOptions(for: trigger, to: audioOptionsMenu)
            }
            audioOptionsMenu.addItem(.separator())
            audioOptionsMenu.addItem(label(L("menu.sound.volume")))
            appendVolumes(to: audioOptionsMenu, ambient: false)
        }
    }

    private func appendSoundOptions(for trigger: Trigger, to menu: NSMenu) {
        let setting = Prefs.sound(trigger)
        menu.addItem(actionItem(L("menu.sound.none"), #selector(selectSoundOff(_:)),
                                value: SoundCommand(trigger: trigger, path: nil),
                                checked: setting.activePath == nil))
        let recent = Prefs.recentSounds(trigger)
        if !recent.isEmpty {
            menu.addItem(.separator())
            for path in recent {
                let entry = actionItem(SoundSetting.displayName(forPath: path), #selector(selectRecentSound(_:)),
                                       value: SoundCommand(trigger: trigger, path: path),
                                       checked: setting.activePath == path)
                entry.toolTip = path
                menu.addItem(entry)
            }
        }
        menu.addItem(.separator())
        menu.addItem(actionItem(L("menu.sound.choose"), #selector(chooseSound(_:)),
                                value: SoundCommand(trigger: trigger, path: nil)))
        let clear = actionItem(L("menu.sound.clear"), #selector(clearSoundList(_:)),
                               value: SoundCommand(trigger: trigger, path: nil))
        clear.isEnabled = !recent.isEmpty
        menu.addItem(clear)
    }

    private func appendAmbientOptions(to menu: NSMenu) {
        let voice = Prefs.ambientVoice
        menu.addItem(label(L("ambient.loopSettings")))
        for builtIn in AmbientVoice.builtIn {
            menu.addItem(actionItem(L("ambient.\(builtIn.storedValue)"), #selector(selectAmbientVoice(_:)),
                                    value: builtIn.storedValue, checked: voice == builtIn))
        }
        let loop = actionItem(L("ambient.loop"), #selector(chooseAmbientLoop(_:)))
        if case .loop(let path) = voice {
            loop.state = .on
            loop.toolTip = path
        }
        menu.addItem(loop)
        menu.addItem(.separator())
        menu.addItem(label(L("ambient.keyEffects")))
        menu.addItem(actionItem(L("ambient.grains"), #selector(toggleAmbientGrains), checked: Prefs.ambientGrains))
        menu.addItem(actionItem(L("ambient.chimes"), #selector(toggleAmbientChimes), checked: Prefs.ambientChimes))
        menu.addItem(actionItem(L("ambient.guitar"), #selector(toggleAmbientGuitar), checked: Prefs.ambientGuitar))
        menu.addItem(actionItem(L("ambient.electronic"), #selector(toggleAmbientElectronic), checked: Prefs.ambientElectronic))
        menu.addItem(actionItem(L("ambient.beat"), #selector(toggleAmbientPulse), checked: Prefs.ambientBPM > 0))
        menu.addItem(.separator())
        menu.addItem(label(L("ambient.volume")))
        appendVolumes(to: menu, ambient: true)
    }

    private func appendVolumes(to menu: NSMenu, ambient: Bool) {
        let selected = ambient ? Prefs.ambientMaxLevel : Prefs.soundVolume
        for volume in Prefs.volumeOptions {
            menu.addItem(actionItem("\(Int(volume * 100))%",
                                    ambient ? #selector(selectAmbientLevel(_:)) : #selector(selectVolume(_:)),
                                    value: Double(volume), checked: abs(selected - volume) < 0.001))
        }
    }

    private func makeOtherItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("menu.other"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        caretItem = actionItem(L("menu.caret"), #selector(toggleAccurateCaret))
        submenu.addItem(caretItem)
        loginItem = actionItem(L("menu.login"), #selector(toggleLogin))
        submenu.addItem(loginItem)
        item.submenu = submenu
        return item
    }

    @objc private func toggleAccurateCaret() {
        let enabled = !Prefs.accurateCaret
        Prefs.accurateCaret = enabled
        if !enabled { CaretLocator.releaseAccessibilityTrees() }
    }

    @objc private func toggleLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L("login.error")
            alert.informativeText = error.localizedDescription
            activateApp()
            alert.runModal()
        }
        refreshLoginItem()
    }

    private func refreshLoginItem() {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            loginItem.state = status == .enabled ? .on : status == .requiresApproval ? .mixed : .off
            loginItem.toolTip = status == .requiresApproval ? L("login.approval") : nil
        } else {
            loginItem.isEnabled = false
            loginItem.toolTip = L("login.unsupported")
        }
    }

    private func makePermissionItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("menu.permission"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        accessibilityStatusItem = label(L("permission.accessibility"))
        inputMonitoringStatusItem = label(L("permission.inputMonitoring"))
        submenu.addItem(accessibilityStatusItem)
        submenu.addItem(inputMonitoringStatusItem)
        submenu.addItem(.separator())
        submenu.addItem(actionItem(L("permission.openSettings"), #selector(openPermissionSettings)))
        submenu.addItem(actionItem(L("permission.recheck"), #selector(recheckPermissions)))
        submenu.addItem(actionItem(L("permission.reveal"), #selector(revealApp)))
        item.submenu = submenu
        permissionItem = item
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenu()
    }

    private func refreshMenu() {
        for item in effectKindItems {
            item.state = item.representedObject as? String == Prefs.visualEffect.rawValue ? .on : .off
        }
        for item in effectCheckItems {
            item.state = item.representedObject as? String == Prefs.effectSize.rawValue ? .on : .off
        }
        for item in soundModeItems {
            item.state = item.representedObject as? String == Prefs.soundMode.rawValue ? .on : .off
        }
        rebuildAudioOptions()
        caretItem.state = Prefs.accurateCaret ? .on : .off
        refreshLoginItem()
        refreshPermissionItems(accessibility: CaretLocator.isTrusted,
                               inputMonitoring: CaretLocator.hasInputMonitoring)
    }

    private func refreshPermissionItems(accessibility: Bool, inputMonitoring: Bool) {
        permissionItem.isHidden = accessibility && inputMonitoring
        accessibilityStatusItem.state = accessibility ? .on : .off
        inputMonitoringStatusItem.state = inputMonitoring ? .on : .off
    }

    @objc private func selectSoundMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = SoundMode(rawValue: raw) else { return }
        Prefs.soundMode = mode
        // Load the loop only when its mode is used, and stop ambient output in other modes.
        if mode == .ambient { restoreAmbient() }
        else { ambient.setEnabled(false) }
    }

    @objc private func selectAmbientVoice(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        guard let voice = AmbientVoice.builtIn.first(where: { $0.storedValue == raw }) else { return }
        applyAmbientVoice(voice)
    }

    @objc private func chooseAmbientLoop(_ sender: NSMenuItem) {
        activateApp()
        let panel = NSOpenPanel()
        panel.message = L("ambient.loop")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard ambient.loadLoop(url: url) else {
            let alert = NSAlert()
            alert.messageText = L("alert.loop.title")
            alert.informativeText = L("alert.loop.body", url.lastPathComponent)
            alert.alertStyle = .warning
            alert.addButton(withTitle: L("alert.sound.ok"))
            activateApp()
            alert.runModal()
            return
        }
        applyAmbientVoice(.loop(url.path))
    }

    private func applyAmbientVoice(_ voice: AmbientVoice) {
        ambient.setVoice(voice)
        Prefs.ambientVoice = voice
    }

    @objc private func toggleAmbientGrains() {
        Prefs.ambientGrains.toggle()
        ambient.setGrainsEnabled(Prefs.ambientGrains)
    }

    @objc private func toggleAmbientChimes() {
        Prefs.ambientChimes.toggle()
        ambient.setChimesEnabled(Prefs.ambientChimes)
    }

    @objc private func toggleAmbientGuitar() {
        Prefs.ambientGuitar.toggle()
        ambient.setGuitarEnabled(Prefs.ambientGuitar)
    }

    @objc private func toggleAmbientElectronic() {
        Prefs.ambientElectronic.toggle()
        ambient.setElectronicEnabled(Prefs.ambientElectronic)
    }

    @objc private func toggleAmbientPulse() {
        Prefs.ambientBPM = Prefs.ambientBPM > 0 ? 0 : 90
        ambient.setPulseBPM(Prefs.ambientBPM)
    }

    @objc private func selectAmbientLevel(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        Prefs.ambientMaxLevel = Float(value)
        ambient.setMaxLevel(Float(value))
    }

    // MARK: - 메뉴 동작

    @objc private func selectVisualEffect(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let effect = VisualEffect(rawValue: raw) else { return }
        Prefs.visualEffect = effect
        overlay.apply(size: Prefs.effectSize)
    }

    @objc private func selectEffectSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let size = EffectSize(rawValue: raw) else { return }
        Prefs.effectSize = size
        overlay.apply(size: size)
    }

    @objc private func selectSoundOff(_ sender: NSMenuItem) {
        guard let command = soundCommand(from: sender) else { return }
        var setting = Prefs.sound(command.trigger)
        setting.isEnabled = false
        Prefs.setSound(command.trigger, setting)
    }

    /// 목록에서 고른 소리를 바로 쓴다. 고른 것이 맨 앞으로 올라온다.
    @objc private func selectRecentSound(_ sender: NSMenuItem) {
        guard let command = soundCommand(from: sender), let path = command.path else { return }
        applySound(trigger: command.trigger, path: path)
    }

    @objc private func chooseSound(_ sender: NSMenuItem) {
        guard let command = soundCommand(from: sender) else { return }
        activateApp()

        let panel = NSOpenPanel()
        panel.message = L("menu.sound.choose")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio, .yaml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        applySound(trigger: command.trigger, path: url.path)
    }

    /// 잘못 고른 소리를 지울 수 있도록 목록을 비운다. 고른 소리도 함께 지운다.
    @objc private func clearSoundList(_ sender: NSMenuItem) {
        guard let command = soundCommand(from: sender) else { return }
        Prefs.clearRecentSounds(command.trigger)
        var setting = Prefs.sound(command.trigger)
        setting.isEnabled = false
        Prefs.setSound(command.trigger, setting)
    }

    @objc private func selectVolume(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        Prefs.soundVolume = Float(value)
    }

    @objc private func openPermissionSettings() {
        openSettingsPane()
    }

    @objc private func recheckPermissions() {
        let accessibility = CaretLocator.isTrusted
        let inputMonitoring = CaretLocator.hasInputMonitoring

        guard accessibility, inputMonitoring else {
            showPermissionAlert(needsAccessibility: !accessibility, needsInputMonitoring: !inputMonitoring)
            return
        }

        // 입력 모니터링은 앱을 다시 실행해야 효력이 생긴다.
        let alert = NSAlert()
        alert.messageText = L("alert.granted.title")
        alert.informativeText = L("alert.granted.body")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("alert.granted.relaunch"))
        alert.addButton(withTitle: L("alert.granted.later"))
        activateApp()

        if alert.runModal() == .alertFirstButtonReturn {
            relaunch()
        }
    }

    /// 시스템 설정 목록에 앱이 없을 때 + 단추로 고르기 쉽도록 Finder에서 보여준다.
    @objc private func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    @objc private func showAbout() {
        activateApp()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let credits = NSAttributedString(
            string: "\(L("copyright"))\n\n\(L("about.credits"))",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "SparkFX Keyboard",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2",
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "5",
            .credits: credits,
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - 입력 감시

    private func startMonitoringInput() {
        // 키 입력은 캐럿 위치에서 터뜨린다. 전역 키 감시에는 두 가지 권한이 모두 필요하다.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard !event.isARepeat else { return }
            self?.handleKeyPress(keyCode: event.keyCode)
        }

        // 마우스는 버튼을 누를 때만, 그 위치에서 터뜨린다. 마우스 감시는 권한이 필요 없다.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.handleMouseDown(type: event.type)
        }
    }

    private func handleMouseDown(type: NSEvent.EventType) {
        ambient.noteInput()
        if let player = preparedSound(for: .mouse), let button = KeyNames.buttonName(for: type) {
            player.play(button: button)
            ambient.noteSoundPlayed()
        }
        overlay.fire(at: Self.mouseArrowOffset(NSEvent.mouseLocation), trigger: .mouse)
    }

    private func handleKeyPress(keyCode: UInt16) {
        ambient.noteInput()
        // 소리는 커서 조회를 기다리지 않고 바로 낸다.
        if let player = preparedSound(for: .keyboard) {
            player.play(keyCode: keyCode)
            ambient.noteSoundPlayed()
        }
        guard Prefs.visualEffect != .none else { return }

        // 캐럿 조회는 다른 앱에 대한 IPC라 메인 스레드를 붙잡지 않도록 뒤로 미룬다.
        let fallback = Self.mouseArrowOffset(NSEvent.mouseLocation)
        let placement: CaretLocator.Placement = keyCode == Self.backspaceKeyCode ? .deleting : .typing
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let point = CaretLocator.caretPoint(placement: placement)
            DispatchQueue.main.async {
                self?.overlay.fire(at: point ?? fallback, trigger: .keyboard)
            }
        }
    }

    // MARK: - 앰비언트

    /// 저장해 둔 앰비언트 설정을 되살린다. 루프 파일이 사라졌으면 따뜻한 패드로 돌아간다.
    private func restoreAmbient() {
        guard Prefs.soundMode == .ambient else {
            ambient.setEnabled(false)
            return
        }
        var voice = Prefs.ambientVoice
        if case .loop(let path) = voice, !ambient.loadLoop(url: URL(fileURLWithPath: path)) {
            voice = .pad
            Prefs.ambientVoice = voice
        }
        ambient.setVoice(voice)
        ambient.setMaxLevel(Prefs.ambientMaxLevel)
        ambient.setGrainsEnabled(Prefs.ambientGrains)
        ambient.setChimesEnabled(Prefs.ambientChimes)
        ambient.setGuitarEnabled(Prefs.ambientGuitar)
        ambient.setElectronicEnabled(Prefs.ambientElectronic)
        ambient.setPulseBPM(Prefs.ambientBPM)
        ambient.setEnabled(Prefs.soundMode == .ambient)
    }

    // MARK: - 소리

    private func soundPlayer(for trigger: Trigger) -> SoundPlayer {
        trigger == .keyboard ? keyboardSound : mouseSound
    }

    /// 고른 소리를 올려서 돌려준다. 꺼져 있거나 읽지 못하면 nil.
    private func preparedSound(for trigger: Trigger) -> SoundPlayer? {
        guard Prefs.soundMode == .custom,
              let path = Prefs.sound(trigger).activePath else { return nil }
        let player = soundPlayer(for: trigger)
        guard player.load(path: path) else { return nil }
        return player
    }

    private func applySound(trigger: Trigger, path: String) {
        guard soundPlayer(for: trigger).load(path: path) else {
            // 못 읽는 파일은 목록에서 지워 다시 고르게 한다.
            Prefs.removeRecentSound(trigger, path: path)

            let alert = NSAlert()
            alert.messageText = L("alert.sound.title")
            alert.informativeText = L("alert.sound.body", URL(fileURLWithPath: path).lastPathComponent)
            alert.alertStyle = .warning
            alert.addButton(withTitle: L("alert.sound.ok"))
            activateApp()
            alert.runModal()
            return
        }
        Prefs.setSound(trigger, SoundSetting(path: path, isEnabled: true))
        Prefs.noteUsedSound(trigger, path: path)
        // 고른 소리를 바로 들려준다.
        soundPlayer(for: trigger).preview()
    }

    private func soundCommand(from item: NSMenuItem) -> SoundCommand? {
        item.representedObject as? SoundCommand
    }

    // MARK: - 권한

    /// 키 입력을 받으려면 두 가지 권한이 모두 필요하다.
    /// 손쉬운 접근은 캐럿 위치 조회에, 입력 모니터링은 키 이벤트 관찰에 쓰인다.
    private func requestPermissions() {
        let accessibility = CaretLocator.requestPermission()
        let inputMonitoring = CaretLocator.requestInputMonitoring()

        guard !accessibility || !inputMonitoring, !Prefs.hasShownPermissionNotice else { return }
        Prefs.hasShownPermissionNotice = true
        // 시스템 권한 창을 가리지 않도록 잠시 뒤에 띄운다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.showPermissionAlert(needsAccessibility: !accessibility, needsInputMonitoring: !inputMonitoring)
        }
    }

    private func showPermissionAlert(needsAccessibility: Bool, needsInputMonitoring: Bool) {
        var missing: [String] = []
        if needsAccessibility { missing.append(L("permission.accessibility.short")) }
        if needsInputMonitoring { missing.append(L("permission.inputMonitoring.short")) }

        let alert = NSAlert()
        alert.messageText = L("alert.permission.title", missing.joined(separator: ", "))
        alert.informativeText = L("alert.permission.body")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("alert.permission.openSettings"))
        alert.addButton(withTitle: L("alert.permission.later"))
        activateApp()

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        openSettingsPane(preferAccessibility: needsAccessibility)
    }

    /// 한 번에 한 화면만 열 수 있다. 빠진 쪽을 먼저 연다.
    private func openSettingsPane(preferAccessibility: Bool = false) {
        let pane: String
        if preferAccessibility && !CaretLocator.isTrusted {
            pane = "Privacy_Accessibility"
        } else if !CaretLocator.hasInputMonitoring {
            pane = "Privacy_ListenEvent"
        } else {
            pane = "Privacy_Accessibility"
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    private func relaunch() {
        guard Bundle.main.bundleIdentifier != nil else {
            NSApp.terminate(nil)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: - 도우미

    private static func mouseArrowOffset(_ location: CGPoint) -> CGPoint {
        CGPoint(
            x: location.x + mouseArrowSize.width / 2,
            y: location.y - mouseArrowSize.height / 2
        )
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - 진단 (--demo / --diag)

    /// `--demo`: 접근성 권한 없이 확인할 수 있도록 마우스 위치에서 주기적으로 터뜨린다.
    private func startDemoTimer() {
        Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            self?.overlay.fire(at: Self.mouseArrowOffset(NSEvent.mouseLocation), trigger: .mouse)
        }
    }

    private func runDiagnostics() {
        CaretLocator.trace = { print("DIAG caret: \($0)") }

        print("DIAG accessibility=\(CaretLocator.isTrusted)"
            + " inputMonitoring=\(CaretLocator.hasInputMonitoring) (\(CaretLocator.inputMonitoringDescription))")
        print("DIAG language=\(Locale.preferredLanguages.first ?? "?")")
        print("DIAG localized: effect=\(L("menu.effect")) choose=\(L("menu.sound.choose"))"
            + " quit=\(L("menu.quit")) copyright=\(L("copyright"))")
        for size in EffectSize.allCases {
            print("DIAG   \(size.rawValue) -> \(size.title)")
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            print("DIAG alive accessibility=\(CaretLocator.isTrusted) inputMonitoring=\(CaretLocator.hasInputMonitoring)")
        }
    }
}
