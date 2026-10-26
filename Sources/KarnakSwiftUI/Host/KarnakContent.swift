import KarnakCore
import SwiftUI

/// Level 1, the renderer alone (`docs/integration.md`, Three levels): draws a screen from bundled
/// JSON, with no client, network or cache. Use it for previews, tests and screens that ship in
/// the app.
///
/// ```swift
/// KarnakContent(screenJson: try String(contentsOf: promoURL), themeJson: nil)
/// ```
///
/// `screenJson` is a screen response body and `themeJson` the app's theme, a theme response body (a
/// theme the screen carries is ignored; none draws the baseline theme). A screen that
/// can't be read draws nothing and is logged; the content fills the space it is offered.
/// Colors resolve for the environment's color scheme and layout direction.
public struct KarnakContent: View {
  private let screenJson: String
  private let themeJson: String?

  @StateObject private var resolver = LevelOneResolver()
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.karnakDeviceSizes) private var injectedDevice
  @Environment(\.karnakContainerWidth) private var forcedWidth
  @State private var measuredWidth: CGFloat?

  /// Creates the view for `screenJson`, themed by `themeJson` when given.
  public init(screenJson: String, themeJson: String? = nil) {
    self.screenJson = screenJson
    self.themeJson = themeJson
  }

  /// The resolved screen, or nothing when it can't be read.
  public var body: some View {
    // Until the container is measured the screen resolves as `compact`;
    // ``karnakContainerWidth(_:)`` forces a width, for previews of the other classes.
    let width = forcedWidth ?? measuredWidth.map(Double.init) ?? 0
    let environment = (injectedDevice ?? DeviceSizes.current).environment(
      colorScheme: colorScheme, layoutDirection: layoutDirection, width: width)
    Group {
      if let screen = resolver.screen(screenJson, themeJson, environment) {
        ResolvedScreenView(screen: screen, onAction: { _ in })
      }
    }
    .measuringContainerWidth($measuredWidth)
  }
}

/// Resolves a level-1 screen once per input, so redraws don't resolve it again.
@MainActor
final class LevelOneResolver: ObservableObject {
  private struct Inputs {
    let screenJson: String
    let themeJson: String?
    let environment: ScreenEnvironment

    func matches(_ other: Inputs) -> Bool {
      screenJson == other.screenJson && themeJson == other.themeJson
        && environment.isEqual(other.environment)
    }
  }

  private var inputs: Inputs?
  private var resolved: ResolvedScreen?

  func screen(_ json: String, _ theme: String?, _ env: ScreenEnvironment) -> ResolvedScreen? {
    let requested = Inputs(screenJson: json, themeJson: theme, environment: env)
    if let inputs, inputs.matches(requested) { return resolved }
    let state = ScreenResolversKt.screenResolver(debug: false, log: RendererDiagnostics.systemLog)
      .resolve(screenJson: json, themeJson: theme, environment: env)
    inputs = requested
    resolved = (state as? ScreenStateContent)?.screen
    return resolved
  }
}
