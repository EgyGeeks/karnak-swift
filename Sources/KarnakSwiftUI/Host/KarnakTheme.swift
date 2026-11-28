import KarnakCore
import SwiftUI
import UIKit

/// The project's theme for the app's own views (`docs/integration.md`, Match your native screens to the theme): its
/// colors, typography, spacing, radii and elevation by the project's token names, in the environment's color scheme,
/// so a native view matches the Karnak screens beside it. Read it with `@Environment(\.karnakTheme)` below
/// `.karnakHost`:
///
/// ```swift
/// @Environment(\.karnakTheme) private var theme
///
/// var body: some View {
///   Text("Total")
///     .karnakTextStyle("h1")
///     .foregroundStyle(theme?.color("commerce") ?? .accentColor)
/// }
/// ```
///
/// Every lookup is `nil` for a name the theme lacks, so the app falls back to its own value; a lookup does no I/O.
/// Two are equal when they are the same theme revision in the same scheme and Dynamic Type size with the same theme
/// faces registered, so a view that reads it draws again when the user's text size changes or a face its text style
/// uses lands.
public struct KarnakTheme: Equatable, @unchecked Sendable {
  // The engine's theme is immutable and safe to share between threads; the registry is read on the main actor only.
  private let theme: ScreenTheme
  private let fonts: ThemeFontRegistry?
  /// The registry's count of registered faces when this value was made (``ThemeFontRegistry/registered``).
  private let fontsRegistered: Int
  /// The environment's Dynamic Type size where this value was read: what ``textStyle(_:dynamicTypeSize:)`` scales to.
  private let dynamicTypeSize: DynamicTypeSize

  /// The theme revision (`docs/theme.md`), the same on every device given that release.
  public var revision: String { theme.revision }
  /// Whether the colors are the dark mode's: the environment's `colorScheme`.
  public let isDark: Bool

  init(
    _ theme: ScreenTheme, isDark: Bool, dynamicTypeSize: DynamicTypeSize = .large,
    fonts: ThemeFontRegistry? = nil, fontsRegistered: Int = 0
  ) {
    self.theme = theme
    self.isDark = isDark
    self.dynamicTypeSize = dynamicTypeSize
    self.fonts = fonts
    self.fontsRegistered = fontsRegistered
  }

  private var mode: ColorMode { isDark ? .dark : .light }

  /// The color `name`: a semantic color (`surface`, `onSurface`), a palette color or a `#RRGGBB` / `#AARRGGBB` hex,
  /// in the order a node resolves a color in. A required semantic color the theme lacks is the SDK's baseline's.
  public func color(_ name: String) -> Color? {
    theme.color(name: name, mode: mode).map(resolvedColor)
  }

  /// The spacing token `name` in points (`docs/theme.md`, Spacing and radii).
  public func spacing(_ name: String) -> CGFloat? {
    theme.spacing(name: name).map { points(dp: $0.floatValue) }
  }

  /// The radius token `name` in points (`docs/theme.md`, Spacing and radii); a pill is a large value, such as `9999`.
  public func radius(_ name: String) -> CGFloat? {
    theme.radius(name: name).map { points(dp: $0.floatValue) }
  }

  /// The shadow layers of elevation token `name` (`docs/theme.md`, Elevation), the first drawn lowest; a layer whose
  /// color the theme lacks takes its `shadow` color.
  public func elevation(_ name: String) -> [KarnakThemeShadow]? {
    theme.elevation(name: name, mode: mode)?.map(KarnakThemeShadow.init)
  }

  /// The typography token `name` as a screen draws it, scaled by Dynamic Type as Karnak text is: at the environment's
  /// size where the theme was read, or at `dynamicTypeSize` when given. It has the theme's face once it is
  /// registered, and the system font at the same size and weight until then. Prefer
  /// ``SwiftUI/View/karnakTextStyle(_:)``, which applies it and draws again when the face lands. `body` is required,
  /// so a theme without it has the baseline's.
  @MainActor
  public func textStyle(
    _ name: String, dynamicTypeSize: DynamicTypeSize? = nil
  ) -> KarnakTextStyle? {
    guard let style = theme.textStyle(name: name) else { return nil }
    let traits = UITraitCollection(
      preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize ?? self.dynamicTypeSize))
    return KarnakTextStyle(style, traits: traits, postScriptName: fonts?.postScriptName(for:))
  }

  public static func == (lhs: KarnakTheme, rhs: KarnakTheme) -> Bool {
    lhs.theme.revision == rhs.theme.revision && lhs.isDark == rhs.isDark
      && lhs.dynamicTypeSize == rhs.dynamicTypeSize && lhs.fonts === rhs.fonts
      && lhs.fontsRegistered == rhs.fontsRegistered
  }
}

/// A typography token of ``KarnakTheme`` resolved at one Dynamic Type size, as a Karnak `text` node starts from it.
public struct KarnakTextStyle: Equatable, Sendable {
  /// The font: the theme's face when it is registered, else the system font at the same size and weight.
  public let font: Font
  /// The font size in points, scaled for Dynamic Type.
  public let size: CGFloat
  /// The height of one line in points, scaled for Dynamic Type; nil for the font's own.
  public let lineHeight: CGFloat?
  /// The letter spacing in points (`tracking`).
  public let tracking: CGFloat
  /// The space SwiftUI's `lineSpacing` takes so each line is ``lineHeight`` tall; 0 without one.
  let lineSpacing: CGFloat

  init(
    _ style: ThemeTextStyle, traits: UITraitCollection,
    postScriptName: ((ResolvedFontFace) -> String?)?
  ) {
    let font = style.font
    let name = font.face.flatMap { postScriptName?($0) }
    let points = textPoints(sp: font.size, traits: traits)
    self.font = resolvedFont(font, scaledPoints: points, postScriptName: name)
    size = points
    tracking = KarnakSwiftUI.tracking(em: font.letterSpacing, fontPoints: points)
    let lineHeight = style.lineHeight.map { textPoints(sp: $0.floatValue, traits: traits) }
    self.lineHeight = lineHeight
    lineSpacing = lineHeight.map { max(0, $0 - naturalLineHeight(name, points)) } ?? 0
  }
}

/// One shadow layer of a theme's elevation token (``KarnakTheme/elevation(_:)``), as CSS's `box-shadow` reads one.
public struct KarnakThemeShadow: Equatable, Sendable {
  /// How far the shadow is moved from the shape, in points; `y` grows downward.
  public let x: CGFloat
  /// See ``x``.
  public let y: CGFloat
  /// The blur radius in points.
  public let blur: CGFloat
  /// How much the shadow grows (or, negative, shrinks) before it is blurred, in points.
  public let spread: CGFloat
  /// The shadow's color, with its alpha.
  public let color: Color

  init(_ shadow: KarnakShadow) {
    x = points(dp: shadow.x)
    y = points(dp: shadow.y)
    blur = points(dp: shadow.blur)
    spread = points(dp: shadow.spread)
    color = resolvedColor(shadow.color)
  }
}

extension EnvironmentValues {
  /// The project's theme in this environment's color scheme (``KarnakTheme``), below `.karnakHost`; nil outside one
  /// and while the device holds no project theme (a fresh install offline, with no bundled snapshot), when the app
  /// uses its own values. The first read loads the theme off the main thread as a first screen would, which fixes it
  /// for the session: a theme released later applies from the next launch. Views that read it draw again when the
  /// client holds another theme or the color scheme changes. It is read-only: the app can't put a screen on another
  /// theme.
  public var karnakTheme: KarnakTheme? {
    karnakThemeState.read(isDark: colorScheme == .dark, dynamicTypeSize: dynamicTypeSize)
  }
}

extension View {
  /// Applies the theme's typography token `name` as a Karnak `text` node does: its font (the theme's face once
  /// registered), tracking and line height, at the environment's Dynamic Type size. Without a theme, or for a name
  /// the theme lacks, it changes nothing, so the view keeps the app's own style.
  public func karnakTextStyle(_ name: String) -> some View {
    modifier(KarnakTextStyleModifier(name: name))
  }
}

private struct KarnakTextStyleModifier: ViewModifier {
  let name: String
  @Environment(\.karnakTheme) private var theme

  func body(content: Content) -> some View {
    if let style = theme?.textStyle(name) {
      content
        .font(style.font)
        .tracking(style.tracking)
        .lineSpacing(style.lineSpacing)
        .padding(.vertical, style.lineSpacing / 2)
    } else {
      content
    }
  }
}
