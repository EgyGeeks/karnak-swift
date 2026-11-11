import KarnakCore
import SwiftUI

/// A node's `actions.contextMenu` (`docs/renderer-contract.md`, Context menus) as the system's context menu: a long
/// press opens it, and a secondary click on iPadOS. A destructive item takes the system's destructive role. The system
/// draws the panel, so the menu's own colors, radius and shadows and the items' icons are not drawn here: a system
/// menu takes only system images. Each item is also one of the node's accessibility actions, named by its label: on
/// the node itself when it is one element, else on the element ``NodeClick`` gives its group.
struct NodeContextMenu: ViewModifier {
  let menu: ResolvedContextMenu?
  /// Whether the node is a group whose element ``NodeClick`` draws, which lists the actions instead.
  var inGroup = false
  @Environment(\.karnakActions) private var actions

  func body(content: Content) -> some View {
    if let menu {
      content
        .contextMenu {
          ForEach(menu.items, id: \.id) { item in
            Button(item.label, role: item.destructive ? .destructive : nil) { actions.click(item.onSelect) }
          }
        }
        .modifier(MenuActions(menu: inGroup ? nil : menu))
    } else {
      content
    }
  }
}

/// A context menu's items as the accessibility actions of the element it modifies, named by their labels.
struct MenuActions: ViewModifier {
  let menu: ResolvedContextMenu?
  @Environment(\.karnakActions) private var actions

  func body(content: Content) -> some View {
    if let menu {
      content.accessibilityActions {
        ForEach(menu.items, id: \.id) { item in
          Button(item.label) { actions.click(item.onSelect) }
        }
      }
    } else {
      content
    }
  }
}
