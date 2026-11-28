import KarnakCore
import SwiftUI

/// A `select` with `presentation: "sheet"` (ADR 0062, D11; `docs/renderer-contract.md`, Choice status): the options in
/// a sheet titled with the select's `title`, at medium height and draggable to large, with a search field that filters
/// them by the engine's rule (`OptionSearch`), so every renderer finds the same options for the same query. The
/// selected option is checked; picking an enabled one sends its value and closes the sheet, and dismissing it changes
/// nothing. While the options reload the sheet keeps them, dimmed and not pickable. When it lists nothing it says why:
/// the engine's `noMatchesText` for a query, else the select's notice ("Choose City first", "No options"); an options
/// error shows under the list with its retry, as under the box. A disabled option is shown and can't be picked.
struct SelectSheet: View {
  let select: ResolvedSelect
  /// Picks the option with this value; the select closes the sheet.
  let pick: (String) -> Void
  @State private var query = ""

  var body: some View {
    NavigationStack {
      list
        .navigationTitle(select.title ?? select.accessibleName)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
    }
    .presentationDetents([.medium, .large])
  }

  private var list: some View {
    VStack(spacing: 0) {
      let matches = SelectSheet.matches(select.options, query)
      if matches.isEmpty, let empty = SelectSheet.emptyText(select, query: query) {
        Text(verbatim: empty)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(matches, id: \.value) { option in
          row(option)
        }
        .busyOptions(select.busy)
      }
      if let error = select.optionsError {
        OptionsErrorView(error: error).padding()
      }
    }
  }

  private func row(_ option: ResolvedOption) -> some View {
    Button {
      guard option.enabled, !select.busy else { return }
      pick(option.value)
    } label: {
      HStack {
        Text(verbatim: option.label.words)
        Spacer(minLength: optionTrailingGap)
        if option.value == select.selected {
          Image(systemName: "checkmark").accessibilityHidden(true)
        }
      }
      .contentShape(Rectangle())
    }
    .foregroundStyle(option.enabled ? Color.primary : Color.secondary)
    .disabled(!option.enabled)
    .accessibilityLabel(option.spokenLabel)
    .accessibilityAddTraits(option.value == select.selected ? .isSelected : [])
  }

  /// What the sheet says when it lists nothing: the engine's `noMatchesText` for a query that matches no option, else
  /// the select's notice, why it has none to offer. A query of only spaces is no query, as the matcher reads it.
  static func emptyText(_ select: ResolvedSelect, query: String) -> String? {
    query.trimmingCharacters(in: .whitespaces).isEmpty ? select.notice?.words : select.noMatchesText
  }

  /// The options whose label matches `query`, in their order: the engine's matcher, shared with the other renderers.
  static func matches(_ options: [ResolvedOption], _ query: String) -> [ResolvedOption] {
    OptionSearch.shared.filter(options: options, query: query)
  }
}
