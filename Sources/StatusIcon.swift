import AppKit

/// 메뉴 막대용 불꽃놀이 아이콘. 템플릿 이미지라 라이트/다크 모드에 맞춰 자동으로 반전된다.
enum StatusIcon {
    static func make(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            // 18pt에서는 가는 줄기가 사라지므로 굵기를 키우고 가짓수를 줄인다.
            let glyph = rect.insetBy(dx: rect.width * 0.03, dy: rect.height * 0.03)
            context.addPath(FireworkShape.path(
                in: glyph,
                spokes: 8,
                innerRadius: 0.14,
                outerRadius: 0.90,
                startAngle: .pi / 2,
                lengthPattern: [1.0, 0.82],
                baseHalfWidth: 0.09,
                tipHalfWidth: 0.028,
                centerRadius: 0.17
            ))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fillPath()

            return true
        }
        image.isTemplate = true
        return image
    }
}
