import CoreGraphics
import KarnakCore

/// The node types this renderer draws, cast once from the exported class hierarchy. Kotlin
/// sealed classes import as plain classes, so anything else, such as a type a newer engine
/// adds, is ``unsupported``.
enum NodeKind {
  case column(ResolvedColumn)
  case form(ResolvedForm)
  case row(ResolvedRow)
  case grid(ResolvedGrid)
  case stack(ResolvedStack)
  case list(ResolvedList)
  case carousel(ResolvedCarousel)
  case text(ResolvedText)
  case image(ResolvedImage)
  case icon(ResolvedIconNode)
  case button(ResolvedButton)
  case progress(ResolvedProgressNode)
  case custom(ResolvedCustom)
  case unsupported

  init(_ node: ResolvedNode) {
    self = Self.layout(node) ?? Self.content(node) ?? .unsupported
  }

  /// The kind of a node that lays children out, or nil for any other node.
  private static func layout(_ node: ResolvedNode) -> NodeKind? {
    switch node {
    case let column as ResolvedColumn: .column(column)
    case let form as ResolvedForm: .form(form)
    case let row as ResolvedRow: .row(row)
    case let grid as ResolvedGrid: .grid(grid)
    case let stack as ResolvedStack: .stack(stack)
    case let list as ResolvedList: .list(list)
    case let carousel as ResolvedCarousel: .carousel(carousel)
    default: nil
    }
  }

  /// A node that draws content of its own, or nil.
  private static func content(_ node: ResolvedNode) -> NodeKind? {
    switch node {
    case let text as ResolvedText: .text(text)
    case let image as ResolvedImage: .image(image)
    case let icon as ResolvedIconNode: .icon(icon)
    case let button as ResolvedButton: .button(button)
    case let progress as ResolvedProgressNode: .progress(progress)
    case let custom as ResolvedCustom: .custom(custom)
    default: nil
    }
  }

  /// Whether ``NodeView`` draws this kind itself; see `drawnNode(_:)` for the others.
  var isDrawn: Bool {
    switch self {
    case .custom, .unsupported: false
    default: true
    }
  }

  /// Whether the node lays children out: the roots that fill the screen. A `text`, `image` or
  /// `button` root keeps its own size at the top start corner.
  var isContainer: Bool {
    switch self {
    case .column, .form, .row, .stack, .list: true
    default: false
    }
  }

  /// Whether the node reports its whole box to the frame observer: a collection whose items the conformance runner
  /// cannot read, as a UIKit-backed scroll view keeps its content out of an in-process accessibility traversal.
  var reportsFrame: Bool {
    switch self {
    case .list, .carousel: true
    default: false
    }
  }

  /// Where the primitive sits when its box is larger than it: a stack's content alignment, a
  /// paragraph's alignment, a button's center, else the top start corner.
  var contentPosition: ContentPosition {
    switch self {
    case .stack(let stack): ContentPosition(stack.contentAlignment)
    case .text(let text): ContentPosition(text.paragraph.textAlign)
    case .button: .center
    default: .topStart
    }
  }

  /// How the primitive relates to its box: an image fills it, and the rest are measured.
  var boxContent: BoxContent {
    switch self {
    case .image(let image):
      .image(aspectRatio: image.aspectRatio.map { CGFloat($0.floatValue) })
    default: .measured
    }
  }

  /// The nodes drawn inside this one: a container's children or a custom node's fallback.
  var children: [ResolvedNode] {
    switch self {
    case .column(let column): column.children
    case .form(let form): form.children
    case .row(let row): row.children
    case .grid(let grid): grid.children
    case .stack(let stack): stack.children
    case .list(let list): list.children
    case .carousel(let carousel): carousel.children
    case .custom(let custom): custom.fallback.map { [$0] } ?? []
    case .text, .image, .icon, .button, .progress, .unsupported: []
    }
  }
}

/// The node drawn in `node`'s place, or nil when nothing is: no custom renderers are
/// registered yet, so a custom node draws its fallback, and an unsupported node is skipped.
/// Containers draw only these, so a skipped node takes no slot and no spacing.
func drawnNode(_ node: ResolvedNode) -> ResolvedNode? {
  switch NodeKind(node) {
  case .custom(let custom): custom.fallback.flatMap(drawnNode)
  case .unsupported: nil
  default: node
  }
}
