import KarnakCore

/// What a view tells the open screen: each sends to the session, and nothing happens without one.
extension ScreenModel {
  /// Sends the activation of `handle` to the open screen; nothing happens without one.
  func click(_ handle: ActionHandle) {
    session?.click(handle)
  }

  /// Sends the appearance of `handle`, a node at least half visible, to the open screen; nothing
  /// happens without one.
  func appear(_ handle: ActionHandle) {
    session?.appear(handle)
  }

  /// Sends the near report of `handle`, a node near the viewport, to the open screen; nothing happens without one.
  func near(_ handle: ActionHandle) {
    session?.near(handle)
  }

  /// Sends a node's settled event, such as a carousel's `pageChange`, to the open screen; nothing happens without one.
  func event(_ handle: ActionHandle, payload: KarnakValue, byUser: Bool, generation: Int64) {
    session?.event(handle, payload: payload, byUser: byUser, generation: generation)
  }

  /// Tells the open screen the floating view `key` ended for `reason`; nothing happens without one.
  func floatingDismissed(_ key: String, _ reason: FloatingDismissReason) {
    session?.floatingDismissed(key, reason)
  }

  /// Sends an input's event to the open screen; nothing happens without one.
  func input(_ event: InputEvent) {
    session?.input(event)
  }
}
