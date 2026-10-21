import KarnakCore
import SwiftUI

/// `button`: a SwiftUI `Button` whose custom style draws the node (`docs/renderer-contract.md`,
/// `button`, and Style resolution and interaction states).
///
/// - **Interaction states.** `configuration.isPressed`, `.onHover` and `@FocusState` are tracked
///   for every button. While the node is `interactive`, the button draws
///   `styleFor(active states)` exactly as it draws any node, box and face; otherwise it draws
///   the node itself. The states outlive a tree in which the button isn't interactive, so a
///   button that keeps focus through loading draws focused again when it's enabled.
/// - **Activation.** Activating an enabled button sends its handle. A loading button has no
///   `onClick`: it stays enabled, so it keeps keyboard focus, but activating it does nothing,
///   and VoiceOver reads its state description. A disabled button is `.disabled`, so it is
///   not activatable and reads as dimmed. Neither passes a tap on to a clickable parent.
/// - **Layout.** A row, column or flow parent allocates for the tree's node, as for any child
///   (`NodeChildren`); the drawn box follows the drawn node within that allocation (#273).
///   The hit area is the drawn node's touch target.
struct ButtonView: View {
  /// The button as the tree resolved it.
  let button: ResolvedButton
  /// What the button's parent decides about its box.
  let placement: ChildPlacement
  @State private var pressed = false
  @State private var hovered: Bool
  @FocusState private var focused: Bool
  @Environment(\.karnakActions) private var actions

  /// - Parameters:
  ///   - button: The button as the tree resolved it.
  ///   - placement: What the button's parent decides about its box.
  ///   - hovered: Whether a pointer is over the button when it appears; tests set it, since
  ///     they can't hover.
  init(button: ResolvedButton, placement: ChildPlacement, hovered: Bool = false) {
    self.button = button
    self.placement = placement
    _hovered = State(initialValue: hovered)
  }

  var body: some View {
    let drawn = button.styled(
      for: activeInteractions(pressed: pressed, hovered: hovered, focused: focused))
    let target = touchTarget(of: drawn)
    Button {
      if let handle = button.onClick { actions.click(handle) }
    } label: {
      ButtonFace(button: drawn)
    }
    .buttonStyle(NodeButtonStyle(button: drawn, placement: placement, touchTarget: target))
    .focused($focused)
    .onHover { hovered = $0 }
    .onPreferenceChange(ButtonPressedKey.self) { pressed = $0 }
    .modifier(NodeSemantics(semantics: button.semantics, isContainer: false))
    // Outside `.disabled`, so it still takes the taps the disabled button ignores.
    .modifier(TapBarrier(isActive: button.semantics.disabled, touchTarget: target))
    .modifier(ReservedTouchTarget(minimum: placement.reservesTouchTarget ? target : 0))
    .modifier(NodeAppear(handle: button.onAppear))
  }
}

/// Draws a button's node: its face in its box, with the touch target as the hit area. It
/// reports `isPressed` to ``ButtonView``, which selects the node to draw.
private struct NodeButtonStyle: ButtonStyle {
  let button: ResolvedButton
  let placement: ChildPlacement
  let touchTarget: CGFloat

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .nodeBox(button, placement: placement, contentPosition: .center)
      .contentShape(TouchTargetShape(minimum: touchTarget))
      .preference(key: ButtonPressedKey.self, value: configuration.isPressed)
  }
}

/// Whether the button's style is pressed.
private struct ButtonPressedKey: PreferenceKey {
  static let defaultValue = false

  static func reduce(value: inout Bool, nextValue: () -> Bool) {
    value = value || nextValue()
  }
}

/// Takes taps on a disabled button's touch target and does nothing with them, as a disabled
/// `UIButton` does, so they don't reach a clickable parent.
private struct TapBarrier: ViewModifier {
  let isActive: Bool
  let touchTarget: CGFloat

  func body(content: Content) -> some View {
    if isActive {
      content.contentShape(TouchTargetShape(minimum: touchTarget)).onTapGesture {}
    } else {
      content
    }
  }
}
