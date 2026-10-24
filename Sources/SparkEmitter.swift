import CoreGraphics
import QuartzCore

/// 불꽃놀이 한 발의 색 구성.
struct FireworkShell {
    let core: CGColor
    let main: CGColor
    let ember: CGColor

    static let all: [FireworkShell] = [
        FireworkShell(core: .rgb(1.00, 0.97, 0.80), main: .rgb(1.00, 0.78, 0.20), ember: .rgb(1.00, 0.45, 0.06)),
        FireworkShell(core: .rgb(1.00, 0.95, 0.82), main: .rgb(1.00, 0.55, 0.14), ember: .rgb(0.88, 0.20, 0.04)),
        FireworkShell(core: .rgb(1.00, 0.88, 0.86), main: .rgb(1.00, 0.33, 0.26), ember: .rgb(0.72, 0.07, 0.05)),
        FireworkShell(core: .rgb(0.94, 0.99, 1.00), main: .rgb(0.49, 0.86, 1.00), ember: .rgb(0.13, 0.44, 0.92)),
        FireworkShell(core: .rgb(0.88, 1.00, 0.96), main: .rgb(0.38, 0.90, 0.68), ember: .rgb(0.05, 0.55, 0.48)),
        FireworkShell(core: .rgb(1.00, 0.90, 0.99), main: .rgb(0.83, 0.48, 1.00), ember: .rgb(0.45, 0.16, 0.86)),
    ]
}

/// 불꽃놀이 파티클의 모양과 움직임. 창과 무관하게 레이어 하나만 설정한다.
enum SparkEmitter {

    /// 레이어의 공통 설정. 창을 만들 때 한 번만 부른다.
    static func prepare(_ emitter: CAEmitterLayer) {
        emitter.emitterShape = .point
        emitter.emitterMode = .points
        // 투명한 배경 위에서는 가산 혼합이 통째로 사라질 수 있다. 확실히 보이는 alpha 합성으로 그린다.
        emitter.renderMode = .unordered
        emitter.emitterSize = .zero
        emitter.emitterPosition = CGPoint(x: -4000, y: -4000)
        emitter.birthRate = 0
    }

    /// 이번 터짐에 쓸 파티클들을 준비한다. 색은 레이어마다 고정이라 진행 중인 파티클이 바뀌지 않는다.
    static func load(
        _ emitter: CAEmitterLayer,
        shell: FireworkShell,
        style: SparkStyle,
        image: CGImage,
        displayScale: CGFloat
    ) {
        emitter.emitterCells = cells(shell: shell, style: style, image: image, displayScale: displayScale)
    }

    private static func cells(
        shell: FireworkShell,
        style: SparkStyle,
        image: CGImage,
        displayScale: CGFloat
    ) -> [CAEmitterCell] {
        let duration = Double(SparkStyle.burstDuration)

        func make(
            _ color: CGColor,
            share: Float,
            scale: CGFloat,
            speed: CGFloat,
            lifetime: Float,
            gravity: CGFloat,
            fade: Float,
            spin: CGFloat,
            spread: CGFloat
        ) -> CAEmitterCell {
            let cell = CAEmitterCell()
            cell.contents = image
            cell.contentsScale = displayScale
            cell.color = color.copy(alpha: style.opacity) ?? color
            cell.birthRate = style.count * share / Float(duration)
            cell.lifetime = lifetime
            cell.lifetimeRange = lifetime * 0.3
            cell.velocity = speed
            cell.velocityRange = speed * spread
            cell.emissionRange = .pi * 2
            cell.yAcceleration = -(style.gravity * gravity)
            cell.scale = scale
            cell.scaleRange = scale * 0.4
            cell.scaleSpeed = -scale * 0.55
            cell.alphaSpeed = fade
            cell.spin = spin
            cell.spinRange = spin * 4
            return cell
        }

        let s = style.scale
        return [
            // 폭발 중심의 밝은 심지
            make(shell.core, share: 0.16, scale: s * 0.55, speed: style.speed * 1.15,
                 lifetime: style.lifetime * 0.40, gravity: 0.6, fade: -3.4, spin: 0, spread: 0.22),
            // 바깥 껍질: 조금 더 멀리까지 퍼진다
            make(shell.main, share: 0.14, scale: s * 0.70, speed: style.speed * 1.45,
                 lifetime: style.lifetime * 0.95, gravity: 1.0, fade: -1.7, spin: 0.6, spread: 0.14),
            // 몸통: 같은 반지름에 모여 링을 이룬다
            make(shell.main, share: 0.44, scale: s, speed: style.speed,
                 lifetime: style.lifetime, gravity: 1.0, fade: -1.5, spin: 1.2, spread: 0.10),
            // 안쪽 잔불: 느리고 오래 살며 아래로 흘러내린다
            make(shell.ember, share: 0.26, scale: s * 1.35, speed: style.speed * 0.62,
                 lifetime: style.lifetime * 1.5, gravity: 1.7, fade: -0.85, spin: 2.2, spread: 0.20),
        ]
    }
}

/// 파티클 하나를 부드러운 흰 점으로 그린 이미지. 색은 셀의 color가 곱해 준다.
enum SparkImage {
    static func make(diameter: Int = 64) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: diameter,
                height: diameter,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        let colors = [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.6),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.4, 1]) else {
            return nil
        }

        let center = CGPoint(x: CGFloat(diameter) / 2, y: CGFloat(diameter) / 2)
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: CGFloat(diameter) / 2,
            options: []
        )
        return context.makeImage()
    }
}

private extension CGColor {
    static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
