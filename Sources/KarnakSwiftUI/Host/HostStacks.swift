import Combine
import SwiftUI

// The seams the `KarnakNavigation` product's host stacks plug into. The core draws screens and knows nothing of who
// stacks them: a host stack (`.karnakDestinations()`, a tab's stack, the UIKit coordinator) registers here so native
// code and links find it, and tells the screens below it where they sit. `package`, so no app sees them.

/// A stack native code can open screens on: the `.karnakDestinations()` stack, a tab's stack, or a
/// `KarnakNavigationCoordinator` (all in the `KarnakNavigation` product).
@MainActor
package protocol KarnakEntryHost: AnyObject {
  /// Pushes `screenId` as the entry `entryId`; `receiver` hears how it ended, once.
  func push(
    _ screenId: String, params: [String: Any], entryId: String,
    receiver: @escaping (String, [String: Any]) -> Void)
  /// Removes `entryId` and the entries above it.
  func remove(_ entryId: String)
  /// Performs a navigation request, such as the screen a link opens.
  func perform(_ request: KarnakNavigation)
}

/// The stacks of a client that native code can open screens on, newest last, so native code opening a screen
/// (`KarnakSwiftClient.open(_:params:)`) or a link finds one to push on.
package final class HostStackRegistry: @unchecked Sendable {
  @MainActor private var hosts: [WeakHost] = []

  nonisolated init() {}

  private struct WeakHost {
    weak var host: (any KarnakEntryHost)?
  }

  /// Makes `host` the one native code opens screens on.
  @MainActor package func register(_ host: any KarnakEntryHost) {
    hosts.removeAll { $0.host == nil || $0.host === host }
    hosts.append(WeakHost(host: host))
  }

  /// The host that registered last and is still alive.
  @MainActor package var active: (any KarnakEntryHost)? {
    hosts.last { $0.host != nil }?.host
  }
}

/// What a host stack needs of the client that opens its screens (``SwiftUI/EnvironmentValues/karnakStackOpener``).
@MainActor
package protocol HostStackOpener: AnyObject {
  /// Logs a diagnostic where the host configured its logs.
  func report(_ message: String)
  /// The host dropped the entry `id`: its receiver hears `cancelled` unless it had its delivery.
  func entryRemoved(_ id: String)
  /// The host stacks screens of this opener are on.
  var stackRegistry: HostStackRegistry { get }
}

extension EnvironmentValues {
  /// The client of the enclosing `.karnakHost`, as a host stack sees it; nil outside one.
  package var karnakStackOpener: (any HostStackOpener)? { karnakOpener }
}

/// Where the screens below a view sit in a host stack: what a screen asks of the stack it is drawn in.
@MainActor
package protocol HostStackPosition {
  /// Performs a screen's navigation request on the stack: the screen's default navigation.
  func perform(_ request: KarnakNavigation)
  /// Whether an entry of the stack lies above this position now.
  var isCovered: Bool { get }
  /// Whether an entry of the stack lies above this position, as the stack changes.
  var coverage: AnyPublisher<Bool, Never> { get }
}
