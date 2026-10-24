import AppKit
import ApplicationServices
import IOKit.hid

/// 현재 텍스트 입력 커서(캐럿)의 위치를 접근성 API로 찾는다.
enum CaretLocator {
    /// 접근성 권한이 없으면 시스템 설정 안내를 띄우고 현재 상태를 돌려준다.
    @discardableResult
    static func requestPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 키 입력을 관찰하려면 "손쉬운 접근"과는 별개로 "입력 모니터링" 권한이 필요하다.
    /// 손쉬운 접근만 켜면 마우스 이벤트는 오지만 키 이벤트는 오지 않는다.
    static var hasInputMonitoring: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// 진단용: 입력 모니터링 권한을 시스템이 어떻게 보고 있는지.
    /// '미결정'이면 아직 물어본 적이 없다는 뜻이라 목록에도 없을 수 있다.
    static var inputMonitoringDescription: String {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return "허용"
        case kIOHIDAccessTypeDenied: return "거부"
        default: return "미결정"
        }
    }

    /// 입력 모니터링 권한을 요청한다. 시스템 설정에서 직접 켜야 하고, 켠 뒤에는 앱을 다시 실행해야 한다.
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// 어디서 위치를 얻었는지 알려주는 진단용 갈고리.
    static var trace: ((String) -> Void)?

    /// 이미 접근성 트리를 켜 달라고 한 앱들. 매번 다시 요청하지 않으려고 기억한다.
    private static var requestedApps = Set<pid_t>()
    private static let requestedAppsLock = NSLock()

    /// Chromium/Electron 앱에 접근성 트리를 켜 달라고 요청한다.
    ///
    /// 실측으로 확인한 것: 이 두 속성을 **이 순서로** 켜야 그제야 `boundsForRange`가
    /// 크기가 있는 진짜 커서 사각형을 돌려준다. 하나만 켜면 크기 0인 사각형이 온다.
    /// VoiceOver가 켜는 것과 같은 스위치라, 해당 앱은 접근성 트리를 통째로 만들기 시작한다.
    /// 트리를 다 만드는 데 **실측 1.8초쯤** 걸린다. 그래서 켠 직후의 재시도는 보통 실패하고,
    /// 그 앱에서 몇 초쯤 지난 뒤부터 정확한 커서가 잡힌다.
    @discardableResult
    static func requestAccessibilityTree(for pid: pid_t) -> Bool {
        requestedAppsLock.lock()
        let isNew = requestedApps.insert(pid).inserted
        requestedAppsLock.unlock()
        guard isNew else { return false }

        let app = AXUIElementCreateApplication(pid)
        // 순서가 중요하다. Enhanced를 먼저 켜야 Manual이 먹는다.
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return true
    }

    /// 켜 달라고 했던 앱들의 트리를 다시 닫아 준다. 설정을 끄면 부담도 사라져야 한다.
    static func releaseAccessibilityTrees() {
        requestedAppsLock.lock()
        let pids = requestedApps
        requestedApps.removeAll()
        requestedAppsLock.unlock()

        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanFalse)
        }
    }

    /// 캐럿 기준으로 불꽃을 어디에 둘지.
    enum Placement {
        /// 새 글자가 들어가는 자리. 커서 막대에서 한 글자쯤 오른쪽으로 비킨다.
        case typing
        /// 백스페이스. 지운 자리를 보게 되므로 커서에 바짝 붙인다.
        case deleting

        func distance(forGlyphHeight height: CGFloat) -> CGFloat {
            switch self {
            case .typing: return min(max(height * 1.0, 12), 36)
            case .deleting: return min(max(height * 0.5, 6), 20)
            }
        }
    }

    /// 캐럿 위치를 AppKit 전역 좌표(좌하단 원점)로 반환. 알 수 없으면 nil.
    ///
    /// 커서 위치를 알려주는 앱이면 정확한 캐럿 자리를, 알려주지 않는 앱(터미널, 일부 Electron 앱)이면
    /// 입력 영역의 왼쪽 아래를 돌려준다.
    static func caretPoint(placement: Placement = .typing) -> CGPoint? {
        guard AXIsProcessTrusted() else {
            trace?("접근성 권한 없음")
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.2)

        guard let focused = focusedElement(of: systemWide) else {
            trace?("포커스된 요소를 알 수 없음")
            return nil
        }

        if let point = caretGlyphPoint(in: focused, placement: placement) {
            trace?("캐럿 위치 \(point)")
            return point
        }

        // 커서를 알려주지 않는 앱이면, 접근성 트리를 켜 달라고 한 번 요청하고 다시 물어본다.
        if Prefs.accurateCaret, let pid = processID(of: focused) {
            if requestAccessibilityTree(for: pid) {
                trace?("접근성 트리를 켜 달라고 요청함 (pid \(pid))")
            }
            if let refreshed = focusedElement(of: systemWide),
               let point = caretGlyphPoint(in: refreshed, placement: placement) {
                trace?("접근성 트리를 켠 뒤 캐럿 위치 \(point)")
                return point
            }
        }

        if let point = focusAreaPoint(in: focused) {
            trace?("커서 위치를 알려주지 않는 앱. 입력 영역 왼쪽 아래 \(point) 사용")
            return point
        }
        trace?("위치를 찾지 못함")
        return nil
    }

    private static func focusedElement(of systemWide: AXUIElement) -> AXUIElement? {
        guard let ref = copy(systemWide, kAXFocusedUIElementAttribute),
              CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(ref, to: AXUIElement.self)
    }

    private static func processID(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }

    /// 캐럿이 놓인 글자의 자리. 많은 앱이 여기까지는 알려준다.
    private static func caretGlyphPoint(in element: AXUIElement, placement: Placement) -> CGPoint? {
        guard let rangeRef = copy(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return nil }

        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(rangeRef, to: AXValue.self), .cfRange, &range) else { return nil }

        // 캐럿은 "다음 글자의 왼쪽 끝", 문장 끝이면 "앞 글자의 오른쪽 끝"에 있다.
        let insertion = range.location
        let candidates: [CFRange] = [
            CFRange(location: insertion, length: 1),
            CFRange(location: insertion - 1, length: 1),
            CFRange(location: insertion, length: 0),
        ]

        for candidate in candidates where candidate.location >= 0 {
            guard let rect = bounds(element, candidate) else { continue }
            let x = candidate.length == 0 || candidate.location == insertion ? rect.minX : rect.maxX
            let point = CGPoint(x: x, y: rect.midY)
            if isOnSomeScreen(point), let converted = appKitPoint(fromQuartz: point) {
                return CGPoint(x: converted.x + placement.distance(forGlyphHeight: rect.height), y: converted.y)
            }
        }
        return nil
    }

    /// 커서 위치를 알려주지 않는 앱을 위한 차선책: 포커스된 입력 영역의 왼쪽 아래.
    /// 터미널은 프롬프트가, 한 줄 입력란은 글자가 아래쪽에 있기 때문이다.
    private static func focusAreaPoint(in element: AXUIElement) -> CGPoint? {
        guard let positionRef = copy(element, kAXPositionAttribute),
              CFGetTypeID(positionRef) == AXValueGetTypeID()
        else { return nil }

        var origin = CGPoint.zero
        guard AXValueGetValue(unsafeBitCast(positionRef, to: AXValue.self), .cgPoint, &origin),
              origin.x.isFinite, origin.y.isFinite
        else { return nil }

        var size = CGSize.zero
        if let sizeRef = copy(element, kAXSizeAttribute), CFGetTypeID(sizeRef) == AXValueGetTypeID() {
            _ = AXValueGetValue(unsafeBitCast(sizeRef, to: AXValue.self), .cgSize, &size)
        }
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }

        // 접근성 좌표는 y가 아래로 증가하므로 origin.y + height가 영역의 아래쪽이다.
        let point = CGPoint(
            x: origin.x + min(28, size.width * 0.06),
            y: origin.y + size.height - min(22, size.height * 0.14)
        )
        guard isOnSomeScreen(point) else { return nil }
        return appKitPoint(fromQuartz: point)
    }

    // MARK: - 좌표 변환

    /// 접근성 API는 좌상단 원점(Quartz) 좌표를 쓴다. 화면 좌표계로 변환한다.
    static func appKitPoint(fromQuartz p: CGPoint) -> CGPoint? {
        guard let primary = NSScreen.screens.first else { return nil }
        return CGPoint(x: p.x, y: primary.frame.maxY - p.y)
    }

    private static func isOnSomeScreen(_ quartzPoint: CGPoint) -> Bool {
        guard let appKit = appKitPoint(fromQuartz: quartzPoint) else { return false }
        return NSScreen.screens.contains { $0.frame.insetBy(dx: -4, dy: -4).contains(appKit) }
    }

    // MARK: - 접근성 헬퍼

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func bounds(_ element: AXUIElement, _ range: CFRange) -> CGRect? {
        var range = range
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }

        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &result
        ) == .success,
        let resultRef = result, CFGetTypeID(resultRef) == AXValueGetTypeID()
        else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(unsafeBitCast(resultRef, to: AXValue.self), .cgRect, &rect) else { return nil }
        guard rect.width.isFinite, rect.height.isFinite,
              rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.height > 0
        else { return nil }
        return rect
    }
}
