import KarnakCore
import SwiftUI

/// `column` and `form`: children top to bottom through ``KarnakColumnLayout``, which runs
/// weighted allocation, space arrangements and `stretch` (`docs/renderer-contract.md`, `column`).
struct ColumnView: View {
  /// The children, painted and read in order.
  let children: [ResolvedNode]
  /// The container's layout fields.
  let fields: LinearFields
  /// Which axes of the container's box its own parent sizes.
  let placement: ChildPlacement
  /// The container's key: the rows of a `repeat` below it anchor the scroll.
  let key: String

  var body: some View {
    let stretches = fields.alignment == .stretch
    KarnakColumnLayout(
      wrapsWidth: placement.wraps(.horizontal, of: fields.layout),
      wrapsHeight: placement.wraps(.vertical, of: fields.layout),
      spacing: fields.spacing, arrangement: fields.arrangement, alignment: fields.alignment
    ) {
      NodeChildren(nodes: children, parent: key) {
        ChildPlacement.linear($0, axis: .vertical, stretches: stretches)
      }
    }
  }
}

/// `row`: children from the start edge through ``KarnakRowLayout``, or wrapped onto lines through
/// ``KarnakFlowLayout`` (`docs/renderer-contract.md`, `row`). Switching `wrap` keeps the children.
struct RowView: View {
  /// The row.
  let row: ResolvedRow
  /// Which axes of the row's box its own parent sizes.
  let placement: ChildPlacement

  var body: some View {
    let fields = LinearFields(row)
    let wrapsWidth = placement.wraps(.horizontal, of: row.layout)
    let wrapsHeight = placement.wraps(.vertical, of: row.layout)
    let layout =
      row.wrap
      ? AnyLayout(
        KarnakFlowLayout(
          wrapsWidth: wrapsWidth, wrapsHeight: wrapsHeight, spacing: fields.spacing,
          arrangement: fields.arrangement, alignment: fields.alignment))
      : AnyLayout(
        KarnakRowLayout(
          wrapsWidth: wrapsWidth, wrapsHeight: wrapsHeight, spacing: fields.spacing,
          arrangement: fields.arrangement, alignment: fields.alignment))
    let stretches = fields.alignment == .stretch
    layout {
      NodeChildren(nodes: row.children, parent: row.key.value) {
        ChildPlacement.linear($0, axis: .horizontal, stretches: stretches)
      }
    }
  }
}

/// `stack`: children painted in order, last on top, each at the logical content alignment; the
/// stack sizes to its largest child (`docs/renderer-contract.md`, `stack`).
struct StackView: View {
  /// The stack.
  let stack: ResolvedStack
  /// Which axes of the stack's box its own parent sizes.
  let placement: ChildPlacement

  var body: some View {
    KarnakStackLayout(
      wrapsWidth: placement.wraps(.horizontal, of: stack.layout),
      wrapsHeight: placement.wraps(.vertical, of: stack.layout),
      alignment: ContentPosition(stack.contentAlignment)
    ) {
      NodeChildren(nodes: stack.children, parent: stack.key.value) { _ in .standalone }
    }
  }
}
