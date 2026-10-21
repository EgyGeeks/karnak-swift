import SwiftUI

/// What ``KarnakScreen`` shows while its first load runs: a centered spinner.
public struct KarnakLoadingView: View {
  /// Creates the spinner.
  public init() {}

  /// A spinner filling the space, named "Loading" for VoiceOver.
  public var body: some View {
    ProgressView()
      .accessibilityLabel(Text("Loading"))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// What ``KarnakScreen`` shows when the screen couldn't be loaded and there is nothing to show:
/// a message and a retry button.
///
/// The texts are the project's strings `common.error_title` (the message) and `common.retry` (the
/// button) from the string table the client holds, in the user's language
/// (``KarnakSwiftResources/string(_:args:)``). A key the table doesn't have, or a table that has
/// not loaded yet, falls back to the host's own string catalog: localize "Something went wrong" and
/// "Retry" there, or pass your own `error` view (`docs/integration.md`, Loading and error views).
/// Showing the view reads ``KarnakSwiftClient/resources``, which starts the strings' first load
/// when nothing has.
public struct KarnakErrorView: View {
  private let retry: (() -> Void)?
  @Environment(\.karnakResources) private var resources

  /// Creates the error view; `retry` loads the screen again.
  public init(retry: @escaping () -> Void) {
    self.retry = retry
  }

  /// A view for a failure that loading again can't fix: the message alone.
  init() {
    retry = nil
  }

  /// The message above a retry button, centered.
  public var body: some View {
    VStack(spacing: 12) {
      resources.text("common.error_title", fallback: "Something went wrong")
      if let retry {
        Button(action: retry) { resources.text("common.retry", fallback: "Retry") }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

extension KarnakSwiftResources {
  /// The project's text for `key`, or `fallback` from the host's string catalog when the table
  /// has none (``string(_:args:)`` answers the key itself for a key it doesn't hold).
  func text(_ key: String, fallback: LocalizedStringKey) -> Text {
    let value = string(key)
    return value == key ? Text(fallback) : Text(verbatim: value)
  }
}
