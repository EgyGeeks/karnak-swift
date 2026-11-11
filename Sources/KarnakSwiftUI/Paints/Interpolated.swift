import SwiftUI

/// A view drawn from a number SwiftUI interpolates while an animation runs, so what `content` draws (a canvas, say)
/// moves every frame without the node re-laying out.
struct Interpolated<Content: View>: View, @preconcurrency Animatable {
  /// The number at this frame.
  var value: CGFloat
  /// What it draws.
  let content: (CGFloat) -> Content

  var animatableData: CGFloat {
    get { value }
    set { value = newValue }
  }

  var body: some View { content(value) }
}
