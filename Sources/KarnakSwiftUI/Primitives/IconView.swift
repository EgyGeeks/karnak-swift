import KarnakCore
import SwiftUI

/// `icon`: the button's ``VectorIconView`` drawing in its `size` square (`docs/renderer-contract.md`,
/// Display primitives). A name the theme doesn't define leaves the square empty. The icon is one
/// accessibility element named by the node's semantics: labelled, or `semantics.hidden` when it is
/// decorative.
struct IconView: View {
  /// The icon node.
  let node: ResolvedIconNode

  var body: some View {
    VectorIconView(node.icon)
  }
}
