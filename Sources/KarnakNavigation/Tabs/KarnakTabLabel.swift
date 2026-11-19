import KarnakCore
import KarnakSwiftUI
import SwiftUI
import UIKit

/// A tab's label in the system tab bar, filled from the server (ADR 0045, D14): the tab's
/// `label` key from the project's string table in the device's language (the id when it has
/// none), and its theme `icon` (`selectedIcon` while selected) as a template image the bar tints.
/// ``KarnakTabView`` draws it when the app gives no `label` of its own.
public struct KarnakTabLabel: View {
  let tab: KarnakTab
  let selected: Bool
  let icons: KarnakTabIcons
  @Environment(\.karnakResources) private var resources

  public var body: some View {
    Label {
      Text(verbatim: tab.label.map { resources.string($0) } ?? tab.id)
    } icon: {
      if let image = icons.image(tab.iconFor(selected: selected)) {
        Image(uiImage: image)
      } else if tab.isSearch {
        // A search tab with no theme icon shows the system's magnifying glass, as UIKit's search tab does.
        Image(systemName: "magnifyingglass")
      }
    }
  }
}

/// The theme's tab bar for one appearance and direction: its tint and each tab icon drawn once.
struct KarnakTabIcons: Equatable {
  let tint: Color?
  private let images: [String: UIImage]

  static let none = KarnakTabIcons(tint: nil, images: [:])

  @MainActor init(_ style: ResolvedTabBarStyle) {
    // The system bar draws its own selection behind the item, not the theme's indicator: the tint
    // is the selected label's color, made to read on the bar, not the selected icon's.
    tint = resolvedColor(style.selectedLabelColor)
    var images: [String: UIImage] = [:]
    for (name, vector) in style.icons {
      images[name] = templateImage(vector, size: CGFloat(style.iconSize))
    }
    self.images = images
  }

  private init(tint: Color?, images: [String: UIImage]) {
    self.tint = tint
    self.images = images
  }

  func image(_ name: String?) -> UIImage? { name.flatMap { images[$0] } }
}

extension KarnakTabBadge {
  /// The badge as the tab bar shows it: a count in the device's digits (`999+` above 999), an
  /// empty badge for a dot, or nil for none.
  var text: Text? {
    guard isVisible else { return nil }
    if isDot { return Text(verbatim: "") }
    let count = shownCount.formatted(.number.grouping(.never))
    return Text(verbatim: overflows ? count + "+" : count)
  }
}
