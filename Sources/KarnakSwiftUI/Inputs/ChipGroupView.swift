import KarnakCore
import SwiftUI

/// `chip_group` (`docs/renderer-contract.md`, Inputs, `ResolvedChipGroup`): the chips in the options' box, one after
/// another from the leading edge and wrapping onto further lines, `spacing` apart both ways, in one accessibility
/// container named by the input. Each chip is a button around its label and is the option's touch target; VoiceOver
/// reads the selected one as selected. Picking an enabled chip sends its value, and takes focus from the other inputs.
/// Focus moving between chips sends nothing: the group reports focus entering and leaving it. In a `multiple` group (a set's or
/// a form's) a chip toggles on its own and sends every value selected then, in the options' order.
struct ChipGroupView: View {
  let group: ResolvedChipGroup
  let placement: ChildPlacement
  @FocusState private var focusedChip: String?
  @Environment(\.karnakInputs) private var inputs
  @Environment(\.karnakInputFocus) private var focus

  var body: some View {
    let drawn = restyled(group, for: focusedChip != nil ? [.focused] : [])
    InputFrame(input: drawn, placement: placement, label: drawn.label, support: drawn.error) {
      chips(drawn)
        .partBox(drawn.control)
        .accessibilityElement(children: .contain)
        .inputAccessibility(drawn)
    }
    .onChange(of: focusedChip != nil) { _, isFocused in
      inputs.send(.focusChange(group.key, isFocused))
      if isFocused { focus.moved(to: group.key.value) }
    }
    .onReceive(focus.moves) { if $0 != group.key.value { focusedChip = nil } }
    .onReceive(focus.requests) { key in
      if key == group.key.value, focus.take(key) { focusedChip = focusTarget }
    }
    .onAppear {
      if focus.take(group.key.value) { focusedChip = focusTarget }
    }
  }

  private func chips(_ drawn: ResolvedChipGroup) -> some View {
    ChipFlowLayout(spacing: points(dp: drawn.spacing)) {
      ForEach(drawn.options, id: \.value) { option in
        ChipView(option: option, focused: $focusedChip) { pick(option) }
      }
    }
    .frame(maxWidth: placement.spans(drawn) ? .infinity : nil, alignment: .leading)
  }

  /// The chip a `FocusRequest` focuses: the selected one, else the first enabled one.
  private var focusTarget: String? {
    group.selected ?? group.options.first(where: \.enabled)?.value
  }

  private func pick(_ option: ResolvedOption) {
    focus.moved(to: group.key.value)
    guard group.acceptsEdits, option.enabled else { return }
    if group.multiple {
      let chosen = group.options.filter { $0.value == option.value ? !$0.selected : $0.selected }
      inputs.send(.selectionChange(group.key, chosen.map(\.value)))
    } else if !option.selected {
      inputs.send(.valueChange(group.key, option.value))
    }
  }
}

/// One chip of a chip group, styled for its own pressed, hovered and focused states.
private struct ChipView: View {
  let option: ResolvedOption
  let focused: FocusState<String?>.Binding
  let pick: () -> Void
  @State private var pressed = false
  @State private var hovered = false

  var body: some View {
    let drawn = option.styled(
      for: activeInteractions(
        pressed: pressed, hovered: hovered, focused: focused.wrappedValue == option.value))
    Button(action: pick) {
      InputTextView(drawn.label)
        .partBox(drawn.row, alignment: .center)
    }
    .buttonStyle(PressTrackingStyle(pressed: $pressed))
    .focused(focused, equals: option.value)
    .disabled(!drawn.enabled)
    .onHover { hovered = $0 }
    .accessibilityLabel(option.label.words)
    .accessibilityAddTraits(drawn.selected ? .isSelected : [])
  }
}

/// Lays chips out one after another from the leading edge, starting a new line when the next does not fit, `spacing`
/// apart along a line and between lines. SwiftUI mirrors a custom layout for a right-to-left environment.
private struct ChipFlowLayout: Layout {
  let spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    arranged(in: proposal.width, subviews).size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let layout = arranged(in: bounds.width, subviews)
    for (subview, frame) in zip(subviews, layout.frames) {
      subview.place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        anchor: .topLeading, proposal: ProposedViewSize(frame.size))
    }
  }

  private func arranged(in width: CGFloat?, _ subviews: Subviews) -> (
    size: CGSize, frames: [CGRect]
  ) {
    let limit = width.flatMap { $0.isFinite ? $0 : nil } ?? .infinity
    var frames: [CGRect] = []
    var across: CGFloat = 0
    var down: CGFloat = 0
    var lineHeight: CGFloat = 0
    var widest: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if across > 0 && across + size.width > limit {
        across = 0
        down += lineHeight + spacing
        lineHeight = 0
      }
      frames.append(CGRect(origin: CGPoint(x: across, y: down), size: size))
      across += size.width + spacing
      lineHeight = max(lineHeight, size.height)
      widest = max(widest, across - spacing)
    }
    return (CGSize(width: widest, height: down + lineHeight), frames)
  }
}
