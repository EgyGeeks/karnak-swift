import SwiftUI

extension ScreenModel {
  /// The screen's title as it reads now (translated, a bound one following its data); `nil` before content and for none.
  var title: String? {
    if case .content(let screen) = phase { screen.title } else { nil }
  }
}

extension View {
  /// Sets `title` as the navigation title of the stack entry the view is in, and nothing for `nil`: a screen without a
  /// title leaves the one the app gave. Put it on an empty view of its own, as the presenter does, so the branch it
  /// takes never changes the identity of the screen's content or of the view that runs its lifecycle.
  @ViewBuilder
  func screenNavigationTitle(_ title: String?) -> some View {
    if let title {
      navigationTitle(title)
    } else {
      self
    }
  }
}
