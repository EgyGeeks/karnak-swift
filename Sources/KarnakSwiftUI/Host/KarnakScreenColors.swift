import KarnakCore
import SwiftUI

/// The project's colors for the part of the app that draws around its screens, such as a frame, a
/// tab bar or a status area (`docs/renderer-contract.md`, Theme of the shown screen). They come from
/// the theme of the screen that is shown, the content of the host's stack: a ``KarnakScreen`` or a
/// ``KarnakFlow`` step, never an overlay (a sheet or a modal) or a section. They follow back
/// navigation with no reload;
/// with no screen shown they come from the environment's default theme, never from the theme of a
/// screen that was loaded last. Read it in a view below
/// ``SwiftUI/View/karnakHost(_:onNavigate:onOpenUrl:onCustom:onTrack:onDismiss:onOpenScreen:onNavigation:)``:
///
/// ```swift
/// struct AppFrame<Content: View>: View {
///   @Environment(\.karnakScreenColors) private var colors
///   @ViewBuilder var content: () -> Content
///   var body: some View {
///     content()
///       .background(colors.color("background", fallback: .white))
///       .tint(colors.color("onBackground"))
///   }
/// }
/// ```
///
/// The value is cheap to copy and safe from any thread.
public struct KarnakScreenColors: Sendable, Equatable {
  private let shown: ShownTheme?
  private let resources: KarnakSwiftResources

  init(shown: ScreenTheme?, resources: KarnakSwiftResources) {
    self.shown = shown.map(ShownTheme.init)
    self.resources = resources
  }

  /// The revision of the theme of the screen that is shown (`khan@2`), or `nil` when no screen is
  /// shown and the colors are the default theme's.
  public var themeRevision: String? { shown?.theme.revision }

  /// The color `name` (`background`, `onBackground`, a custom name) as a dynamic `Color` that follows
  /// the system's light and dark appearance, from the theme of the screen that is shown; with none
  /// shown, from the environment's default theme. `nil` when the name is unknown, or before the
  /// resources have loaded and no screen is shown.
  public func color(_ name: String) -> Color? {
    guard let shown else { return resources.color(name) }
    let theme = shown.theme
    return DynamicColor.make { theme.color(name: name, mode: $0) }
  }

  /// ``color(_:)``, or `fallback` when it is `nil`.
  public func color(_ name: String, fallback: Color) -> Color {
    color(name) ?? fallback
  }

  public static func == (left: KarnakScreenColors, right: KarnakScreenColors) -> Bool {
    // A theme revision is immutable: two reports of one revision are one set of colors.
    left.themeRevision == right.themeRevision && left.resources == right.resources
  }

  /// The colors of nothing: every color is `nil`.
  static let unavailable = KarnakScreenColors(shown: nil, resources: .unavailable)
}

/// A shown theme, shared as a value: the Kotlin theme is immutable.
private final class ShownTheme: @unchecked Sendable {
  let theme: ScreenTheme
  init(_ theme: ScreenTheme) { self.theme = theme }
}

extension EnvironmentValues {
  /// The colors of the screen that is shown below `.karnakHost`, drawn again when it changes; the
  /// default theme's with none shown. Outside a host every color is `nil`.
  @Entry public var karnakScreenColors: KarnakScreenColors = .unavailable

  /// Where full screens report their theme; `nil` outside `.karnakHost`.
  @Entry var karnakShownThemes: KarnakShownThemes?
}

/// Gives the views below `.karnakHost` the registry of shown themes and the colors read from it.
struct KarnakShownThemeHost: ViewModifier {
  @StateObject private var themes = KarnakShownThemes()
  @Environment(\.karnakResources) private var resources

  func body(content: Content) -> some View {
    content
      .environment(\.karnakShownThemes, themes)
      .environment(
        \.karnakScreenColors, KarnakScreenColors(shown: themes.current, resources: resources))
  }
}
