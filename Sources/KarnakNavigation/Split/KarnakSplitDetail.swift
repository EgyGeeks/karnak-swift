import KarnakCore
import KarnakSwiftUI
import Observation
import SwiftUI

/// Sends the `detail` panes of the Karnak screens in a `NavigationSplitView` to its detail column
/// (`docs/integration.md`, Navigation on iOS): opt-in, for an app that owns a split view; without it a screen draws
/// its pane in its own bounds. Hold it with `@State`, give its ``compactColumn`` to the split view, put
/// ``KarnakDetailColumn`` in the detail column and `.karnakSplitDetail(_:)` on the split view:
///
/// ```swift
/// @State private var split = KarnakSplitDetail()
///
/// NavigationSplitView(preferredCompactColumn: $split.compactColumn) {
///   KarnakScreen("inbox")
/// } detail: {
///   KarnakDetailColumn { Text("Pick a message") }
/// }
/// .karnakSplitDetail(split)
/// ```
///
/// A `detail` that a screen in the sidebar or content column opens shows in the detail column, in a
/// `NavigationStack` of the column's own, with the size class of the column. Collapsed (an iPhone, a narrow iPad
/// window) the split view shows the column when a pane opens, its back button closes the pane at the pane's first
/// screen, and the system back and swipe pop the screens above it. A screen in the detail column draws its own
/// `detail` in its own bounds.
@MainActor
@Observable
public final class KarnakSplitDetail {
  /// The column the split view shows when it is collapsed: pass `$split.compactColumn` to
  /// `NavigationSplitView(preferredCompactColumn:)`. A pane that opens shows `.detail`; the split view's back
  /// button setting it back closes the pane.
  public var compactColumn: NavigationSplitViewColumn {
    didSet { compactColumnChanged(from: oldValue) }
  }

  /// The pane the detail column draws; nil when no screen has one open.
  private(set) var pane: SplitPane?
  /// Whether the split view shows one column at a time, as `.karnakSplitDetail(_:)` reads it.
  @ObservationIgnored var collapsed = false
  /// The column to go back to when the pane closes.
  @ObservationIgnored private var columnBeforePane: NavigationSplitViewColumn?
  /// Set while the pane closes on its own, so the column it goes back to closes nothing.
  @ObservationIgnored private var dismissing = false

  /// - Parameter compactColumn: The column to show first when the split view is collapsed.
  public init(compactColumn: NavigationSplitViewColumn = .sidebar) {
    self.compactColumn = compactColumn
  }

  /// Shows `pane` in the detail column in place of any other.
  package func present(_ pane: SplitPane) {
    guard self.pane?.id != pane.id else { return }
    let showing = self.pane != nil
    self.pane = pane
    if !showing, compactColumn != .detail {
      columnBeforePane = compactColumn
      compactColumn = .detail
    }
  }

  /// The pane `id` has closed: the column goes back to its placeholder and, collapsed, to the column it came from.
  package func dismiss(_ id: String) {
    guard pane?.id == id else { return }
    pane = nil
    dismissing = true
    if compactColumn == .detail { compactColumn = columnBeforePane ?? .sidebar }
    dismissing = false
    columnBeforePane = nil
  }

  /// The split view's back button left the detail column while it was collapsed: the pane closes.
  private func compactColumnChanged(from old: NavigationSplitViewColumn) {
    guard !dismissing, old == .detail, compactColumn != .detail, collapsed, let pane else { return }
    columnBeforePane = nil
    pane.close()
  }
}

/// The detail column of a ``KarnakSplitDetail``: the pane a Karnak screen opened, or `placeholder` while none is
/// open. Put it in the `detail` column of the `NavigationSplitView` that `.karnakSplitDetail(_:)` is on. It draws the
/// pane's stack in a `NavigationStack` of its own: don't wrap it in another.
public struct KarnakDetailColumn<Placeholder: View>: View {
  @Environment(\.karnakDetailColumn) private var column
  private let placeholder: Placeholder

  /// The pane, or `placeholder` while there is none.
  public init(@ViewBuilder placeholder: () -> Placeholder) {
    self.placeholder = placeholder()
  }

  public var body: some View {
    DetailColumnContent(pane: (column as? KarnakSplitDetail)?.pane, placeholder: placeholder)
      // A screen in the column draws its own detail in its own bounds.
      .environment(\.karnakDetailColumn, nil)
  }
}

extension KarnakDetailColumn where Placeholder == EmptyView {
  /// The pane, and nothing while there is none.
  public init() {
    self.init { EmptyView() }
  }
}

extension View {
  /// Sends the `detail` panes of the Karnak screens in this `NavigationSplitView` to its ``KarnakDetailColumn``
  /// (``KarnakSplitDetail``). Put it on the split view.
  public func karnakSplitDetail(_ split: KarnakSplitDetail) -> some View {
    modifier(SplitDetailHost(split: split))
  }
}

private struct SplitDetailHost: ViewModifier {
  let split: KarnakSplitDetail
  @Environment(\.horizontalSizeClass) private var sizeClass

  func body(content: Content) -> some View {
    content
      .environment(\.karnakDetailColumn, split)
      // A split view in a compact width shows one column at a time.
      .onChange(of: sizeClass, initial: true) { split.collapsed = sizeClass == .compact }
  }
}

extension KarnakSplitDetail: DetailColumnHost {}
