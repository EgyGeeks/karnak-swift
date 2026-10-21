import Foundation
import KarnakCore
import SwiftUI

/// What native code uses to end a native route step of a flow (`docs/integration.md`, Flows on
/// iOS): the screen the app draws for a `route` step reads it from `@Environment(\.karnakFlow)` and
/// calls ``finish(_:result:)`` when the user is done.
///
/// ```swift
/// struct WalletPay: View {
///   @Environment(\.karnakFlow) private var flow
///   var body: some View {
///     Button("Pay") { flow?.finish("paid", result: ["orderId": "o-1"]) }
///   }
/// }
/// ```
///
/// With a route manifest, an outcome the route doesn't declare and a result that doesn't fit it
/// are ignored and logged. Calling ``finish(_:result:)`` twice, or after the step has gone, does
/// nothing. Leaving the screen without finishing (the swipe back) is the step's `back`.
public final class KarnakFlowHandle: Equatable, @unchecked Sendable {
  private let handle: EntryHandle

  /// The id of the entry this handle ends, which the host reports to
  /// ``KarnakSwiftNavigator/entryRemoved(_:)`` when its router drops it.
  public var entryId: String { handle.entryId }

  init(_ handle: EntryHandle) {
    self.handle = handle
  }

  /// Ends the step with `outcome` and `result` (JSON values, at most 4 KiB encoded). It never
  /// throws: an outcome the route doesn't declare, or a result that doesn't fit, is ignored and
  /// logged.
  public func finish(_ outcome: String, result: [String: Any] = [:]) {
    handle.finish(outcome: outcome, result: result)
  }

  public static func == (lhs: KarnakFlowHandle, rhs: KarnakFlowHandle) -> Bool {
    lhs === rhs
  }
}

extension EnvironmentValues {
  /// The handle that ends the native route step this view is the screen of, or nil elsewhere
  /// (``KarnakFlowHandle``).
  @Entry public var karnakFlow: KarnakFlowHandle?
}
