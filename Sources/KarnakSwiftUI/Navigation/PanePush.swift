import KarnakCore
import SwiftUI
import UIKit

extension EnvironmentValues {
  /// Whether the views below are in a `NavigationStack` that takes `navigationDestination`: true under
  /// `.karnakDestinations()`, the SDK's own stacks and a `KarnakPathScreen`. A covering detail pane is pushed on such a
  /// stack, as a screen is, and draws over its screen elsewhere.
  @Entry package var karnakInNavigationStack = false
  /// Whether the stack the views below are in shows an entry pushed above their screen: a covering detail pane then
  /// stops being pushed, so the entry is the only one presented from that level, and is pushed again when the screen
  /// is back on top.
  @Entry package var karnakPushedAbove = false
}

/// The screens of a detail pane pushed on the stack its screen is in: the pane's first entry pushed over the screen,
/// and each entry above it pushed over the one below, so the push, the pop, the back button and the swipe from the
/// edge are the system's (`docs/renderer-contract.md`, Detail panes). A pop, by the back button or the swipe, is
/// reported to the engine as the pane's own back button reports it. A level keeps drawing the entry it showed while it
/// is popped, so the screen doesn't vanish before the animation ends.
struct PanePushLevel: View {
  @ObservedObject var overlay: OverlayModel
  /// How many of the pane's entries lie below this one.
  let depth: Int
  /// The environment of the pane's screens: the size class of the stack they are pushed on.
  let environment: ScreenEnvironment
  /// Hears the width of the stack, which the covered screen can't measure: it is out of the window.
  var onWidth: (CGFloat) -> Void = { _ in }
  @State private var shown: OverlayEntry?

  var body: some View {
    let current = overlay.entries.indices.contains(depth) ? overlay.entries[depth] : nil
    Group {
      if let entry = current ?? shown {
        ContainedEntryView(entry: entry, fillsSpace: true, onHeight: { _ in })
          .id(entry.id)
          .task(id: PaneEnvironmentKey(environment, entries: [entry.id])) {
            entry.model?.setEnvironment(environment)
          }
      }
    }
    .onChange(of: current?.id, initial: true) { if let current { shown = current } }
    .onGeometryChange(for: CGFloat.self, of: \.size.width) { onWidth($0) }
    .environment(\.karnakInNavigationStack, true)
    .environment(\.karnakPushedAbove, false)
    .navigationDestination(
      isPresented: Binding(
        get: { overlay.entries.count > depth + 1 },
        set: { if !$0 { overlay.popped(toCount: depth + 1) } })
    ) {
      PanePushLevel(
        overlay: overlay, depth: depth + 1, environment: environment, onWidth: onWidth)
    }
  }
}

/// The pane's screens take the size class of the pane, not of the screen that opened it: what a change of it is.
struct PaneEnvironmentKey: Equatable {
  let sizeClass: String
  let reach: String
  let entries: [String]

  init(_ environment: ScreenEnvironment, entries: [String]) {
    sizeClass = environment.sizeClass.wire
    reach = environment.sizeReach.reachableHeader
    self.entries = entries
  }
}

/// Tells whether the view it sits in is shown by a navigation controller, which a `NavigationStack` is backed by. The
/// environment alone can't say it: a sheet an app presents from a screen of a stack inherits the stack's environment
/// but is in no stack, and a `navigationDestination` there would push nothing.
struct NavigationControllerProbe: UIViewControllerRepresentable {
  let report: (Bool) -> Void

  func makeUIViewController(context: Context) -> ProbeController {
    let controller = ProbeController()
    controller.report = report
    return controller
  }

  func updateUIViewController(_ controller: ProbeController, context: Context) {
    controller.report = report
  }

  final class ProbeController: UIViewController {
    var report: (Bool) -> Void = { _ in }
    private var reported: Bool?

    override func loadView() {
      view = UIView()
      view.isUserInteractionEnabled = false
      view.isAccessibilityElement = false
    }

    override func didMove(toParent parent: UIViewController?) {
      super.didMove(toParent: parent)
      check()
    }

    override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
      check()
    }

    private func check() {
      let found = navigationController != nil
      guard found != reported else { return }
      reported = found
      // Not during SwiftUI's update of the view that holds the probe.
      DispatchQueue.main.async { [report] in report(found) }
    }
  }
}
