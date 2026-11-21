import ObjectiveC
import SwiftUI
import UIKit

/// Keeps the system's swipe back from the edge working on a stack entry whose navigation bar is hidden: UIKit's own
/// delegate of the stack's `interactivePopGestureRecognizer` refuses it while the bar is hidden. While the entry is
/// shown, the keeper puts a ``SwipeBackDelegate`` in place of UIKit's, and puts UIKit's back when the entry stops being
/// shown, so no other entry of the stack, and no stack of the app, changes. The swipe stays UIKit's: the same curve,
/// cancellable halfway, and a pop the stack reports as its back button's.
///
/// iOS 26's swipe from anywhere in the content (`interactiveContentPopGestureRecognizer`) is left as UIKit has it: its
/// delegate also keeps it from starting over horizontal scroll views and controls, which a bare delegate would not.
struct SwipeBackKeeper: UIViewControllerRepresentable {
  func makeUIViewController(context: Context) -> KeeperController { KeeperController() }

  func updateUIViewController(_ controller: KeeperController, context: Context) {}

  final class KeeperController: UIViewController {
    private var installed: (recognizer: UIGestureRecognizer, delegate: SwipeBackDelegate)?

    override func loadView() {
      view = UIView()
      view.isUserInteractionEnabled = false
      view.isAccessibilityElement = false
    }

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      install()
    }

    override func viewWillDisappear(_ animated: Bool) {
      super.viewWillDisappear(animated)
      restore()
    }

    private func install() {
      guard installed == nil, let stack = navigationController,
        let recognizer = stack.interactivePopGestureRecognizer
      else { return }
      let original = SwipeBackDelegate.uikitDelegate(of: recognizer)
      let delegate = SwipeBackDelegate(stack: stack, original: original)
      recognizer.delegate = delegate
      SwipeBackDelegate.retain(delegate, on: recognizer)
      installed = (recognizer, delegate)
    }

    private func restore() {
      guard let (recognizer, delegate) = installed else { return }
      installed = nil
      // Another keeper may have put its own in place since: it puts UIKit's back itself.
      guard recognizer.delegate === delegate else { return }
      recognizer.delegate = delegate.original
      SwipeBackDelegate.retain(nil, on: recognizer)
    }
  }
}

/// The delegate a ``SwipeBackKeeper`` puts in place of UIKit's: the swipe begins when the stack has an entry to go back
/// to and is not in a transition. It answers nothing else, so every other question gets UIKit's default answer: UIKit's
/// own delegate also refuses the touches themselves while the bar is hidden (measured on iOS 27.2: forwarding its other
/// answers kept the swipe dead), so it is not asked at all.
///
/// The recognizer holds its delegate weakly, so the delegate in place is also kept by the recognizer itself: a keeper
/// that goes away without being told (SwiftUI removing it while its entry is shown) leaves this delegate, which never
/// begins on the root, rather than none, which would let the swipe begin there and freeze the stack.
@MainActor
final class SwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
  private weak var stack: UINavigationController?
  /// UIKit's own delegate, put back when the entry stops being shown. Held strongly: it doesn't hold this one.
  let original: (any UIGestureRecognizerDelegate)?

  init(stack: UINavigationController, original: (any UIGestureRecognizerDelegate)?) {
    self.stack = stack
    self.original = original
  }

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard let stack else { return false }
    return stack.viewControllers.count > 1 && stack.transitionCoordinator == nil
  }

  /// UIKit's own delegate of `recognizer`, past the one another keeper may have put in place.
  static func uikitDelegate(
    of recognizer: UIGestureRecognizer
  ) -> (any UIGestureRecognizerDelegate)? {
    guard let kept = recognizer.delegate as? SwipeBackDelegate else { return recognizer.delegate }
    return kept.original
  }

  /// Keeps `delegate` alive for as long as `recognizer` holds it (or releases the one kept, for `nil`).
  static func retain(_ delegate: SwipeBackDelegate?, on recognizer: UIGestureRecognizer) {
    objc_setAssociatedObject(recognizer, &retainedKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
  }

  private nonisolated(unsafe) static var retainedKey: UInt8 = 0
}
