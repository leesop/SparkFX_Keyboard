import CoreGraphics

/// 불꽃놀이가 터진 모양. 중심에서 사방으로 뻗다가 끝으로 갈수록 가늘어지는 빛줄기와 가운데 알갱이,
/// 그리고 주변에 흩어진 불티로 이루어진다. 빛줄기 길이를 크게 흔들어야 눈송이 같은 대칭 도형으로 보이지 않는다.
/// 지름이 작은 메뉴 막대 아이콘과 큰 앱 아이콘이 같은 비율을 쓰도록 모든 치수를 반지름 대비 비율로 받는다.
enum FireworkShape {
    static func path(
        in rect: CGRect,
        spokes: Int = 14,
        innerRadius: CGFloat = 0.05,
        outerRadius: CGFloat = 0.92,
        startAngle: CGFloat = .pi / 2 + 0.18,
        lengthPattern: [CGFloat] = [1.0, 0.42, 0.84, 0.5, 0.94, 0.34, 0.72, 0.56],
        baseHalfWidth: CGFloat = 0.055,
        tipHalfWidth: CGFloat = 0.009,
        centerRadius: CGFloat = 0.09
    ) -> CGPath {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let path = CGMutablePath()

        for index in 0..<spokes {
            let angle = CGFloat(index) * (2 * .pi / CGFloat(spokes)) + startAngle
            let pattern = lengthPattern.isEmpty ? 1 : lengthPattern[index % lengthPattern.count]
            let reach = radius * outerRadius * pattern
            let along = CGPoint(x: cos(angle), y: sin(angle))
            let across = CGPoint(x: -along.y, y: along.x)

            func point(_ distance: CGFloat, _ offset: CGFloat) -> CGPoint {
                CGPoint(x: center.x + along.x * distance + across.x * offset,
                        y: center.y + along.y * distance + across.y * offset)
            }

            let base = radius * innerRadius
            let baseWidth = radius * baseHalfWidth
            let tipWidth = radius * tipHalfWidth

            // 알갱이 원과 겹쳐도 하나로 채워지도록 감는 방향을 원과 맞춘다.
            path.move(to: point(base, baseWidth))
            path.addLine(to: point(base, -baseWidth))
            path.addLine(to: point(reach, -tipWidth))
            path.addLine(to: point(reach, tipWidth))
            path.closeSubpath()
        }

        let core = radius * centerRadius
        path.addEllipse(in: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2))

        return path
    }

    /// 빛줄기 사이에 흩어진 불티. (거리, 각도, 크기)를 반지름 대비 비율로 받는다.
    static func sparks(
        in rect: CGRect,
        spots: [(distance: CGFloat, angle: CGFloat, size: CGFloat)] = [
            (0.58, 0.35, 0.035), (0.74, 1.15, 0.028), (0.46, 2.10, 0.032),
            (0.88, 2.75, 0.024), (0.52, 3.60, 0.030), (0.80, 4.30, 0.026),
            (0.62, 5.15, 0.034), (0.94, 5.80, 0.022), (0.38, 4.80, 0.026),
            (0.68, 0.95, 0.022),
        ]
    ) -> CGPath {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let path = CGMutablePath()

        for spot in spots {
            let size = radius * spot.size
            let point = CGPoint(x: center.x + cos(spot.angle) * radius * spot.distance,
                                y: center.y + sin(spot.angle) * radius * spot.distance)
            path.addEllipse(in: CGRect(x: point.x - size, y: point.y - size, width: size * 2, height: size * 2))
        }
        return path
    }
}
