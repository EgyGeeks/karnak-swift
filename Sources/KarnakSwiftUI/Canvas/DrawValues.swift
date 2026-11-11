import CoreGraphics
import Foundation
import KarnakCore

/// The values of a canvas's draw ops at the frame being drawn (`docs/renderer-contract.md`, Canvas; ADR 0037, D11): a
/// fixed number or paint is itself, a loop is `from + (to - from) * easing(t)` on ``nowMillis``, and a loop that isn't
/// running (the canvas off screen, in the background, or Reduce Motion on) is its `rest`.
struct DrawValues {
  /// The clock of the frame being drawn, in milliseconds.
  var nowMillis: Int64 = 0
  /// Whether loops run; when not, a loop draws at its `rest`.
  var running = false

  /// `number` at this frame.
  func number(_ number: ResolvedDrawNumber) -> CGFloat {
    guard let looped = number as? ResolvedDrawNumberLooped else { return CGFloat(number.atRest) }
    return running ? mixed(looped) : CGFloat(looped.rest)
  }

  /// The point `point` names at this frame.
  func point(_ point: ResolvedPoint) -> CGPoint {
    CGPoint(x: number(point.x), y: number(point.y))
  }

  /// `paint` at this frame.
  func frame(of paint: ResolvedDrawPaint) -> PaintFrame {
    guard let looped = paint as? ResolvedDrawPaintLooped, running else {
      return PaintTarget.of(paint.atRest_).frame()
    }
    return PaintFrame.mix(
      PaintTarget.of(looped.from), PaintTarget.of(looped.to), fraction: progress(looped.timing))
      ?? PaintTarget.of(looped.rest).frame()
  }

  private func mixed(_ loop: ResolvedDrawNumberLooped) -> CGFloat {
    CGFloat(loop.from + (loop.to - loop.from) * progress(loop.timing))
  }

  /// The eased position in the cycle at ``nowMillis``; with `alternate` a cycle goes there and back.
  func progress(_ timing: ResolvedLoopTiming) -> Double {
    let duration = Int64(timing.durationMillis)
    // A token can resolve to 0 ms (a theme allows it): the loop is at its end, never a division by zero.
    guard duration > 0 else { return 1 }
    let period = timing.alternate ? duration * 2 : duration
    let phase = ((nowMillis % period) + period) % period
    let leg = phase < duration ? phase : period - phase
    return CubicBezier(timing.easing).value(at: Double(leg) / Double(duration))
  }
}

/// A cubic Bézier easing curve as CSS `cubic-bezier(x1, y1, x2, y2)`: the same curve the transitions and the other
/// renderers use.
struct CubicBezier {
  let x1: Double
  let y1: Double
  let x2: Double
  let y2: Double

  init(_ easing: ResolvedEasing) {
    x1 = easing.x1
    y1 = easing.y1
    x2 = easing.x2
    y2 = easing.y2
  }

  /// The eased value at `time`, 0 to 1: the curve's y where its x is `time`.
  func value(at time: Double) -> Double {
    let x = min(max(time, 0), 1)
    return Self.coordinate(y1, y2, at: parameter(forX: x))
  }

  private func parameter(forX x: Double) -> Double {
    var low = 0.0
    var high = 1.0
    var t = x
    for _ in 0..<Self.iterations {
      let error = Self.coordinate(x1, x2, at: t) - x
      if abs(error) < Self.tolerance { break }
      if error > 0 { high = t } else { low = t }
      t = (low + high) / 2
    }
    return t
  }

  /// One coordinate of the curve from (0, 0) to (1, 1) with control values `a` and `b`, at parameter `t`.
  private static func coordinate(_ a: Double, _ b: Double, at t: Double) -> Double {
    let u = 1 - t
    return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
  }

  private static let iterations = 40
  private static let tolerance = 1e-6
}
