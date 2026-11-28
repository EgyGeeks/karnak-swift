import KarnakCore
import SwiftUI

/// The animation of `easing` over `seconds` (`docs/renderer-contract.md`, Motion): a cubic Bézier as
/// `Animation.timingCurve`, a theme's spring through its values over the whole duration, so a spring takes exactly the
/// transition's duration as every other curve does.
func easingAnimation(_ easing: ResolvedEasing, seconds: Double) -> Animation {
  if let points = easing as? ResolvedEasingPoints {
    return Animation(PointsAnimation(values: points.values.map(\.doubleValue), duration: seconds))
  }
  guard let bezier = easing as? ResolvedEasingBezier else { return .linear(duration: seconds) }
  return .timingCurve(bezier.x1, bezier.y1, bezier.x2, bezier.y2, duration: seconds)
}

/// The eased value at `time`, 0 to 1, of `easing`: the curve every renderer draws.
func easedValue(_ easing: ResolvedEasing, at time: Double) -> Double {
  if let points = easing as? ResolvedEasingPoints {
    return PointsAnimation.value(points.values.map(\.doubleValue), at: time)
  }
  guard let bezier = easing as? ResolvedEasingBezier else { return min(max(time, 0), 1) }
  return CubicBezier(bezier).value(at: time)
}

/// A curve given by its values at equally spaced times, as CSS `linear(v0, v1, …)`: a theme's spring, which may
/// pass 1 while it overshoots and ends at 1.
struct PointsAnimation: CustomAnimation {
  let values: [Double]
  let duration: TimeInterval

  func animate<V: VectorArithmetic>(
    value: V, time: TimeInterval, context: inout AnimationContext<V>
  ) -> V? {
    guard duration > 0, time < duration else { return nil }
    return value.scaled(by: Self.value(values, at: time / duration))
  }

  /// The straight line between the two values around `time`, 0 to 1.
  static func value(_ values: [Double], at time: Double) -> Double {
    guard values.count >= 2, time > 0 else { return 0 }
    guard time < 1 else { return 1 }
    let position = time * Double(values.count - 1)
    let index = min(Int(position), values.count - 2)
    let fraction = position - Double(index)
    return values[index] + (values[index + 1] - values[index]) * fraction
  }
}
