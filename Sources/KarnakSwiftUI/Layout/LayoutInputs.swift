import SwiftUI

/// The container renderer passes resolved bounds, not raw protocol fields.
struct KarnakLayoutInput: Sendable {
  var weight: CGFloat = 0
  var width = AxisBounds()
  var height = AxisBounds()
  var wrapsWidth = true
  var wrapsHeight = true
  /// The child's width is `Fixed`: in a grid it keeps it up to its cells' width.
  var fixedWidth = false
  /// The child is as wide as it is given whatever its `Wrap` width says (a `grid`): in a grid it
  /// takes its cells' width.
  var takesGivenWidth = false
  /// The child's own cross alignment (`layout.align`); nil follows the container.
  var align: KarnakCrossAlignment?
  /// The columns the child covers in a grid; 1 anywhere else.
  var span = 1
  /// The rows the child covers in a grid; 1 anywhere else.
  var rowSpan = 1
  /// The cells the child takes in a grid whose area it names; nil for a child placed in order.
  var gridArea: KarnakGridCell?
  /// The child's height is `Fill`: in a grid it takes its row's height.
  var fillsHeight = false
  /// How the child flexes on its line in a wrapping row; nil when it doesn't.
  var flex: KarnakFlex?
}

/// A child's `grow`, `shrink` and `basis` in a wrapping row, in points.
struct KarnakFlex: Sendable, Equatable {
  var grow: CGFloat = 0
  var shrink: CGFloat = 0
  /// The width lines break with and flexing starts from; nil for the child's own width.
  var basis: CGFloat?
}

struct KarnakLayoutInputKey: LayoutValueKey {
  static let defaultValue = KarnakLayoutInput()
}

extension View {
  func karnakLayoutInput(_ input: KarnakLayoutInput) -> some View {
    layoutValue(key: KarnakLayoutInputKey.self, value: input)
  }
}
