import Foundation

/// How a screen opened by ``KarnakSwiftClient/open(_:params:)`` ended: the outcome of its `finish`
/// action and its result, or `cancelled` with an empty result when it closed without finishing.
public typealias KarnakOutcome = (outcome: String, result: [String: Any])

extension KarnakSwiftClient {
  /// Opens screen `screenId` on the host stack and returns how it ended, the iOS form of the
  /// activity-result pattern (`docs/integration.md`, Navigation):
  ///
  /// ```swift
  /// let (outcome, result) = await karnak.open("address_picker", params: ["city": "cairo"])
  /// if outcome == "picked" { use(result["addressId"] as? String) }
  /// ```
  ///
  /// The screen is pushed on the stack of the `.karnakDestinations()` that appeared last, with the
  /// swipe back of any pushed screen; going back delivers `cancelled`. Cancelling the task takes
  /// the screen off the stack. With no `.karnakDestinations()` on screen the call returns
  /// `cancelled` at once and logs why.
  @MainActor
  public func open(_ screenId: String, params: [String: Any] = [:]) async -> KarnakOutcome {
    guard let active = stacks.active else {
      report(
        "Karnak: open('\(screenId)') returned cancelled: no .karnakDestinations() is on screen.")
      return KarnakOutcome(outcome: "cancelled", result: [:])
    }
    let entryId = "karnak-native-\(UUID().uuidString)"
    // The host is main-actor state; this call and the cancellation hop both stay on the main actor.
    nonisolated(unsafe) let stack = active
    let ended = await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Ended, Never>) in
        stack.push(screenId, params: params, entryId: entryId) { outcome, result in
          continuation.resume(
            returning: Ended(value: KarnakOutcome(outcome: outcome, result: result)))
        }
      }
    } onCancel: {
      Task { @MainActor in stack.remove(entryId) }
    }
    return ended.value
  }
}

/// The outcome in transit from the screen's callback (main thread) to the caller's task.
private struct Ended: @unchecked Sendable {
  let value: KarnakOutcome
}
