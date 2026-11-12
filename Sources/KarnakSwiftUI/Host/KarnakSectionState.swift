import Combine
import Observation
import SwiftUI

/// A section of a native screen whose state the host keeps (ADR 0028, D1, "Sections in a native
/// screen"): ``open()`` opens the section's document and starts its data sources, and
/// ``KarnakSection`` only draws it (and opens it, when nothing did first). It lives as long as its owner, not as long as a lazy list row,
/// so a section that scrolls out and back shows its values at once, and its sources load when the
/// screen opens, not when the row first appears.
///
/// It is `@Observable`: hold it where the screen's state lives, with `@State`. Creating it costs nothing, because
/// `State(initialValue:)` builds one on every `init` of the holding view and keeps only the first; call ``open()``
/// when the screen appears:
///
/// ```swift
/// struct HomeView: View {
///   @State private var promos: KarnakSectionState
///   init(client: KarnakSwiftClient) {
///     _promos = State(initialValue: KarnakSectionState("home_promos", client: client))
///   }
///   var body: some View {
///     List { KarnakSection(state: promos) }
///       .onAppear { promos.open() }
///   }
/// }
/// ```
///
/// Releasing the state closes the section (queued and running sources are cancelled), and
/// ``close()`` does it at once.
@Observable
@MainActor
public final class KarnakSectionState {
  let id: String
  let model = ScreenModel()
  private let params: [String: Any]
  private let opener: any ScreenOpening
  private var isOpen = false

  /// Prepares section `id` with `params` (JSON values only) on `client`; nothing opens until ``open()`` or a
  /// ``KarnakSection`` that shows it. The section draws for the device's color scheme and direction until a
  /// ``KarnakSection`` shows it and says its own size.
  public convenience init(_ id: String, params: [String: Any] = [:], client: KarnakSwiftClient) {
    self.init(id, params: params, opener: client)
  }

  init(_ id: String, params: [String: Any], opener: any ScreenOpening) {
    self.id = id
    self.params = params
    self.opener = opener
  }

  /// Opens the section's document and starts its data sources. Calling it again does nothing.
  public func open() {
    // Without a view the device's own traits are all there is.
    let dark = UITraitCollection.current.userInterfaceStyle == .dark
    let rtl = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft
    open(colorScheme: dark ? .dark : .light, layoutDirection: rtl ? .rightToLeft : .leftToRight)
  }

  /// Opens with the scheme and direction the host's SwiftUI environment resolves (an app's own
  /// `.environment(\.colorScheme, …)` included), so sources that bind `context.colorScheme` load once for it.
  func open(colorScheme: ColorScheme, layoutDirection: LayoutDirection) {
    guard !isOpen else { return }
    isOpen = true
    let environment = DeviceSizes.current.environment(
      colorScheme: colorScheme, layoutDirection: layoutDirection, width: 0)
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
/// the section, and follows the host stack and the app's lifecycle. It opens the section when nothing has, and
/// never closes it.
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
    // swiftlint:disable:next redundant_discardable_let
    let _ = state.open(colorScheme: colorScheme, layoutDirection: layoutDirection)
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
