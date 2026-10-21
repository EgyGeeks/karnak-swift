import KarnakCore
import SwiftUI

/// A progress indicator (`docs/renderer-contract.md`, `ResolvedProgress` and Display
/// primitives): a ring for the circular kind, a bar that fills the width it is given for the
/// linear one. A loading button's spinner draws it decoratively and the `progress` node's
/// accessibility element is added by ``NodeSemantics``, so the indicator itself is hidden from
/// accessibility.
///
/// - The ring starts at the top and sweeps `value` clockwise, never mirrored; an indeterminate
///   one turns a 90° arc once a second.
/// - The bar has square ends and fills from the leading edge, which a right-to-left layout
///   mirrors; an indeterminate one crosses a segment of a quarter of its length from before the
///   leading edge to past the trailing one, once a second.
/// - With Reduce Motion on, an indeterminate animation takes four seconds and never stops.
struct ProgressIndicatorView: View {
  /// Whether it is a ring or a bar.
  let kind: KarnakCore.ProgressKind
  /// The ring's diameter in points, or the bar's thickness.
  let size: CGFloat
  /// The ring's stroke width in points.
  let thickness: CGFloat
  /// The completed fraction, 0–1; nil for indeterminate.
  let value: CGFloat?
  /// The arc's or the fill's color.
  let color: Color
  /// The full ring or bar behind it; nil for none.
  let track: Color?
  /// Reduce Motion as a test sets it; nil follows the system setting. `accessibilityReduceMotion` is read-only.
  private let reduceMotionOverride: Bool?
  /// The instant a test draws the indeterminate bar at, once; nil follows the clock.
  private let frozenAt: Date?
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.layoutDirection) private var layoutDirection
  @State private var turning = false

  private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

  init(_ progress: ResolvedProgress) {
    self.init(
      kind: progress.kind, size: points(dp: progress.size),
      thickness: points(dp: progress.thickness),
      value: progress.value.map { CGFloat($0.floatValue) }, color: resolvedColor(progress.color),
      track: progress.trackColor.map(resolvedColor))
  }

  init(
    kind: KarnakCore.ProgressKind = .circular, size: CGFloat, thickness: CGFloat, value: CGFloat?,
    color: Color, track: Color? = nil, reduceMotion: Bool? = nil, frozenAt: Date? = nil
  ) {
    self.reduceMotionOverride = reduceMotion
    self.frozenAt = frozenAt
    self.kind = kind
    self.size = size
    self.thickness = thickness
    self.value = value.map { min(max($0, 0), 1) }
    self.color = color
    self.track = track
  }

  var body: some View {
    Group {
      if kind == .linear { bar } else { ring }
    }
    .accessibilityHidden(true)
  }

  private var ring: some View {
    let circle = Circle().inset(by: thickness / 2)
    return ZStack {
      if let track {
        circle.stroke(track, lineWidth: thickness)
      }
      circle.trim(from: 0, to: value ?? Self.indeterminateRingSweep)
        .stroke(color, lineWidth: thickness)
        // A circle's path starts at the trailing point, so a quarter turn back starts at the top.
        .rotationEffect(.degrees(-90))
        .rotationEffect(.degrees(value == nil && turning ? 360 : 0))
    }
    // SwiftUI mirrors drawing in a right-to-left subtree; the ring turns clockwise everywhere.
    .environment(\.layoutDirection, .leftToRight)
    .frame(width: size, height: size)
    .animation(
      value == nil
        ? .linear(duration: Self.cycleSeconds(reduceMotion: reduceMotion)).repeatForever(
          autoreverses: false) : nil,
      value: turning
    )
    .onAppear { turning = true }
  }

  /// The bar is drawn into one canvas, so the moving segment can't reach outside its box (an offset
  /// view's frame would grow its ancestors' accessibility frames). An indeterminate one is redrawn
  /// every frame from the clock.
  @ViewBuilder
  private var bar: some View {
    if value != nil {
      canvas(phase: 0)
    } else if let frozenAt {
      canvas(phase: Self.phase(at: frozenAt, reduceMotion: reduceMotion))
    } else {
      TimelineView(.animation) { timeline in
        canvas(phase: Self.phase(at: timeline.date, reduceMotion: reduceMotion))
      }
    }
  }

  private func canvas(phase: CGFloat) -> some View {
    Canvas { context, canvasSize in
      var context = context
      if layoutDirection == .rightToLeft {
        context.translateBy(x: canvasSize.width, y: 0)
        context.scaleBy(x: -1, y: 1)
      }
      let full = CGRect(origin: .zero, size: canvasSize)
      if let track { context.fill(Path(full), with: .color(track)) }
      context.fill(Path(fillRect(in: full, phase: phase)), with: .color(color))
    }
    .frame(maxWidth: .infinity)
    .frame(height: size)
  }

  /// What the fill covers in `bar`: `value` of the width from the start edge, or the segment at `phase`
  /// of its way across, clipped to the bar.
  private func fillRect(in bar: CGRect, phase: CGFloat) -> CGRect {
    if let value {
      return CGRect(x: 0, y: 0, width: bar.width * value, height: bar.height)
    }
    let length = bar.width * Self.segment
    let start = -length + phase * (bar.width + length)
    return CGRect(x: start, y: 0, width: length, height: bar.height).intersection(bar)
  }

  /// How far through its cycle an indeterminate indicator is at `date`, 0 to 1.
  static func phase(at date: Date, reduceMotion: Bool) -> CGFloat {
    let cycle = cycleSeconds(reduceMotion: reduceMotion)
    return CGFloat(
      date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle)
  }

  /// The time of one cycle of an indeterminate indicator: a second, and four times that with Reduce
  /// Motion on. The animation never stops.
  static func cycleSeconds(reduceMotion: Bool) -> Double { reduceMotion ? 4 : 1 }

  private static let indeterminateRingSweep: CGFloat = 0.25
  private static let segment: CGFloat = 0.25
}
