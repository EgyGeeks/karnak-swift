import KarnakCore
import SwiftUI

/// A field of a node's box that a `motion` transition moves (the registry marks it `x-transition`), drawn by
/// ``NodeBox``. The background moves in ``MovingPaint`` and a progress value in its primitive; a text's or a track's
/// color and a border's paint don't move yet (#3717).
enum BoxMotionField: String, CaseIterable {
  case width = "layout.width"
  case height = "layout.height"
  case radius = "style.radius"
  case alpha = "style.alpha"

  /// The longest an alpha change runs under Reduce Motion (`docs/renderer-contract.md`, Motion).
  static let reducedAlphaSeconds = 0.15

  /// Whether the field is a size or a shape, which Reduce Motion applies at once; alpha only gets shorter.
  var isGeometry: Bool { self != .alpha }
}

extension ResolvedLayout {
  /// How `field` moves to a new value: the node's transition of it, nil for none. Under Reduce Motion a size or a
  /// shape snaps and alpha runs at most ``BoxMotionField/reducedAlphaSeconds``.
  func animation(of field: BoxMotionField, reduceMotion: Bool) -> Animation? {
    guard let transition = transition(of: field.rawValue) else { return nil }
    guard reduceMotion else { return transition.animation }
    if field.isGeometry { return nil }
    let seconds = min(Double(transition.durationMillis) / 1000, BoxMotionField.reducedAlphaSeconds)
    return easingAnimation(transition.easing, seconds: seconds)
  }
}

extension Transaction {
  /// Sets the animation of a changed box field: its own transition's, nil (at once) for none. A transaction that
  /// disables animations stays as it is.
  mutating func move(with animation: Animation?) {
    guard !disablesAnimations else { return }
    self.animation = animation
  }
}
