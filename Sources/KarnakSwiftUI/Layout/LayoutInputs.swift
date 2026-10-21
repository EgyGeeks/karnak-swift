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
  /// The child's height is `Fill`: in a grid it takes its row's height.
  var fillsHeight = false
}

struct KarnakLayoutInputKey: LayoutValueKey {
  static let defaultValue = KarnakLayoutInput()
}

extension View {
  func karnakLayoutInput(_ input: KarnakLayoutInput) -> some View {
    layoutValue(key: KarnakLayoutInputKey.self, value: input)
  }
}
