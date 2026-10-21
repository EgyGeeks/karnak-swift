import KarnakCore

/// The transient states a button's tracking reports as active.
func activeInteractions(pressed: Bool, hovered: Bool, focused: Bool) -> Set<Interaction> {
  var active = Set<Interaction>()
  if pressed { active.insert(.pressed) }
  if hovered { active.insert(.hovered) }
  if focused { active.insert(.focused) }
  return active
}

extension ResolvedButton {
  /// The button to draw while `active` states are on: `styleFor(active)` while the button is
  /// `interactive`, else the button itself, which never restyles
  /// (`docs/renderer-contract.md`, Style resolution and interaction states).
  func styled(for active: Set<Interaction>) -> ResolvedButton {
    guard interactive, !active.isEmpty else { return self }
    return styleFor(interaction: active) as? ResolvedButton ?? self
  }
}
