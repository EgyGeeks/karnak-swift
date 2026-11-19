import KarnakCore
import SwiftUI

/// `search` (`docs/renderer-contract.md`, `ResolvedSearch`; ADR 0043, D5). Where the screen hoists it into the system's
/// search field (``ScreenSearch``) the node draws nothing; until the screen knows, nothing either. Elsewhere (a section,
/// or a screen with no navigation bar for `.searchable` to live in) it draws a search field in its place: the search
/// icon, the query over the placeholder, and a clear button while there is text, in the bar's box; under it, while the
/// field has focus, the suggestions in the menu's box. Search on the keyboard submits the query, and a picked suggestion
/// writes its value as one edit, then submits it; either closes the keyboard and the suggestions once something is
/// sent.
struct SearchFieldView: View {
  let search: ResolvedSearch
  let placement: ChildPlacement
  @Environment(\.karnakSearchPlacement) private var searchPlacement

  var body: some View {
    // A second search the screen shows despite `search_not_unique` is drawn in place: only the first one is hoisted.
    if searchPlacement.drawsInPlace(search) {
      InlineSearchField(search: search, placement: placement)
    }
  }
}

private struct InlineSearchField: View {
  let search: ResolvedSearch
  let placement: ChildPlacement
  @State private var text: String
  @State private var query: SearchQuery
  @State private var autofocused = false
  @State private var hovered = false
  @FocusState private var focused: Bool
  @Environment(\.karnakInputs) private var inputs
  @Environment(\.karnakActions) private var actions
  @Environment(\.karnakInputFocus) private var focus

  init(search: ResolvedSearch, placement: ChildPlacement) {
    self.search = search
    self.placement = placement
    _text = State(initialValue: search.value)
    _query = State(initialValue: SearchQuery(search))
  }

  var body: some View {
    let drawn = restyled(
      search, for: activeInteractions(pressed: false, hovered: hovered, focused: focused))
    InputFrame(input: drawn, placement: placement, label: nil, support: drawn.error) {
      VStack(alignment: .leading, spacing: 0) {
        bar(drawn)
        if focused, !drawn.suggestions.isEmpty { suggestions(drawn) }
      }
    }
    .onHover { hovered = $0 }
    .syncsSearchQuery(search, text: $text, query: query, inputs: inputs)
    .reportsFocus(search.key, focused, to: inputs)
    .takesFocusRequests(search.key.value, focus: focus, focused: $focused)
    .onAppear {
      guard search.autofocus, search.enabled, !autofocused else { return }
      autofocused = true
      focused = true
    }
  }

  private func bar(_ drawn: ResolvedSearch) -> some View {
    HStack(spacing: 0) {
      VectorIconView(drawn.searchIcon)
      ZStack(alignment: .leading) {
        if text.isEmpty, let placeholder = drawn.placeholder { InputTextView(placeholder) }
        TextField("", text: $text)
          .modifier(InputValueStyle(style: drawn.textStyle, multiline: false))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .submitLabel(.search)
          .onSubmit { submit(text) }
          .focused($focused)
          .disabled(!drawn.enabled)
          .accessibilityLabel(drawn.accessibleName)
          .accessibilityHint(drawn.accessibleHint)
          .accessibilityAddTraits(.isSearchField)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if !text.isEmpty, drawn.acceptsEdits {
        Button {
          text = ""
        } label: {
          VectorIconView(drawn.clearIcon)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(drawn.clearLabel)
      }
    }
    .frame(maxWidth: placement.spans(drawn) ? .infinity : nil, alignment: .leading)
    .partBox(drawn.control)
    .contentShape(Rectangle())
    .onTapGesture { if drawn.enabled { focused = true } }
  }

  /// The suggestions, each a button that VoiceOver reads by its label, in the menu's box.
  private func suggestions(_ drawn: ResolvedSearch) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      // By position: a server may send two suggestions with the same value.
      ForEach(Array(drawn.suggestions.enumerated()), id: \.offset) { _, suggestion in
        Button {
          pick(suggestion.value)
        } label: {
          InputTextView(suggestion.label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .partBox(suggestion.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!suggestion.enabled)
        .accessibilityLabel(suggestion.label.words)
      }
    }
    .partBox(drawn.menu)
    .accessibilityElement(children: .contain)
  }

  private func pick(_ value: String) {
    text = value
    submit(value)
  }

  /// Submits `value`; once something is sent the keyboard closes. When nothing is (a query below `minLength`), the
  /// field takes back the focus SwiftUI's submit ended, so the person goes on typing with the suggestions open.
  private func submit(_ value: String) {
    focused = !query.submit(value, search: search, inputs: inputs, actions: actions)
  }
}
