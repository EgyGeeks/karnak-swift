import SwiftUI

extension View {
  /// Makes the `NavigationStack` this view is in the host stack of Karnak navigation
  /// (`docs/integration.md`, Navigation): a tap on an `open_screen` button pushes an
  /// ``KarnakScreen`` of the action's screen id and params, and `replace`, `reset`, `back` (also
  /// `to` and `root`) and `finish` act on the stack, with the system's swipe back. An
  /// `onOpenScreen` or `onNavigation` given to
  /// ``SwiftUI/View/karnakHost(_:onNavigate:onOpenUrl:onCustom:onTrack:onDismiss:onOpenScreen:onNavigation:overlays:)``
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
  @Environment(\.karnakStack) private var inherited
  @Environment(\.karnakOpener) private var opener
  @Environment(\.karnakHostCallbacks) private var callbacks
  @Environment(\.dismiss) private var dismiss
  @StateObject private var ownStack = KarnakHostStack()

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
/// and how many entries lie below it.
struct KarnakStackLevel {
  let stack: KarnakHostStack
  let depth: Int
}

/// The stacks of a client that native code can open screens on, newest last, so native code opening a
/// screen (``KarnakSwiftClient/open(_:params:)``) finds one to push on.
final class HostStackRegistry: @unchecked Sendable {
  @MainActor private var hosts: [WeakHost] = []

  nonisolated init() {}

  private struct WeakHost {
    weak var host: (any KarnakEntryHost)?
  }

  /// Makes `host` the one native code opens screens on.
  @MainActor func register(_ host: any KarnakEntryHost) {
    hosts.removeAll { $0.host == nil || $0.host === host }
    hosts.append(WeakHost(host: host))
  }

  /// The host that registered last and is still alive.
  @MainActor var active: (any KarnakEntryHost)? {
    hosts.last { $0.host != nil }?.host
  }
}

/// What a host-stack entry shows: the SDK's screen, or the app's native screen of a route step.
private struct KarnakEntryView: View {
  let entry: KarnakStackEntry

  var body: some View {
    if let screenId = entry.screenId {
      KarnakScreen(entry: entry, screenId: screenId)
    } else if let route = entry.route {
      KarnakRouteEntryView(route: route)
    }
  }
}
