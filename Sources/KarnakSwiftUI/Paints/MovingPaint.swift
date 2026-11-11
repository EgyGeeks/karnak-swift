import KarnakCore
import SwiftUI

/// A paint that moves to a new target when the node's tree changes (`docs/renderer-contract.md`, Motion): the
/// background of a node with a `style.background` transition. The old paint stays drawn until the new move is set up,
/// so no frame shows the new paint early, and a reduced-motion setting snaps.
struct MovingPaint: View {
  let target: PaintTarget?
  let shape: NodeShape
  let transition: ResolvedTransition

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var move: Move

  init(target: PaintTarget?, shape: NodeShape, transition: ResolvedTransition) {
    self.target = target
    self.shape = shape
    self.transition = transition
    _move = State(initialValue: Move(from: nil, to: target, progress: 1))
  }

  /// The state of the animation: what it came from, where it goes and how far it is.
  private struct Move: Equatable {
    var from: PaintTarget?
    var to: PaintTarget?
    var progress: Double
  }

  var body: some View {
    PaintedFill(from: move.from, to: move.to, progress: move.progress, shape: shape)
      .onChange(of: target) { _, new in start(toward: new) }
  }

  private func start(toward new: PaintTarget?) {
    let origin = move.to
    guard !reduceMotion, transition.durationMillis > 0 else {
      move = Move(from: nil, to: new, progress: 1)
      return
    }
    var reset = Transaction()
    reset.disablesAnimations = true
    withTransaction(reset) { move = Move(from: origin, to: new, progress: 0) }
    // One hop later, so the reset frame is committed before the move begins.
    Task { @MainActor in
      withAnimation(transition.animation) { move.progress = 1 }
    }
  }
}

extension ResolvedTransition {
  /// The transition's timing curve, from the theme's cubic Bézier.
  var animation: Animation {
    .timingCurve(
      easing.x1, easing.y1, easing.x2, easing.y2, duration: Double(durationMillis) / 1000)
  }
}
