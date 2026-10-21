import SwiftUI
import UIKit

extension UIView {
  /// The part of this view's window that is on screen for it, in window coordinates: the window's
  /// bounds clipped by every ancestor that scrolls or clips its content. Empty without a window.
  func visibleRectInWindow() -> CGRect {
    guard let window else { return .zero }
    var visible = window.bounds
    var ancestor = superview
    while let view = ancestor, !visible.isEmpty {
      // The view's frame in its superview, not its bounds: a scrolled view's bounds are offset.
      if let parent = view.superview, view is UIScrollView || view.clipsToBounds {
        visible = visible.intersection(parent.convert(view.frame, to: nil))
      }
      ancestor = view.superview
    }
    return visible
  }
}

/// Reports, through `onChange`, which part of the window a screen can show: the window's bounds
/// clipped by the scroll views and clipping containers around it, such as a host's `ScrollView`
/// around a section or a sheet's content. It is re-read when the view moves, lays out, or an
/// enclosing scroll view scrolls. A node counts as visible only inside this area.
struct ViewportProbe: UIViewRepresentable {
  /// Receives the visible area in window (global) coordinates whenever it changes.
  let onChange: (CGRect) -> Void

  func makeUIView(context: Context) -> ProbeView {
    let view = ProbeView()
    view.isUserInteractionEnabled = false
    view.isAccessibilityElement = false
    return view
  }

  func updateUIView(_ view: ProbeView, context: Context) {
    view.onChange = onChange
    view.refresh()
  }
}

/// The view behind ``ViewportProbe``.
final class ProbeView: UIView {
  var onChange: ((CGRect) -> Void)?
  private var lastReported: CGRect?
  private var scrolls: [NSKeyValueObservation] = []

  override func didMoveToWindow() {
    super.didMoveToWindow()
    observeEnclosingScrollViews()
    refresh()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    refresh()
  }

  /// Reads the visible area again and reports it when it changed.
  func refresh() {
    let visible = visibleRectInWindow()
    guard visible != lastReported else { return }
    lastReported = visible
    onChange?(visible)
  }

  private func observeEnclosingScrollViews() {
    scrolls = []
    var ancestor = superview
    while let view = ancestor {
      if let scroll = view as? UIScrollView {
        scrolls.append(scroll.observe(\.contentOffset) { [weak self] _, _ in self?.refresh() })
      }
      ancestor = view.superview
    }
  }
}
