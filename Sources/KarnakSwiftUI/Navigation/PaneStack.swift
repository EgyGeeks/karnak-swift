import SwiftUI

/// The stack inside a detail pane: its top entry's screen, under a bar with a back button when
/// there is a way back (an entry below, or `onRootBack`). It is not a `NavigationStack`: the pane
/// is drawn inside its screen, which an app pushes on a `NavigationStack` of its own, and SwiftUI
/// gives a stack nested in another's destination the outer stack's path, so opening the pane
/// popped the app to its root. The entries below the top one stay in the view tree, hidden, and
/// keep their scroll position; nothing in them counts as visible (`actions.appear` waits until
/// the entry is on top again).
///
/// A native route drawn in the pane is therefore in no stack of the pane's: its
/// `navigationTitle`, `toolbar` and `NavigationLink`s reach the app's stack around the screen,
/// when there is one.
struct PaneStackView: View {
  @ObservedObject var overlay: OverlayModel
  /// Closes the pane from its first entry (a pane that covers its screen); nil for a pane beside
  /// its screen, whose first entry has no way back.
  var onRootBack: (() -> Void)?

  var body: some View {
    VStack(spacing: 0) {
      if let back { PaneBar(onBack: back) }
      ZStack(alignment: .top) {
        ForEach(overlay.entries) { entry in
          let isTop = entry.id == overlay.entries.last?.id
          ContainedEntryView(entry: entry, fillsSpace: true, onHeight: { _ in })
            .opacity(isTop ? 1 : 0)
            .allowsHitTesting(isTop)
            // A container of its own takes `accessibilityHidden(false)`, as the screen does in ``DetailPanes``.
            .accessibilityElement(children: .contain)
            .accessibilityHidden(!isTop)
            .environment(\.karnakCovered, !isTop)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    // VoiceOver's escape gesture leaves as the back button does.
    .accessibilityAction(.escape) { back?() }
  }

  /// What the back button does: pops the top entry, or at the first entry closes the pane.
  private var back: (() -> Void)? {
    let count = overlay.entries.count
    if count > 1 { return { overlay.popped(toCount: count - 1) } }
    return onRootBack
  }
}

/// The pane's bar: a back button at the leading edge and nothing else (a pane has no title). It
/// keeps the system look, as the pane's surface and divider do: the system's chevron, which
/// mirrors in a right-to-left layout and grows with Dynamic Type, in the app's tint, on a touch
/// target of at least 44 points. Its name for VoiceOver is "Back" from the app's string catalog,
/// as ``KarnakLoadingView``'s "Loading" is.
private struct PaneBar: View {
  let onBack: () -> Void

  var body: some View {
    HStack {
      Button(action: onBack) {
        Image(systemName: "chevron.backward")
          .font(.body.weight(.semibold))
          .frame(minWidth: 44, minHeight: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel(Text("Back"))
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 4)
  }
}
