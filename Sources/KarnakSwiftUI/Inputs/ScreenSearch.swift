import KarnakCore
import SwiftUI
import UIKit

/// Where a screen draws its `search` (ADR 0043, D5; `docs/renderer-contract.md`, `ResolvedSearch`).
enum SearchPlacement: Equatable {
  /// In the node's place, as a field of the screen's own (``SearchFieldView``): a section, or a screen with no
  /// navigation bar to hold the system's field.
  case inline
  /// Not known yet: the screen has not learned whether a navigation bar shows it. Nothing is drawn meanwhile.
  case pending
  /// Hoisted into the system's search field (``ScreenSearchable``): the node with this key draws nothing.
  case hoisted(key: String)

  /// Whether `node` takes a place of its own where it stands: anything but a search this placement keeps out of it.
  func drawsInPlace(_ node: ResolvedNode) -> Bool {
    guard let search = node as? ResolvedSearch else { return true }
    switch self {
    case .inline: return true
    case .pending: return false
    case .hoisted(let key): return key != search.key.value
    }
  }
}

extension EnvironmentValues {
  /// Where the `search` of the screen being drawn goes; outside a screen, in its place.
  @Entry var karnakSearchPlacement = SearchPlacement.inline
}

/// A screen's `search`, hoisted into SwiftUI's `.searchable` (ADR 0043, D5): the screen view puts it on its own content,
/// never on the host's stack, and the system places the field (in the navigation bar, at the bottom on an iOS 26
/// iPhone, top trailing on an iPad). It works only where a navigation bar shows the screen: elsewhere (a sheet the
/// engine presents, a screen in no stack, the root of a stack whose bar is hidden) `.searchable` has no toolbar to live
/// in, so the node draws a field of its own in its place.
struct ScreenSearch: ViewModifier {
  /// The screen's search, if it has one and hoists it; a screen shows at most one (`search_not_unique`).
  let search: ResolvedSearch?
  /// Whether a navigation bar shows the screen (``SearchBarProbe``); nil until it is known.
  @State private var hasBar: Bool?

  func body(content: Content) -> some View {
    hoisted(content)
      .environment(\.karnakSearchPlacement, placement)
      .background {
        if search != nil {
          SearchBarProbe { hasBar = $0 }.accessibilityHidden(true)
        }
      }
  }

  @ViewBuilder private func hoisted(_ content: Content) -> some View {
    if let search, hasBar == true {
      content.modifier(ScreenSearchable(search: search))
    } else {
      content
    }
  }

  private var placement: SearchPlacement {
    guard let search else { return .inline }
    switch hasBar {
    case .none: return .pending
    case .some(true): return .hoisted(key: search.key.value)
    case .some(false): return .inline
    }
  }

  /// The search `screen` shows: the first in its tree. The engine has already picked an `adaptive`'s branch, so the
  /// tree holds only what is shown.
  static func find(in screen: ResolvedScreen) -> ResolvedSearch? {
    var pending = screen.root.map { [$0] } ?? []
    while let node = pending.popLast() {
      if let search = node as? ResolvedSearch { return search }
      pending.append(contentsOf: NodeRenderers.children(of: node).reversed())
    }
    return nil
  }
}

/// `.searchable` for a screen's search: the query two-way with the engine's value, the placeholder (else the accessible
/// name) as the prompt, each suggestion a `.searchCompletion` of its value, Search submitting the engine's payload,
/// and the system's Cancel button, which clears the query (one edit to `""`). `autofocus` presents the search, which
/// focuses the field, the first time the screen draws it, and the engine's `FocusRequest` for it does the same.
struct ScreenSearchable: ViewModifier {
  let search: ResolvedSearch
  @State private var text: String
  @State private var presented = false
  @State private var autofocused = false
  @State private var query: SearchQuery
  @Environment(\.karnakInputs) private var inputs
  @Environment(\.karnakActions) private var actions
  @Environment(\.karnakInputFocus) private var focus
  @Environment(\.autocorrectionDisabled) private var hostAutocorrectionDisabled

  init(search: ResolvedSearch) {
    self.search = search
    _text = State(initialValue: search.value)
    _query = State(initialValue: SearchQuery(search))
  }

  func body(content: Content) -> some View {
    content
      // The system's search field takes a query as typed (below). The screen's own fields get back the host's
      // autocorrection setting and the system's default capitalization: SwiftUI can't read the host's.
      .textInputAutocapitalization(nil)
      .autocorrectionDisabled(hostAutocorrectionDisabled)
      .searchable(text: $text, isPresented: $presented, prompt: Text(search.prompt))
      .searchSuggestions {
        // A disabled suggestion can't be picked, and the system has no disabled completion: it is left out.
        ForEach(Array(search.suggestions.enumerated()), id: \.offset) { _, suggestion in
          if suggestion.enabled {
            Text(suggestion.label.words).searchCompletion(suggestion.value)
          }
        }
      }
      .onSubmit(of: .search) {
        query.submit(text, search: search, inputs: inputs, actions: actions)
      }
      .syncsSearchQuery(search, text: $text, query: query, inputs: inputs)
      .onChange(of: presented) { _, isPresented in
        // A disabled search takes no focus, so nothing is typed into it: the system's field has no disabled state.
        if isPresented, !search.enabled {
          presented = false
          return
        }
        inputs.send(.focusChange(search.key, isPresented))
      }
      .onChange(of: search.enabled) { _, enabled in
        if !enabled { presented = false }
      }
      .onReceive(focus.requests) { requested in
        if requested == search.key.value, focus.take(requested), search.enabled { presented = true }
      }
      .task(id: search.key.value) { await autofocusOnce() }
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
  }

  /// Presents the search once, when the screen first draws it with `autofocus`. A request made in the same update as
  /// the field's creation is lost, so it waits for the next turn of the main loop.
  private func autofocusOnce() async {
    if focus.take(search.key.value) { presented = true }
    guard search.autofocus, search.enabled, !autofocused else { return }
    autofocused = true
    await Task.yield()
    presented = true
  }
}

/// Tells whether a navigation controller shows the view it sits in with its bar, where `.searchable` puts its field.
/// The environment alone can't say it: a sheet an app presents from a screen of a stack inherits the stack's
/// environment but is in no stack, and a stack may hide its bar.
struct SearchBarProbe: UIViewControllerRepresentable {
  let report: (Bool) -> Void

  func makeUIViewController(context: Context) -> ProbeController {
    let controller = ProbeController()
    controller.report = report
    return controller
  }

  func updateUIViewController(_ controller: ProbeController, context: Context) {
    controller.report = report
  }

  final class ProbeController: UIViewController {
    var report: (Bool) -> Void = { _ in }
    private var reported: Bool?

    override func loadView() {
      view = UIView()
      view.isUserInteractionEnabled = false
      view.isAccessibilityElement = false
    }

    override func didMove(toParent parent: UIViewController?) {
      super.didMove(toParent: parent)
      check()
    }

    override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
      check()
    }

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      check()
    }

    private func check() {
      // Not yet in the controller tree: nothing to tell, rather than a false "no bar".
      guard parent != nil else { return }
      let found = navigationController.map { !$0.isNavigationBarHidden } ?? false
      guard found != reported else { return }
      reported = found
      // Not during SwiftUI's update of the view that holds the probe.
      DispatchQueue.main.async { [report] in report(found) }
    }
  }
}
