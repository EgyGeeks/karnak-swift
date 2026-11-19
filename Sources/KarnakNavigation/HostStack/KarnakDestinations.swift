import Combine
import KarnakSwiftUI
import SwiftUI

extension View {
  /// Makes the `NavigationStack` this view is in the host stack of Karnak navigation
  /// (`docs/integration.md`, Navigation): a tap on an `open_screen` button pushes an
  /// ``KarnakScreen`` of the action's screen id and params, and `replace`, `reset`, `back` (also
  /// `to` and `root`) and `finish` act on the stack, with the system's swipe back. An
  /// `onOpenScreen` or `onNavigation` given to
  /// ``SwiftUI/View/karnakHost(_:onNavigate:onOpenUrl:onCustom:onTrack:onDismiss:onOpenScreen:onNavigation:onScreen:overlays:)``
  /// wins over it.
  ///
  /// ```swift
  /// NavigationStack {
  ///   HomeView().karnakDestinations()
  /// }
  /// .karnakHost(karnak)
  /// ```
  ///
  /// Apply it inside the stack, as `navigationDestination` needs: on its root view, and on any
  /// view you push yourself that shows screens. Every screen and section below it uses the
  /// stack, and the screens it pushes can push more. Pushes made while another is on its way in
  /// wait their turn. `modal` and `sheet` screens need nothing from the host: the SDK draws them
  /// with a `NavigationStack` of their own. An app that owns its `NavigationPath` gives
  /// `karnakHost` an `onNavigation` instead and shows a ``KarnakScreen`` in its own
  /// `navigationDestination`.
  public func karnakDestinations() -> some View {
    modifier(KarnakDestinations())
  }
}

private struct KarnakDestinations: ViewModifier {
  @Environment(\.karnakStack) private var position
  @Environment(\.karnakStackOpener) private var opener
  @Environment(\.karnakHostCallbacks) private var callbacks
  @Environment(\.dismiss) private var dismiss
  @StateObject private var ownStack = KarnakHostStack()

  /// The level of the stack this view is in, when an outer `.karnakDestinations()` or tab drives it.
  private var inherited: KarnakStackLevel? { position as? KarnakStackLevel }

  func body(content: Content) -> some View {
    let level = inherited ?? KarnakStackLevel(stack: ownStack, depth: 0)
    // The stack keeps the latest hooks, like the screens do. A result builder allows a
    // declaration here, not a bare call.
    // swiftlint:disable:next redundant_discardable_let
    let _ = configure(level.stack)
    KarnakStackLevelView(level: level, content: content)
      .onAppear { if inherited == nil { opener?.stackRegistry.register(ownStack) } }
  }

  private func configure(_ stack: KarnakHostStack) {
    guard inherited == nil else { return }
    let hooks = callbacks
    let pop = dismiss
    stack.entryRemoved = { [weak opener] in opener?.entryRemoved($0) }
    stack.report = { [weak opener] in opener?.report($0) }
    stack.leave = {
      if let onDismiss = hooks.onDismiss { onDismiss() } else { pop() }
    }
  }
}

/// One level of the chain: the content, and the entry at its depth pushed above it.
private struct KarnakStackLevelView<Content: View>: View {
  let level: KarnakStackLevel
  let content: Content
  @ObservedObject private var stack: KarnakHostStack

  init(level: KarnakStackLevel, content: Content) {
    self.level = level
    self.content = content
    stack = level.stack
  }

  var body: some View {
    content
      .environment(\.karnakStack, level)
      .environment(\.karnakInNavigationStack, true)
      .environment(\.karnakPushedAbove, stack.entries.count > level.depth)
      .navigationDestination(
        isPresented: Binding(
          get: { stack.entries.count > level.depth },
          set: { if !$0 { stack.popped(toDepth: level.depth) } })
      ) {
        // Kept after a pop, so the screen doesn't vanish before the animation ends.
        if let entry = stack.entry(at: level.depth) {
          KarnakEntryView(entry: entry)
            .onAppear { stack.appeared(entry.id) }
            .karnakDestinations()
            .environment(\.karnakStack, KarnakStackLevel(stack: stack, depth: level.depth + 1))
            .id(entry.id)
        }
      }
  }
}

/// Where a view sits in the host stack: the entries it shares with the views above and below it,
/// and how many entries lie below it. The screens below it read it as their ``HostStackPosition``.
struct KarnakStackLevel: HostStackPosition {
  let stack: KarnakHostStack
  let depth: Int

  func perform(_ request: KarnakNavigation) {
    stack.perform(request)
  }

  var isCovered: Bool {
    stack.isCovered(at: depth)
  }

  var coverage: AnyPublisher<Bool, Never> {
    stack.$entries.map { [depth] in $0.count > depth }.removeDuplicates().eraseToAnyPublisher()
  }
}

/// What a host-stack entry shows: the SDK's screen, or the app's native screen of a route step.
private struct KarnakEntryView: View {
  let entry: KarnakStackEntry

  var body: some View {
    if let screenId = entry.screenId {
      KarnakScreen(
        screenId: screenId, params: entry.params, entryId: entry.id, receiver: entry.receiver)
    } else if let route = entry.route {
      KarnakRouteEntryView(route: route)
    }
  }
}
