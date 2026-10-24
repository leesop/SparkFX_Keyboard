import AppKit
import QuartzCore

/// Pastel rings spread from a tiny drop. Each input owns its layers, so fast
/// typing does not restart ripples already in flight.
final class RippleEmitter {
    static let maximumBursts = 24
    static let ringDuration: CFTimeInterval = 0.68
    static let ringDelay: CFTimeInterval = 0.09
    static let lifetime = ringDuration + ringDelay * 2 + 0.05

    let layer = CALayer()

    static func radius(size: EffectSize, trigger: Trigger) -> CGFloat {
        (size == .small ? 30 : 44) * trigger.sizeFactor
    }

    func burst(at point: CGPoint, size: EffectSize, trigger: Trigger, displayScale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Bound the cost even during very fast typing or repeated clicks.
        while let children = layer.sublayers, children.count >= Self.maximumBursts {
            children.first?.removeFromSuperlayer()
        }
        let burst = Self.makeBurst(at: point, size: size, trigger: trigger, displayScale: displayScale)
        layer.addSublayer(burst)
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime) { [weak burst] in
            burst?.removeFromSuperlayer()
        }
    }

    func clear() {
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
    }

    static func makeBurst(at point: CGPoint, size: EffectSize, trigger: Trigger, displayScale: CGFloat) -> CALayer {
        let radius = Self.radius(size: size, trigger: trigger)
        let bounds = CGRect(x: 0, y: 0, width: radius * 2 + 8, height: radius * 2 + 8)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let burst = CALayer()
        burst.name = "water-droplet"
        burst.bounds = bounds
        burst.position = point
        burst.contentsScale = displayScale
        burst.masksToBounds = false

        let colors = [
            NSColor(srgbRed: 0.28, green: 0.77, blue: 0.96, alpha: 1),
            NSColor(srgbRed: 0.63, green: 0.63, blue: 0.98, alpha: 1),
            NSColor(srgbRed: 0.39, green: 0.88, blue: 0.79, alpha: 1),
        ]
        let start = CACurrentMediaTime()
        for index in 0..<3 {
            let ring = CAShapeLayer()
            ring.name = "ripple-\(index)"
            ring.frame = bounds
            ring.contentsScale = displayScale
            let outerRadius = radius * (1 - CGFloat(index) * 0.16)
            ring.path = circle(center: center, radius: outerRadius)
            ring.fillColor = nil
            ring.strokeColor = colors[index].cgColor
            ring.lineWidth = (size == .small ? 1.6 : 2.0) * trigger.sizeFactor
            ring.lineCap = .round
            ring.opacity = 0
            ring.shadowColor = colors[index].cgColor
            ring.shadowOpacity = 0.18
            ring.shadowRadius = 2
            ring.shadowOffset = .zero

            let grow = CABasicAnimation(keyPath: "path")
            grow.fromValue = circle(center: center, radius: 2)
            grow.toValue = ring.path
            grow.duration = ringDuration
            grow.timingFunction = CAMediaTimingFunction(name: .easeOut)

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.8 * trigger.opacityFactor, 0.45 * trigger.opacityFactor, 0]
            fade.keyTimes = [0, 0.1, 0.6, 1]
            fade.duration = ringDuration

            let animation = CAAnimationGroup()
            animation.animations = [grow, fade]
            animation.beginTime = start + Double(index) * ringDelay
            animation.duration = ringDuration
            animation.fillMode = .both
            ring.add(animation, forKey: "spread")
            burst.addSublayer(ring)
        }

        // A small glossy bead makes the center feel like a drop landing.
        let bead = CAShapeLayer()
        bead.name = "drop"
        bead.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
        bead.position = center
        bead.path = CGPath(ellipseIn: bead.bounds.insetBy(dx: 0.8, dy: 0.8), transform: nil)
        bead.fillColor = colors[0].withAlphaComponent(0.45).cgColor
        bead.strokeColor = NSColor.white.withAlphaComponent(0.8).cgColor
        bead.lineWidth = 0.8
        bead.contentsScale = displayScale
        bead.opacity = 0

        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.4, 1, 0.2]
        pop.keyTimes = [0, 0.25, 1]
        pop.duration = 0.28
        let disappear = CABasicAnimation(keyPath: "opacity")
        disappear.fromValue = trigger.opacityFactor
        disappear.toValue = 0
        disappear.duration = 0.28
        let landing = CAAnimationGroup()
        landing.animations = [pop, disappear]
        landing.duration = 0.28
        bead.add(landing, forKey: "landing")
        burst.addSublayer(bead)
        return burst
    }

    private static func circle(center: CGPoint, radius: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2), transform: nil)
    }
}
