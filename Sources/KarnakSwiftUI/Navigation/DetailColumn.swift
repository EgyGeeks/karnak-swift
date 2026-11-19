import KarnakCore
import SwiftUI

// The seam an app's split view plugs into (`KarnakSplitDetail`, in the `KarnakNavigation` product): a screen's
// detail pane is the screen's own (``DetailPanes``), and goes to the split view's detail column while one is set
// up above it. `package`, so no app sees it.

/// A column that draws the detail panes the screens below it open, in place of their own bounds.
@MainActor
package protocol DetailColumnHost: AnyObject {
  /// Shows `pane` in the column in place of any other.
  func present(_ pane: SplitPane)
  /// The pane `id` has closed.
  func dismiss(_ id: String)
}

/// The pane a screen sent to the detail column: its stack, how its screens get their environment, and how the user
/// closes it.
@MainActor
package struct SplitPane {
  let overlay: OverlayModel
  let environment: (Double) -> ScreenEnvironment
  /// Closes the pane, as the user does from the column.
  package let close: () -> Void

  package var id: String { overlay.id }
}

/// A detail column: the stack of `pane`, or `placeholder` while there is none. Each pane is a `NavigationStack` of its own
/// (a split view's column may hold one), its first entry the root under the split view's bar, the others pushed. Its
/// screens take the size class of the column, measured once for the column, so a new pane starts at the column's width.
package struct DetailColumnContent<Placeholder: View>: View {
  private let pane: SplitPane?
  private let placeholder: Placeholder
  @State private var width: CGFloat?

  /// Draws `pane`, or `placeholder`, filling the column.
  package init(pane: SplitPane?, placeholder: Placeholder) {
    self.pane = pane
    self.placeholder = placeholder
  }

  package var body: some View {
    Group {
      if let pane {
        PaneColumnStack(overlay: pane.overlay, environment: pane.environment(Double(width ?? 0)))
          // A new pane starts its own stack.
          .id(pane.id)
      } else {
        placeholder
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .measuringContainerWidth($width)
  }
}

private struct PaneColumnStack: View {
  @ObservedObject var overlay: OverlayModel
  let environment: ScreenEnvironment

  var body: some View {
    ContainedStackView(overlay: overlay, fillsSpace: true, showsRootBar: true)
      .task(id: PaneEnvironmentKey(environment, entries: overlay.entries.map(\.id))) {
        // The pane's screens take the size class of the column, not of the screen that opened it.
        for entry in overlay.entries { entry.model?.setEnvironment(environment) }
      }
  }
}

/// Sends the detail pane of a screen to the detail column while it is open, and takes it back when it closes or the
/// screen's view is gone for good.
struct SendsDetailToColumn: ViewModifier {
  @ObservedObject var effects: EffectModel
  let column: any DetailColumnHost
  let environment: (Double) -> ScreenEnvironment
  /// Ends with the view's identity and takes the pane back then: a screen covered in its column keeps it.
  @State private var lease = ColumnLease()

  func body(content: Content) -> some View {
    content.onChange(of: effects.detail?.id, initial: true) { old, new in
      if let old, old != new { column.dismiss(old) }
      lease.release()
      guard let detail = effects.detail else { return }
      let effects = effects
      column.present(
        SplitPane(
          overlay: detail, environment: environment, close: { effects.detailClosedByUser() }))
      lease.hold(detail.id, in: column)
    }
  }
}

/// The pane a screen holds in a detail column, taken back when the screen's view state is released.
private final class ColumnLease: @unchecked Sendable {
  private weak var column: (any DetailColumnHost)?
  private var id: String?

  @MainActor func hold(_ id: String, in column: any DetailColumnHost) {
    self.column = column
    self.id = id
  }

  @MainActor func release() {
    column = nil
    id = nil
  }

  deinit {
    guard let id else { return }
    Task { @MainActor [weak column] in column?.dismiss(id) }
  }
}

extension EnvironmentValues {
  /// The column the screens below send their detail panes to; nil to draw them in their own bounds.
  @Entry package var karnakDetailColumn: (any DetailColumnHost)?
}
