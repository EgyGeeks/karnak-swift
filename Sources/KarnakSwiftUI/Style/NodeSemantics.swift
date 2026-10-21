import KarnakCore
import SwiftUI

/// Maps a node's resolved semantics to SwiftUI accessibility (`docs/renderer-contract.md`,
/// `ResolvedSemantics`):
/// - a hidden node leaves the accessibility tree with its subtree;
/// - `mergeDescendants` combines the subtree into one element;
/// - a container with its own label, hint, state or role that doesn't merge becomes a labelled
///   group that contains its children, so each stays reachable;
/// - a leaf drawn as one box (an `icon` or a `progress`) is one element over its padded box;
/// - roles become traits, the state description the element's value, and a disabled node is
///   disabled;
/// - a `progress` is represented by the system's own `ProgressView` (a determinate one with its
///   whole-percent value, else an indeterminate one), so VoiceOver reads Apple's localized
///   progress semantics, including the in-progress state, with no string of ours.
struct NodeSemantics: ViewModifier {
  /// The node's semantics.
  let semantics: AccessibilitySemantics
  /// Whether the node lays out children, rather than being an element itself, as text is.
  let isContainer: Bool
  /// Whether the node's whole padded box is one accessibility element, as for an `icon` or a
  /// `progress`: its frame then includes the padding, as TalkBack's and the web's do.
  let isBoxElement: Bool

  init(semantics: ResolvedSemantics, isContainer: Bool, isBoxElement: Bool = false) {
    self.init(
      semantics: AccessibilitySemantics(semantics), isContainer: isContainer,
      isBoxElement: isBoxElement)
  }

  init(semantics: AccessibilitySemantics, isContainer: Bool, isBoxElement: Bool = false) {
    self.semantics = semantics
    self.isContainer = isContainer
    self.isBoxElement = isBoxElement
  }

  func body(content: Content) -> some View {
    if semantics.hidden {
      content.accessibilityHidden(true)
    } else if semantics.mergeDescendants {
      described(content.accessibilityElement(children: .combine))
    } else if isBoxElement {
      // A clear element behind the glyph, as large as the padded box, so the frame includes the padding.
      content.background {
        described(Rectangle().fill(.clear).accessibilityElement(children: .ignore))
      }
      .accessibilityElement(children: .contain)
    } else if isContainer && isDescribed {
      described(content.accessibilityElement(children: .contain))
    } else {
      described(content)
    }
  }

  private var isDescribed: Bool {
    !semantics.traits.isEmpty || semantics.label != nil || semantics.hint != nil
      || semantics.stateDescription != nil
  }

  @ViewBuilder
  private func described(_ element: some View) -> some View {
    if let progress = semantics.progress {
      element.accessibilityRepresentation { progressElement(progress) }
    } else {
      plain(element)
    }
  }

  /// What VoiceOver reads for a `progress`: the system's progress view with the node's label and hint.
  private func progressElement(_ progress: ProgressSemantics) -> some View {
    progress.view
      .accessibilityLabel(ifPresent: semantics.label)
      .accessibilityHint(ifPresent: semantics.hint)
      .disabled(semantics.disabled)
  }

  private func plain(_ element: some View) -> some View {
    element
      .accessibilityAddTraits(semantics.traits)
      .accessibilityLabel(ifPresent: semantics.label)
      .accessibilityHint(ifPresent: semantics.hint)
      .accessibilityValue(ifPresent: semantics.stateDescription)
      .disabled(semantics.disabled)
  }
}

/// `ResolvedSemantics` as SwiftUI reads it. Swift can't construct resolved values, so tests
/// build this directly for states a level-1 tree never has, such as a loading button's state
/// description.
struct AccessibilitySemantics: Equatable {
  /// The role's traits.
  var traits: AccessibilityTraits = []
  var label: String?
  var hint: String?
  /// Read as the element's value, e.g. "Loading".
  var stateDescription: String?
  var hidden = false
  var disabled = false
  var mergeDescendants = false
  /// Set for a `progress`: it is read through the system's progress view instead of traits and a value.
  var progress: ProgressSemantics?
}

/// The progress an accessibility element reports: a whole-percent fraction, or nil while indeterminate.
struct ProgressSemantics: Equatable {
  /// The completed fraction, rounded to a whole percent with halves up (`docs/renderer-contract.md`); nil
  /// for an indeterminate one.
  var fraction: Double?

  init(_ value: Float?) {
    fraction = value.map { Double(($0 * 100).rounded()) / 100 }
  }

  /// The system's own element for it.
  @ViewBuilder
  var view: some View {
    if let fraction { ProgressView(value: fraction) } else { ProgressView() }
  }
}

extension AccessibilitySemantics {
  init(_ semantics: ResolvedSemantics) {
    self.init(
      traits: accessibilityTraits(semantics.role), label: semantics.label, hint: semantics.hint,
      stateDescription: semantics.stateDescription, hidden: semantics.hidden,
      disabled: semantics.disabled, mergeDescendants: semantics.mergeDescendants)
  }
}

extension AccessibilitySemantics {
  /// The semantics of a resolved node: its own, and for a `progress` the progress it reports
  /// (`docs/renderer-contract.md`, Display primitives): a whole percent, or none while indeterminate,
  /// which the system's progress view reads as in progress.
  init(_ node: ResolvedNode) {
    self.init(node.semantics)
    guard let progress = node as? ResolvedProgressNode else { return }
    self.progress = ProgressSemantics(progress.progress.value?.floatValue)
  }
}

extension View {
  /// Sets the label when there is one; otherwise the platform default stays, such as a
  /// text's own words.
  @ViewBuilder
  fileprivate func accessibilityLabel(ifPresent label: String?) -> some View {
    if let label { accessibilityLabel(label) } else { self }
  }

  @ViewBuilder
  fileprivate func accessibilityHint(ifPresent hint: String?) -> some View {
    if let hint { accessibilityHint(hint) } else { self }
  }

  @ViewBuilder
  fileprivate func accessibilityValue(ifPresent value: String?) -> some View {
    if let value { accessibilityValue(value) } else { self }
  }
}
