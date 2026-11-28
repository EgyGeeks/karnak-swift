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

/// What a screen shows while it needs a signed-in person and the app has said nobody is, when neither its
/// entry nor the default of ``KarnakConfiguration/screenStates(_:)`` draws a sign-in view: a heading, the
/// screen's reason when the project maps it, and a "Sign in" button.
///
/// The texts are the project's strings `common.sign_in_title` (the heading), `common.sign_in` (the button) and
/// `common.sign_in_reason.<reason>` (the line under the heading) from the string table the client holds, in the
/// user's language. The heading and the button fall back to the host's own string catalog: localize
/// "Sign in to continue" and "Sign in" there. A reason the table doesn't map shows nothing: the code is never
/// drawn. For VoiceOver it is one heading and one button, the reason read as the button's hint.
public struct KarnakSignInRequiredView: View {
  private let reason: String?
  private let signIn: () -> Void
  @Environment(\.karnakResources) private var resources

  /// Creates the placeholder for a screen locked for `reason` (its `authReason`, or `nil`); `signIn` asks the
  /// app to sign in.
  public init(reason: String?, signIn: @escaping () -> Void) {
    self.reason = reason
    self.signIn = signIn
  }

  /// The heading, the mapped reason and the button, centered.
  public var body: some View {
    let why = reason.flatMap { resources.mappedText("common.sign_in_reason.\($0)") }
    VStack(spacing: 12) {
      resources.text("common.sign_in_title", fallback: "Sign in to continue")
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      if let why {
        // Read as the button's hint, so it is no element of its own.
        Text(verbatim: why)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      Button(action: signIn) { resources.text("common.sign_in", fallback: "Sign in") }
        .accessibilityHint(why ?? "")
    }
    .multilineTextAlignment(.center)
    .padding(.horizontal)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

extension KarnakSwiftResources {
  /// The project's text for `key`, or `fallback` from the host's string catalog when the table
  /// has none (``string(_:args:)`` answers the key itself for a key it doesn't hold).
  func text(_ key: String, fallback: LocalizedStringKey) -> Text {
    mappedText(key).map { Text(verbatim: $0) } ?? Text(fallback)
  }

  /// The project's text for `key`, or `nil` when the table has none.
  func mappedText(_ key: String) -> String? {
    let value = string(key)
    return value == key ? nil : value
  }
}
