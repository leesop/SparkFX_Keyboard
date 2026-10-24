import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// AppIcon.iconset 폴더에 필요한 크기의 PNG를 만든다. 결과는 build.sh에서 iconutil로 묶는다.

@main
enum IconGen {
    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    static let variants: [(name: String, pixels: Int)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]

    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            FileHandle.standardError.write("usage: icongen <output.iconset>\n".data(using: .utf8)!)
            exit(1)
        }
        let outputDirectory = arguments[1]
        try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

        for variant in variants {
            guard let image = render(pixels: variant.pixels) else {
                FileHandle.standardError.write("render failed: \(variant.name)\n".data(using: .utf8)!)
                exit(1)
            }
            let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(variant.name)
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
            ) else {
                FileHandle.standardError.write("cannot write: \(variant.name)\n".data(using: .utf8)!)
                exit(1)
            }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
    }

    static func render(pixels: Int) -> CGImage? {
        let side = CGFloat(pixels)
        guard let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setShouldAntialias(true)
        context.interpolationQuality = .high

        // 밤하늘 배경: macOS 아이콘처럼 여백을 두고 둥근 사각형으로 자른다.
        let inset = side * 0.095
        let background = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
        let radius = background.width * 0.2237
        let clip = CGPath(roundedRect: background, cornerWidth: radius, cornerHeight: radius, transform: nil)

        context.saveGState()
        context.addPath(clip)
        context.clip()

        if let sky = CGGradient(
            colorsSpace: space,
            colors: [
                CGColor(srgbRed: 0.16, green: 0.12, blue: 0.38, alpha: 1),
                CGColor(srgbRed: 0.04, green: 0.03, blue: 0.14, alpha: 1),
            ] as CFArray,
            locations: [0, 1]
        ) {
            context.drawLinearGradient(
                sky,
                start: CGPoint(x: background.midX, y: background.maxY),
                end: CGPoint(x: background.midX, y: background.minY),
                options: []
            )
        }

        // 배경에 흩뿌린 작은 별
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.5))
        let stars: [(CGFloat, CGFloat, CGFloat)] = [
            (0.16, 0.86, 0.010), (0.30, 0.94, 0.007), (0.72, 0.90, 0.009),
            (0.88, 0.72, 0.007), (0.12, 0.30, 0.008), (0.84, 0.16, 0.010),
            (0.60, 0.06, 0.007), (0.40, 0.10, 0.006), (0.50, 0.96, 0.006),
        ]
        for star in stars {
            let r = background.width * star.2
            let center = CGPoint(x: background.minX + background.width * star.0,
                                 y: background.minY + background.height * star.1)
            context.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }

        // 올라가는 궤적. 이것이 있어야 방사형 도형이 "불꽃놀이"로 읽힌다.
        drawTrail(
            context,
            background: background,
            from: CGPoint(x: background.minX + background.width * 0.28,
                          y: background.minY - background.height * 0.02),
            to: CGPoint(x: background.minX + background.width * 0.45,
                        y: background.minY + background.height * 0.36),
            control: CGPoint(x: background.minX + background.width * 0.26,
                             y: background.minY + background.height * 0.22),
            tip: CGColor(srgbRed: 1.00, green: 0.72, blue: 0.24, alpha: 1)
        )
        drawTrail(
            context,
            background: background,
            from: CGPoint(x: background.minX + background.width * 0.14,
                          y: background.minY + background.height * 0.42),
            to: CGPoint(x: background.minX + background.width * 0.19,
                        y: background.minY + background.height * 0.68),
            control: CGPoint(x: background.minX + background.width * 0.11,
                             y: background.minY + background.height * 0.56),
            tip: CGColor(srgbRed: 0.40, green: 0.93, blue: 0.85, alpha: 1)
        )

        // 작은 불꽃들을 뒤에, 큰 불꽃을 앞에 그린다. 한가운데에 두면 도형처럼 보여 조금씩 치우친다.
        drawBurst(
            context,
            center: CGPoint(x: background.minX + background.width * 0.20,
                            y: background.minY + background.height * 0.77),
            radius: background.width * 0.14,
            tip: CGColor(srgbRed: 0.40, green: 0.93, blue: 0.85, alpha: 1)
        )
        drawBurst(
            context,
            center: CGPoint(x: background.minX + background.width * 0.81,
                            y: background.minY + background.height * 0.22),
            radius: background.width * 0.12,
            tip: CGColor(srgbRed: 0.95, green: 0.50, blue: 1.00, alpha: 1)
        )
        drawBurst(
            context,
            center: CGPoint(x: background.minX + background.width * 0.47,
                            y: background.minY + background.height * 0.53),
            radius: background.width * 0.30,
            tip: CGColor(srgbRed: 1.00, green: 0.63, blue: 0.13, alpha: 1)
        )

        context.restoreGState()
        return context.makeImage()
    }

    /// 불꽃이 올라간 자취. 가는 선 하나와 그 위에 작아지는 불티로 그린다.
    static func drawTrail(
        _ context: CGContext,
        background: CGRect,
        from start: CGPoint,
        to end: CGPoint,
        control: CGPoint,
        tip: CGColor
    ) {
        func point(at t: CGFloat) -> CGPoint {
            let inverse = 1 - t
            return CGPoint(
                x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
                y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
            )
        }

        let curve = CGMutablePath()
        curve.move(to: start)
        curve.addQuadCurve(to: end, control: control)

        context.saveGState()
        context.setStrokeColor(tip.copy(alpha: 0.55) ?? tip)
        context.setLineWidth(background.width * 0.009)
        context.setLineCap(.round)
        context.addPath(curve)
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.setFillColor(tip.copy(alpha: 0.85) ?? tip)
        for step in 1...5 {
            let t = CGFloat(step) / 5.4
            let dot = background.width * 0.010 * (0.6 + t)
            let spot = point(at: t)
            context.fillEllipse(in: CGRect(x: spot.x - dot, y: spot.y - dot, width: dot * 2, height: dot * 2))
        }
        context.restoreGState()
    }

    static func drawBurst(_ context: CGContext, center: CGPoint, radius: CGFloat, tip: CGColor) {
        let box = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let shape = FireworkShape.path(in: box)
        let sparks = FireworkShape.sparks(in: box)

        // 빛무리: 연속된 원형 그라데이션이라야 뭉친 자국 없이 부드럽다.
        if let halo = CGGradient(
            colorsSpace: space,
            colors: [tip.copy(alpha: 0.42) ?? tip, tip.copy(alpha: 0) ?? tip] as CFArray,
            locations: [0, 1]
        ) {
            context.drawRadialGradient(
                halo,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: radius * 1.15,
                options: []
            )
        }

        // 본체: 중심은 하얗고 끝으로 갈수록 색이 진해진다.
        context.saveGState()
        context.addPath(shape)
        context.addPath(sparks)
        context.clip()
        if let gradient = CGGradient(
            colorsSpace: space,
            colors: [
                CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                tip,
            ] as CFArray,
            locations: [0, 0.78]
        ) {
            context.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: radius,
                options: []
            )
        }
        context.restoreGState()
    }
}
