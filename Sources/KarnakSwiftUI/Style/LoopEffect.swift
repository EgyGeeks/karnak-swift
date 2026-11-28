import KarnakCore
import SwiftUI

/// A node's loop effect (`layout.loopEffect`; `docs/renderer-contract.md`, Loop effects): a shimmer's band drawn over
/// the node in its shape, or a pulse's opacity on the node. Drawn only: the box, the siblings and the semantics never
/// move. Only the band's `Canvas` or the opacity sits inside the `TimelineView(.animation(paused:))`, so a frame
/// redraws that and never runs the node's body or lays it out. The timeline runs only while the node is on screen, the
/// scene is active and Reduce Motion is off; otherwise the node draws plain. Every loop reads the system clock, so boxes
/// of one duration move in step.
struct LoopEffectDrawing: ViewModifier {
  let effect: ResolvedLoopEffect
  let shape: NodeShape
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.layoutDirection) private var layoutDirection
  @State private var onScreen = false

  func body(content: Content) -> some View {
    looked(content)
      .onAppear { onScreen = true }
      .onDisappear { onScreen = false }
  }

  @ViewBuilder
  private func looked(_ content: Content) -> some View {
    let running = LoopFrame.runs(
      onScreen: onScreen, active: scenePhase == .active, reduceMotion: reduceMotion)
    if let shimmer = effect as? ResolvedLoopEffectShimmer {
      content.overlay {
        if running {
          TimelineView(.animation) { timeline in
            Canvas { context, size in
              band(
                shimmer, at: LoopFrame(effect: shimmer, date: timeline.date), into: &context,
                size: size)
            }
          }
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        }
      }
    } else if let pulse = effect as? ResolvedLoopEffectPulse {
      TimelineView(.animation(paused: !running)) { timeline in
        content.opacity(
          running ? LoopFrame(effect: pulse, date: timeline.date).opacity(of: pulse) : 1)
      }
    } else {
      content
    }
  }

  private func band(
    _ shimmer: ResolvedLoopEffectShimmer, at frame: LoopFrame, into context: inout GraphicsContext,
    size: CGSize
  ) {
    guard size.width > 0, size.height > 0 else { return }
    let start = frame.bandStart(
      of: shimmer, width: size.width, rightToLeft: layoutDirection == .rightToLeft)
    let peak = resolvedColor(shimmer.color).opacity(Double(shimmer.alpha))
    let gradient = Gradient(stops: [
      .init(color: peak.opacity(0), location: 0),
      .init(color: peak, location: 0.5),
      .init(color: peak.opacity(0), location: 1),
    ])
    context.fill(
      shape.path(in: CGRect(origin: .zero, size: size)),
      with: .linearGradient(
        gradient, startPoint: CGPoint(x: start, y: 0),
        endPoint: CGPoint(x: start + size.width, y: 0)))
  }
}

/// One frame of a loop: its phase at a date, and what the shimmer's band and the pulse's opacity are at that phase.
/// The engine's `phaseAt`, `bandOffset` and `alphaAt` decide; this only places them in points.
struct LoopFrame {
  /// The loop's phase, 0 up to 1.
  let phase: Float

  init(effect: ResolvedLoopEffect, date: Date) {
    phase = effect.phaseAt(
      elapsedMillis: Int64((date.timeIntervalSinceReferenceDate * 1000).rounded(.down)))
  }

  init(phase: Float) {
    self.phase = phase
  }

  /// Whether a loop runs: on screen, in an active scene and with Reduce Motion off.
  static func runs(onScreen: Bool, active: Bool, reduceMotion: Bool) -> Bool {
    onScreen && active && !reduceMotion
  }

  /// The x of the band's left edge in a box `width` wide: a box's width before the start edge at phase 0, one past the
  /// end edge at phase 1, the start edge being the right one in right-to-left.
  func bandStart(
    of shimmer: ResolvedLoopEffectShimmer, width: CGFloat, rightToLeft: Bool
  ) -> CGFloat {
    let offset = CGFloat(shimmer.bandOffset(phase: phase)) * width
    return rightToLeft ? -offset : offset
  }

  /// The pulse's opacity, multiplied into the node's own.
  func opacity(of pulse: ResolvedLoopEffectPulse) -> Double {
    Double(pulse.alphaAt(phase: phase))
  }
}

extension View {
  /// Draws `effect` on this node in `shape`; the node as it is when it has none.
  @ViewBuilder
  func loopEffect(_ effect: ResolvedLoopEffect?, shape: NodeShape) -> some View {
    if let effect {
      modifier(LoopEffectDrawing(effect: effect, shape: shape))
    } else {
      self
    }
  }
}
