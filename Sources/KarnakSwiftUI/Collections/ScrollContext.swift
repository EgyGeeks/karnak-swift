import SwiftUI
import UIKit

/// The scroll view around a screen, as the collection behavior needs it: whether the user is
/// scrolling, where its viewport is, and a way to move it. The host's own `ScrollView` is the
/// one; a screen outside any scroll view has nothing to hold or anchor.
@MainActor
protocol ScrollContext: AnyObject {
  /// Whether the user's finger is down on the scroll view, dragging it, or it is still decelerating.
  var isGestureActive: Bool { get }
  /// The part of the window the screen shows, in window coordinates (the same ones the rows'
  /// frames are in).
  var visibleRect: CGRect { get }
  /// Moves the content by `delta` points along the scroll axis, without animation, on the next
  /// turn of the run loop.
  func shift(by delta: CGFloat)
}

/// Finds the scroll view around the screen and reports it to `onChange`, as ``ViewportProbe``
/// finds its viewport: a zero-size view in the screen's background.
struct ScrollProbe: UIViewRepresentable {
  /// Receives the context once its view is in a window; nil when it leaves.
  let onChange: (ScrollContext?) -> Void

  func makeUIView(context: Context) -> ScrollProbeView {
    let view = ScrollProbeView()
    view.isUserInteractionEnabled = false
    view.isAccessibilityElement = false
    return view
  }

  func updateUIView(_ view: ScrollProbeView, context: Context) {
    view.onChange = onChange
    view.report()
  }
}

/// The view behind ``ScrollProbe``; it is the ``ScrollContext``.
final class ScrollProbeView: UIView, ScrollContext {
  var onChange: ((ScrollContext?) -> Void)?
  private var reported = false

  private var scrollView: UIScrollView? {
    var ancestor = superview
    while let view = ancestor {
      if let scroll = view as? UIScrollView { return scroll }
      ancestor = view.superview
    }
    return nil
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    report()
  }

  /// Reports this view while it can find a scroll view, and nil when it cannot.
  func report() {
    let found = window != nil && scrollView != nil
    guard found != reported else { return }
    reported = found
    onChange?(found ? self : nil)
  }

  var isGestureActive: Bool {
    guard let scroll = scrollView else { return false }
    return scroll.isTracking || scroll.isDragging || scroll.isDecelerating
  }

  var visibleRect: CGRect { visibleRectInWindow() }

  func shift(by delta: CGFloat) {
    // The move comes from a layout callback of SwiftUI: changing the offset in it changes
    // SwiftUI's own scroll state during a view update, so it waits for the next turn.
    DispatchQueue.main.async { [weak self] in
      guard let scroll = self?.scrollView else { return }
      var offset = scroll.contentOffset
      offset.y = max(offset.y + delta, -scroll.adjustedContentInset.top)
      scroll.setContentOffset(offset, animated: false)
    }
  }
}
