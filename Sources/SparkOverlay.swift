import AppKit
import QuartzCore

private final class OverlayWindow: NSWindow {
    /// 기본 제약은 전체 화면 크기 창을 메뉴 막대 아래로 밀어낸다. 그대로 쓰도록 덮어쓴다.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class OverlayView: NSView {
    let visualLayers: [CALayer]

    init(frame: NSRect, visualLayers: [CALayer]) {
        self.visualLayers = visualLayers
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        for visualLayer in visualLayers {
            visualLayer.frame = bounds
            layer?.addSublayer(visualLayer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for visualLayer in visualLayers {
            visualLayer.frame = bounds
        }
        CATransaction.commit()
    }
}

/// 색이 고정된 이미터 묶음. 한 발씩 돌려 쓰면서, 쓰던 이미터가 다시 나올 때쯤에는
/// 앞서 터진 파티클이 수명을 다하도록 한다.
private final class EmitterGroup {
    private let shells: [FireworkShell]
    private let emitters: [CAEmitterLayer]
    private var generations: [Int]

    var layers: [CAEmitterLayer] { emitters }
    private var next = 0
    private var style: SparkStyle?

    init(shells: [FireworkShell]) {
        self.shells = shells
        emitters = shells.map { _ in
            let emitter = CAEmitterLayer()
            SparkEmitter.prepare(emitter)
            return emitter
        }
        generations = Array(repeating: 0, count: shells.count)
    }

    /// 이 묶음이 쓸 크기로 파티클을 올린다. 크기가 그대로면 다시 올리지 않는다.
    /// 다시 올리면 진행 중이던 파티클이 사라지기 때문이다.
    func setStyle(_ newStyle: SparkStyle, image: CGImage, displayScale: CGFloat) {
        guard style != newStyle else { return }
        style = newStyle
        for index in emitters.indices {
            SparkEmitter.load(
                emitters[index],
                shell: shells[index],
                style: newStyle,
                image: image,
                displayScale: displayScale
            )
        }
    }

    func burst(at point: CGPoint) {
        guard style != nil else { return }

        let index = next
        next = (next + 1) % emitters.count
        let emitter = emitters[index]

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emitter.emitterPosition = point
        emitter.birthRate = 1
        CATransaction.commit()

        // 잠깐만 방출하고 멈춘다. 더 새로운 발사가 들어오면 그쪽 타이머가 끄도록 한다.
        generations[index] &+= 1
        let generation = generations[index]
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(SparkStyle.burstDuration) + 0.01) {
            [weak emitter] in
            guard let emitter, self.generations[index] == generation else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            emitter.birthRate = 0
            CATransaction.commit()
        }
    }

    func teardown() {
        for emitter in emitters {
            emitter.birthRate = 0
            emitter.emitterCells = []
        }
        style = nil
    }
}

/// 화면 하나에 대응하는 투명 창.
/// 입력(키보드/마우스)과 크기(평소/가끔 크게)마다 이미터 묶음을 따로 둔다.
/// 한 묶음에서 설정을 바꿔 가며 쓰면 바꿀 때마다 진행 중인 파티클이 지워지기 때문이다.
private final class ScreenSlot {
    let screen: NSScreen
    let window: OverlayWindow
    let view: OverlayView

    private let groups: [EmitterGroup]
    private let ripples = RippleEmitter()

    init(screen: NSScreen, shells: [FireworkShell]) {
        self.screen = screen
        groups = (0..<(Trigger.allCases.count * 2)).map { _ in EmitterGroup(shells: shells) }

        let frame = screen.frame
        window = OverlayWindow(
            contentRect: NSRect(origin: .zero, size: frame.size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        view = OverlayView(
            frame: NSRect(origin: .zero, size: frame.size),
            visualLayers: groups.flatMap { $0.layers as [CALayer] } + [ripples.layer]
        )
        window.contentView = view
        window.setFrame(frame, display: false)
        window.orderFrontRegardless()
    }

    func configure(effect: VisualEffect, size: EffectSize, image: CGImage?) {
        ripples.clear()
        if effect == .fireworks, let style = size.style,
           let bigStyle = EffectSize.large.style, let image {
            let scale = screen.backingScaleFactor
            for trigger in Trigger.allCases {
                group(trigger, isBig: false).setStyle(style.adjusted(for: trigger), image: image, displayScale: scale)
                group(trigger, isBig: true).setStyle(bigStyle.adjusted(for: trigger), image: image, displayScale: scale)
            }
        } else {
            for group in groups { group.teardown() }
        }
    }

    func ripple(at point: CGPoint, trigger: Trigger, size: EffectSize) {
        ripples.burst(at: point, size: size, trigger: trigger, displayScale: screen.backingScaleFactor)
    }

    func burst(at point: CGPoint, trigger: Trigger, isBig: Bool) {
        group(trigger, isBig: isBig).burst(at: point)
    }

    func teardown() {
        for group in groups {
            group.teardown()
        }
        ripples.clear()
        window.orderOut(nil)
        window.close()
    }

    private func group(_ trigger: Trigger, isBig: Bool) -> EmitterGroup {
        groups[trigger.rawValue * 2 + (isBig ? 1 : 0)]
    }
}

/// 화면마다 클릭을 통과하는 투명 창에서 불꽃 또는 물방울을 표시한다.
final class SparkOverlay {
    /// 이 횟수마다 한 번은 '크게'로 터뜨려 단조로움을 던다.
    private static let bigBurstInterval = 30

    private var slots: [ScreenSlot] = []
    private let sparkImage: CGImage?
    private var screenObserver: NSObjectProtocol?
    private var burstCount = 0

    init() {
        sparkImage = SparkImage.make()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildAfterScreenChange()
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    /// 효과 종류나 크기가 바뀌었을 때 호출. 없음이면 창을 모두 걷어낸다.
    func apply(size: EffectSize) {
        guard Prefs.visualEffect != .none else {
            teardown()
            return
        }
        for slot in slots {
            slot.configure(effect: Prefs.visualEffect, size: size, image: sparkImage)
        }
    }

    /// 지정한 전역 좌표(AppKit 기준)에서 선택한 시각 효과를 표시한다.
    func fire(at point: CGPoint, trigger: Trigger) {
        guard Prefs.visualEffect != .none else { return }

        ensureSlots()
        guard let slot = slot(near: point) else { return }

        let frame = slot.screen.frame
        let local = CGPoint(
            x: min(max(point.x - frame.minX, 0), frame.width),
            y: min(max(point.y - frame.minY, 0), frame.height)
        )
        switch Prefs.visualEffect {
        case .none: return
        case .fireworks:
            burstCount += 1
            slot.burst(at: local, trigger: trigger, isBig: burstCount % Self.bigBurstInterval == 0)
        case .ripple:
            slot.ripple(at: local, trigger: trigger, size: Prefs.effectSize)
        }
    }

    // MARK: - 창 관리

    private func ensureSlots() {
        let screens = NSScreen.screens
        if !slots.isEmpty,
           slots.count == screens.count,
           zip(slots, screens).allSatisfy({ $0.screen === $1 }) {
            return
        }
        teardown()
        // 색마다 두 발씩 두어 재사용 주기를 늘린다.
        slots = screens.map { ScreenSlot(screen: $0, shells: FireworkShell.all + FireworkShell.all) }
        apply(size: Prefs.effectSize)
    }

    private func teardown() {
        for slot in slots {
            slot.teardown()
        }
        slots.removeAll()
    }

    private func rebuildAfterScreenChange() {
        guard !slots.isEmpty else { return }
        teardown()
        ensureSlots()
    }

    private func slot(near point: CGPoint) -> ScreenSlot? {
        if let exact = slots.first(where: { $0.screen.frame.contains(point) }) { return exact }

        func squared(_ frame: CGRect) -> CGFloat {
            let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
            return dx * dx + dy * dy
        }
        return slots.min { squared($0.screen.frame) < squared($1.screen.frame) }
    }
}
