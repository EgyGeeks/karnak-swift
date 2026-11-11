import KarnakCore
import SwiftUI
import UIKit

/// `text_field` (`docs/renderer-contract.md`, Inputs, `ResolvedTextField`): a `TextField` (`axis: .vertical` with a
/// line limit when it has more than one line) or a `SecureField` in the field box, with the placeholder drawn under
/// it while the text is empty, and the label above and the helper or error below.
///
/// - **Value.** The field holds the native text in local state and sends each edit as `valueChange`; ``TextSync``
///   decides when the tree's value is written back. While the input is read-only (a submission in flight) the same
///   field stays, so focus, the keyboard and the accessibility element survive, and every edit is undone at once.
/// - **Display mask.** With `mask` the native text is the mask's text for the value and each edit is read with the
///   mask (``FieldText``; `docs/renderer-contract.md`, Display masks); the value sent never holds a literal.
/// - **Keyboard.** `.keyboardType`, `.textContentType`, `.submitLabel` from the resolved `keyboard`, `autofill` and
///   `imeAction`, and `.onSubmit` sends `imeAction`: SwiftUI ends editing on submit, so for `go`, `search` and `send`
///   the field takes its focus back (it is read-only, still focused, while its form is in flight) and `done` lets the
///   keyboard go. `@FocusState` reports `focusChange` and takes the engine's `FocusRequest`. The field is `focused`
///   whenever it has focus, a tap's included.
/// - **Direction.** The text, typed or placeholder, starts at the screen's start edge, and runs left to right for the
///   `email`, `number`, `decimal`, `phone` and `url` keyboards (``FieldTextLayout``).
/// - **Accessibility.** The accessible name is `semantics.label`, and the error is the hint (the helper while there
///   is none).
struct TextFieldView: View {
  let field: ResolvedTextField
  let placement: ChildPlacement
  @State private var text: String
  @State private var sync: TextSync
  @State private var caret: CaretMove?
  @State private var hovered = false
  @FocusState private var focused: Bool
  @Environment(\.karnakInputs) private var inputs
  @Environment(\.karnakInputFocus) private var focus
  @Environment(\.layoutDirection) private var screenDirection

  init(field: ResolvedTextField, placement: ChildPlacement) {
    self.field = field
    self.placement = placement
    _text = State(initialValue: FieldText(mask: field.mask).shows(field.value))
    _sync = State(initialValue: TextSync(field.value, edits: Int(field.edits)))
  }

  var body: some View {
    let drawn = restyled(
      field, for: activeInteractions(pressed: false, hovered: hovered, focused: focused))
    let layout = FieldTextLayout(keyboard: drawn.keyboard, screen: screenDirection)
    InputFrame(
      input: drawn, placement: placement, label: drawn.label, support: drawn.error ?? drawn.helper
    ) {
      ZStack(alignment: drawn.maxLines > 1 ? .topLeading : .leading) {
        if text.isEmpty, let placeholder = drawn.placeholder {
          InputTextView(placeholder, layout: layout)
        }
        editor(drawn, layout: layout)
      }
      .frame(maxWidth: placement.spans(drawn) ? .infinity : nil, alignment: .leading)
      .partBox(drawn.control)
      .underline(drawn.indicator, in: drawn.control)
      .contentShape(Rectangle())
      .onTapGesture { if drawn.enabled { focused = true } }
    }
    .onHover { hovered = $0 }
    .onChange(of: text) { _, typed in edited(typed) }
    .onChange(of: tree) { _, tree in
      apply(sync.treeValue(tree, readOnly: !field.acceptsEdits, shown: shownValue))
    }
    // A refresh that changes the mask alone: the text is drawn again with the new one.
    .onChange(of: field.mask?.pattern) { _, _ in
      let shown = fieldText.shows(field.value)
      if text != shown { text = shown }
    }
    .onChange(of: field.acceptsEdits) { _, accepts in
      if !accepts { apply(sync.locked(tree: tree, shown: shownValue)) }
    }
    .reportsFocus(field.key, focused, to: inputs)
    .takesFocusRequests(field.key.value, focus: focus, focused: $focused)
  }

  private func editor(_ drawn: ResolvedTextField, layout: FieldTextLayout) -> some View {
    nativeField(drawn)
      .fieldText(layout)
      .modifier(InputValueStyle(style: drawn.textStyle, multiline: drawn.maxLines > 1))
      .keyboardType(uiKeyboard(for: drawn.keyboard))
      .textContentType(drawn.autofill.flatMap(contentType(for:)))
      .textInputAutocapitalization(drawn.keyboard == .text && !drawn.secure ? .sentences : .never)
      .autocorrectionDisabled(drawn.secure || drawn.keyboard != .text)
      .submitLabel(drawn.imeAction.map(submitKey(for:)) ?? .return)
      .onSubmit { submitted(drawn.imeAction) }
      .modifier(
        KeypadActionKey(
          keyboard: drawn.keyboard, imeAction: drawn.imeAction, focused: focused,
          press: pressedKeypadKey)
      )
      .focused($focused)
      .disabled(!drawn.enabled)
      .inputAccessibility(drawn)
  }

  @ViewBuilder
  private func nativeField(_ drawn: ResolvedTextField) -> some View {
    if drawn.secure {
      SecureField("", text: $text)
    } else if drawn.maxLines > 1 {
      TextField("", text: $text, axis: .vertical)
        .lineLimit(Int(drawn.minLines)...Int(drawn.maxLines))
    } else if drawn.mask != nil, #available(iOS 18.0, *) {
      CaretTextField(text: $text, caret: caret)
    } else {
      TextField("", text: $text)
    }
  }

  private var fieldText: FieldText { FieldText(mask: field.mask) }

  /// The tree's value and the engine's count of the field's edits it was resolved with.
  private var tree: TextSync.Tree { TextSync.Tree(value: field.value, edits: Int(field.edits)) }

  /// The value the native text holds now: without a mask's literals.
  private var shownValue: String { fieldText.value(of: text) }

  /// The keyboard's action key: sends `imeAction`, then, for a key that keeps focus, puts it back where SwiftUI's
  /// submit ended editing, so a field that is read-only while its form is in flight is still the one the person is in.
  /// Focus the engine moved elsewhere while answering (a `FocusRequest` delivered at once) stays where it put it.
  private func submitted(_ action: ImeAction?) {
    guard let action else { return }
    let before = focus.latestMove
    inputs.send(.imeAction(field.key))
    if keepsFocus(afterActionKey: action), focus.latestMove == before { focused = true }
  }

  /// The keypad bar's button (``KeypadActionKey``): the action key as the return key sends it, then
  /// ``endsEditing(afterKeypadKey:focusMoved:)``.
  private func pressedKeypadKey(_ action: ImeAction) {
    let before = focus.latestMove
    submitted(action)
    if endsEditing(afterKeypadKey: action, focusMoved: focus.latestMove != before) {
      focused = false
    }
  }

  /// The native text changed to `typed`. A masked field's text is the mask's (it holds the length limit too): the
  /// field takes the text and the caret the mask gives, and the value without literals is the edit.
  private func edited(_ typed: String) {
    let maxLength = field.maxLength.map { Int($0.int32Value) }
    let edit = fieldText.read(typed, after: sync.agreed, maxLength: maxLength)
    if edit.text != typed { text = edit.text }
    if let offset = edit.caret { caret = CaretMove(offset: offset, edit: (caret?.edit ?? 0) + 1) }
    apply(
      sync.edited(
        edit.value, tree: field.value, accepts: field.acceptsEdits,
        maxLength: field.mask == nil ? maxLength : nil))
  }

  private func apply(_ outcome: TextSync.Outcome) {
    switch outcome {
    case .keep: break
    case .send(let value): inputs.send(.valueChange(field.key, value))
    case .replace(let value): text = fieldText.shows(value)
    }
  }
}

/// The value's font and color, and the cursor's color (`ResolvedTextField.textStyle`), scaled once for Dynamic Type
/// as a paragraph is, in the theme face once the registry has it. A range slider draws its picked values with it too.
struct InputValueStyle: ViewModifier {
  let style: InputTextStyle
  let multiline: Bool
  @Environment(\.karnakFonts) private var fonts

  func body(content: Content) -> some View {
    content.modifier(
      ObservedValueStyle(style: style, multiline: multiline, fonts: fonts ?? .unavailable))
  }
}

private struct ObservedValueStyle: ViewModifier {
  let style: InputTextStyle
  let multiline: Bool
  let fonts: ThemeFontRegistry
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  func body(content: Content) -> some View {
    let traits = UITraitCollection(
      preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
    let size = textPoints(sp: style.font.size, traits: traits)
    let name = style.font.face.flatMap(fonts.postScriptName(for:))
    let natural = (name.flatMap { UIFont(name: $0, size: size) } ?? .systemFont(ofSize: size))
      .lineHeight
    let line = style.lineHeight.map { textPoints(sp: $0.floatValue, traits: traits) } ?? natural
    let color = resolvedColor(style.color)
    content
      .font(resolvedFont(style.font, scaledPoints: size, postScriptName: name))
      .foregroundColor(color)
      .tint(color)
      .lineSpacing(multiline ? max(0, line - natural) : 0)
      .frame(minHeight: line)
  }
}

/// The keyboard for `keyboard` (`docs/renderer-contract.md`, Input accessibility).
func uiKeyboard(for keyboard: InputKeyboard) -> UIKeyboardType {
  switch keyboard {
  case .email: .emailAddress
  case .number: .numberPad
  case .decimal: .decimalPad
  case .phone: .phonePad
  case .url: .URL
  default: .default
  }
}

/// The autofill content type for `autofill` (`docs/renderer-contract.md`, Input accessibility).
@MainActor
func contentType(for autofill: Autofill) -> UITextContentType? {
  autofillContentTypes[autofill]
}

@MainActor private let autofillContentTypes: [Autofill: UITextContentType] = [
  .email: .emailAddress, .username: .username, .password: .password, .newpassword: .newPassword,
  .onetimecode: .oneTimeCode, .name: .name, .givenname: .givenName, .familyname: .familyName,
  .phone: .telephoneNumber, .postalcode: .postalCode, .streetaddress: .fullStreetAddress,
]

/// Whether the field keeps its focus after the action key `action` (`docs/renderer-contract.md`, IME actions): the keys
/// that submit the form do, and `done` ends editing, as the platform does. `next` is the engine's: its `FocusRequest`
/// moves focus on.
func keepsFocus(afterActionKey action: ImeAction) -> Bool {
  switch action {
  case .go, .search, .send: true
  default: false
  }
}

/// The keyboard's action key for `action` (`docs/renderer-contract.md`, IME actions).
func submitKey(for action: ImeAction) -> SubmitLabel {
  switch action {
  case .next: .next
  case .go: .go
  case .search: .search
  case .send: .send
  default: .done
  }
}
