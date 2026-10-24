import Combine
import SwiftUI

/// A section of a native screen whose state the host keeps (ADR 0028, D1, "Sections in a native
/// screen"): creating it opens the section's document and starts its data sources, and
/// ``KarnakSection`` only draws it. It lives as long as its owner, not as long as a lazy list row,
/// so a section that scrolls out and back shows its values at once, and its sources load when the
/// screen opens, not when the row first appears.
///
/// Hold it where the screen's state lives, with `@StateObject` (iOS 16 has no `@Observable`):
///
/// ```swift
/// struct HomeView: View {
///   @StateObject private var promos: KarnakSectionState
///   init(client: KarnakSwiftClient) {
///     _promos = StateObject(wrappedValue: KarnakSectionState("home_promos", client: client))
///   }
///   var body: some View {
///     List { KarnakSection(state: promos) }
///   }
/// }
/// ```
///
/// Releasing the state closes the section (queued and running sources are cancelled), and
/// ``close()`` does it at once.
@MainActor
public final class KarnakSectionState: ObservableObject {
  let id: String
  let model = ScreenModel()

  /// Opens section `id` with `params` (JSON values only) on `client`. The section draws for the
  /// device's color scheme and direction until a ``KarnakSection`` shows it and says its own size.
  public convenience init(_ id: String, params: [String: Any] = [:], client: KarnakSwiftClient) {
    self.init(id, params: params, opener: client)
  }

  init(_ id: String, params: [String: Any], opener: any ScreenOpening) {
    self.id = id
    // The device's own traits, so sources that bind `context.colorScheme` load once for the right one.
    let dark = UITraitCollection.current.userInterfaceStyle == .dark
    let rtl = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft
    let environment = DeviceSizes.current.environment(
      colorScheme: dark ? .dark : .light, layoutDirection: rtl ? .rightToLeft : .leftToRight,
      width: 0)
    model.start(
      SessionKey(screenId: id, params: params, opener: opener), opener: opener, params: params,
      environment: environment)
  }

  /// Cancels the section's queued and running sources and stops it. Calling it twice is fine.
  public func close() {
    model.stop()
  }
}

/// Draws a ``KarnakSectionState``: reports the container's width, color scheme and direction to
/// the section, and follows the host stack and the app's lifecycle. It never opens or closes the
/// section.
struct HoistedSectionView<Loading: View, Failure: View>: View {
  let state: KarnakSectionState
  let loading: (() -> Loading)?
  let failure: ((KarnakScreenError, _ retry: @escaping () -> Void) -> Failure)?

  @Environment(\.karnakScreenStates) private var screenStates
  @Environment(\.karnakHostCallbacks) private var hostCallbacks
  @Environment(\.karnakStack) private var stackLevel
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.karnakDeviceSizes) private var injectedDevice
  @Environment(\.karnakContainerWidth) private var forcedWidth
  @State private var measuredWidth: CGFloat?

  var body: some View {
    let model = state.model
    let width = forcedWidth ?? measuredWidth.map(Double.init)
    let environment = (injectedDevice ?? DeviceSizes.current).environment(
      colorScheme: colorScheme, layoutDirection: layoutDirection, width: width ?? 0)
    // swiftlint:disable:next redundant_discardable_let
    let _ = model.updateHostCallbacks(
      hostCallbacks.withDefault(navigation: stackLevel.map(karnakNavigationTarget)))
    ZStack {
      ScreenPhaseView(
        model: model, screenId: state.id, fillsSpace: false, loading: loading, failure: failure,
        sdkViews: .section)
      // The lifecycle hangs on a view of its own: a phase that draws nothing is no view at all.
      Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
        .task(
          id: ScreenEnvironmentKey(
            colorScheme: colorScheme, layoutDirection: layoutDirection,
            reach: environment.sizeReach.reachableHeader, sizeClass: environment.sizeClass.wire)
        ) {
          // The size class is known once the container is measured.
          if width != nil { model.setEnvironment(environment) }
        }
        .onAppear {
          if loading == nil { screenStates.reportFallback(state.id) }
          model.setShown(true)
        }
        // Hidden is not closed: the state's owner closes the section.
        .onDisappear { model.setShown(false) }
        .onReceive(AppLifecycle.isActive) { model.setAppActive($0) }
        .onReceive(stackCoverage(stackLevel)) { model.setCovered($0) }
    }
    .measuringContainerWidth($measuredWidth)
    .presentingEffects(model.effects)
  }
}
