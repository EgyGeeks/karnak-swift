import KarnakCore

/// What decides whether a new tree changes the structure of the one on screen.
enum TreeStructure {
  /// Whether `new` has the same nodes, in the same order, as `shown`: every container holds the
  /// same keys in the same sequence. A tree that only changes what nodes show (a bound text, a
  /// color) has the same structure, so it applies at once; one that adds, removes or reorders
  /// nodes, such as the rows of a `repeat`, does not.
  static func isSame(_ shown: ResolvedScreen, _ new: ResolvedScreen) -> Bool {
    switch (shown.root, new.root) {
    case (nil, nil): true
    case (let old?, let current?): isSame(old, current)
    default: false
    }
  }

  private static func isSame(_ old: ResolvedNode, _ new: ResolvedNode) -> Bool {
    if old === new { return true }
    guard old.key.value == new.key.value else { return false }
    let oldChildren = NodeKind(old).children
    let newChildren = NodeKind(new).children
    guard oldChildren.count == newChildren.count else { return false }
    return zip(oldChildren, newChildren).allSatisfy { isSame($0, $1) }
  }

  /// The row a node belongs to, `<repeat id>,<s or n><key>`, read from its key: a node with a
  /// unique id inside a row is `r:<row>/<id>`, one without an id is `p:r:<row>/<path>`
  /// (`docs/renderer-contract.md`, Keys). Nil for a node outside any row.
  static func rowCode(of key: String) -> String? {
    let rest: Substring
    if key.hasPrefix("r:") {
      rest = key.dropFirst(2)
    } else if key.hasPrefix("p:r:") {
      rest = key.dropFirst(4)
    } else {
      return nil
    }
    return rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first
      .map(String.init)
  }

  /// Whether the node `key` is the root of a row: it belongs to one, and its parent `parentKey`
  /// does not belong to the same one.
  static func isRowRoot(_ key: String, parent parentKey: String?) -> Bool {
    guard let code = rowCode(of: key) else { return false }
    return parentKey.flatMap(rowCode(of:)) != code
  }

  /// The keys of the row roots in `screen`: the nodes whose frames anchor the scroll.
  static func rowRootKeys(_ screen: ResolvedScreen) -> Set<String> {
    var keys: Set<String> = []
    func visit(_ node: ResolvedNode, parent: String?) {
      if isRowRoot(node.key.value, parent: parent) { keys.insert(node.key.value) }
      for child in NodeKind(node).children { visit(child, parent: node.key.value) }
    }
    if let root = screen.root { visit(root, parent: nil) }
    return keys
  }
}
