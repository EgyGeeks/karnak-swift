import SwiftUI

/// A node's ``NodeFrameLayout`` whose width and height each move on their own field's transition
/// (`docs/renderer-contract.md`, Motion). Each axis is its own animatable modifier with its own transaction, so a size
/// that changes without a transition applies at once while the other one moves.
struct MovingFrame: ViewModifier {
  let frame: NodeFrameLayout
  let widthAnimation: Animation?
  let heightAnimation: Animation?

  func body(content: Content) -> some View {
    content
      .modifier(MovingWidth(frame: frame, heightAnimation: heightAnimation))
      .transaction(value: frame.width.mode) { $0.move(with: widthAnimation) }
  }
}

/// The frame's width, interpolated by the transaction its change came in; it hands the height on as it is.
private struct MovingWidth: ViewModifier, @preconcurrency Animatable {
  var frame: NodeFrameLayout
  let heightAnimation: Animation?

  var animatableData: CGFloat {
    get { frame.width.animatableSize }
    set { frame.width.animatableSize = newValue }
  }

  func body(content: Content) -> some View {
    content
      .modifier(MovingHeight(frame: frame))
      // The width's transaction reaches inside: a height that didn't change with it keeps its own (none, at once).
      .transaction(value: frame.height.mode) { $0.move(with: heightAnimation) }
  }
}

/// The frame's height, interpolated by the transaction its change came in, around the content.
private struct MovingHeight: ViewModifier, @preconcurrency Animatable {
  var frame: NodeFrameLayout

  var animatableData: CGFloat {
    get { frame.height.animatableSize }
    set { frame.height.animatableSize = newValue }
  }

  func body(content: Content) -> some View {
    frame { content }
  }
}
