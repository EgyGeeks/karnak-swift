import Combine
import KarnakCore
import SwiftUI

/// What ``KarnakScreen`` and ``KarnakSection`` share: opens the screen for the environment's
/// client and shows the loading, content or error view for its state.
///
/// A screen lives as long as the view's identity, which SwiftUI marks with the `@State`s it
/// keeps (``ViewLifetime``): a screen that is only hidden (covered in a `NavigationStack`, in another
/// `TabView` tab) keeps its content, its pending effects and its scroll position, and closes
/// when its view is gone for good (`docs/integration.md`, State ownership). A section closes
/// when it disappears, as a part of a lazy list does.
struct ScreenPresenter<Loading: View, Failure: View>: View {
  let screenId: String
  let params: [String: Any]
  /// Whether the content fills the space it is offered (a screen) or takes only its own size
  /// (a section).
  let fillsSpace: Bool
  /// Whether the screen closes when its view disappears (a section) instead of when its view is
  /// gone for good (a screen).
  var closesWhenHidden = false
  /// The host-stack entry the screen is, when it is one: it stays open while covered and
  /// closes when its view is gone.
  var entry: ScreenEntry?
  /// Who hears how the screen ended (`KarnakScreen(onFinish:)`); makes the screen an entry of its
  /// own when it has no ``entry``.
  var onFinish: ((_ outcome: String, _ result: [String: Any]) -> Void)?
  /// Who hears, once per screen opened, that it shows what it is going to show (`KarnakScreen.onContentReady`).
  var onContentReady: (@MainActor () -> Void)?
  /// The call's own loading and error views, which win over the registered ones; `nil` when it gave none.
  let loading: (() -> Loading)?
  let failure: ((KarnakScreenError, _ retry: @escaping () -> Void) -> Failure)?
  /// The SDK's own views, the last choice.
  let sdkViews: SdkScreenViews

  @State private var model = ScreenModel()
  /// Ends with the view's identity, and stops the model then (``ViewLifetime``).
  @State private var lifetime = ViewLifetime()
  @Environment(\.karnakOpener) private var opener
  @Environment(\.karnakScreenStates) private var screenStates
  @Environment(\.karnakHostCallbacks) private var hostCallbacks
  @Environment(\.karnakStack) private var stackLevel
  @Environment(\.karnakScreenObserver) private var screenObserver
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.karnakDeviceSizes) private var injectedDevice
  @Environment(\.karnakContainerWidth) private var forcedWidth
  @State private var measuredWidth: CGFloat?

  init(
    screenId: String, params: [String: Any], fillsSpace: Bool, closesWhenHidden: Bool = false,
    entry: ScreenEntry? = nil,
    onFinish: ((_ outcome: String, _ result: [String: Any]) -> Void)? = nil,
    onContentReady: (@MainActor () -> Void)? = nil,
    loading: (() -> Loading)?,
    failure: ((KarnakScreenError, _ retry: @escaping () -> Void) -> Failure)?,
    sdkViews: SdkScreenViews
  ) {
    self.screenId = screenId
    self.params = params
    self.fillsSpace = fillsSpace
    self.closesWhenHidden = closesWhenHidden
    self.entry = entry
    self.onFinish = onFinish
    self.onContentReady = onContentReady
    self.loading = loading
    self.failure = failure
    self.sdkViews = sdkViews
  }

  var body: some View {
    let ownEntry = onFinish != nil && entry == nil
    let resolved = resolvedEntry(ownEntry: ownEntry)
    let key = SessionKey(
      screenId: screenId, params: params, opener: opener, entryId: resolved?.id)
    let width = forcedWidth ?? measuredWidth.map(Double.init)
    let environment = screenEnvironment(width: width ?? 0)
    // The model keeps the latest hooks (no published state changes), like ActionSink's handler.
    // A result builder allows a declaration here, not a bare call.
    // swiftlint:disable:next redundant_discardable_let
    let _ = model.updateHostCallbacks(
      hostCallbacks.withDefault(navigation: stackLevel.map(karnakNavigationTarget)),
      onFinish: onFinish, onContentReady: onContentReady)
    panes {
      phaseView
      // The lifecycle hangs on a view of its own: a phase that draws nothing, such as a
      // section's default loading view, is no view at all, and SwiftUI never runs its tasks.
      Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
        // The screen opens once its container is measured, so the first load carries the right
        // size classes and the first frame is the right branch.
        .task(id: StartKey(key: key, measured: width != nil)) {
          guard width != nil else { return }
          lifetime.model = model
          screenObserver?(model)
          model.savedFormsSlot = savedFormsSlot
          model.start(
            key, opener: opener, params: params, environment: environment, entry: resolved,
            reportsRemoval: ownEntry)
          if loading == nil { screenStates.reportFallback(screenId) }
        }
        .task(
          id: ScreenEnvironmentKey(
            colorScheme: colorScheme, layoutDirection: layoutDirection,
            reach: environment.sizeReach.reachableHeader, sizeClass: environment.sizeClass.wire)
        ) {
          model.setEnvironment(environment)
        }
        .onAppear {
          model.setShown(true)
        }
        // A hidden screen only leaves the foreground; `lifetime` stops it when the view is gone.
        .onDisappear {
          if closesWhenHidden && !keepsOpenWhenCovered {
            model.stop()
          } else {
            model.setShown(false)
          }
        }
        .onReceive(AppLifecycle.isActive) { model.setAppActive($0) }
        .onReceive(AppLifecycle.isFrontmost) { model.keepForms(leaving: !$0) }
        .onReceive(coverage) { model.setCovered($0) }
    }
    .presentingEffects(model.effects, hasPanes: fillsSpace)
  }

  /// The screen's views, with its detail pane when it is a screen and not a section: a section's
  /// detail is a full-screen cover.
  @ViewBuilder
  private func panes<Views: View>(@ViewBuilder _ views: @escaping () -> Views) -> some View {
    let measured = ZStack(content: views).measuringContainerWidth($measuredWidth)
    if fillsSpace {
      DetailPanes(effects: model.effects, environment: screenEnvironment(width:)) { measured }
    } else {
      measured
    }
  }

  /// Where the screen's form state is kept for a process that replaces this one; nil for a screen no new process
  /// opens under the same name (``SavedFormsKey/names(fullScreen:isEntry:inHostStack:)``).
  private var savedFormsSlot: SavedFormsSlot? {
    let fullScreen = fillsSpace && !closesWhenHidden
    let named = SavedFormsKey.names(
      fullScreen: fullScreen, isEntry: entry != nil, inHostStack: stackLevel != nil)
    guard named else { return nil }
    let name = SavedFormsKey.name(
      scope: opener?.savedStateScope ?? "", screen: screenId, params: params, entry: entry?.id)
    return SavedFormsSlot(store: .shared, name: name)
  }

  /// Whether an entry of the host stack lies above the screen, as the stack changes.
  private var coverage: AnyPublisher<Bool, Never> { stackCoverage(stackLevel) }

  /// The entry the screen opens as: the one it was given, or its own when its caller waits for
  /// an outcome. Either hears the outcome through `onFinish`.
  private func resolvedEntry(ownEntry: Bool) -> ScreenEntry? {
    let receiver: ((String, [String: Any]) -> Void)? =
      onFinish == nil ? entry?.receiver : { [weak model] in model?.finishHandler?($0, $1) }
    guard let id = entry?.id ?? (ownEntry ? model.ownEntryId : nil) else { return nil }
    return ScreenEntry(id: id, receiver: receiver)
  }

  /// A section that is an entry, or sits below one, is covered by a push without being left: it
  /// stays open, so the `onFinish` of the screens above it finds it. It closes when its view is
  /// gone for good.
  private var keepsOpenWhenCovered: Bool {
    if entry != nil || onFinish != nil { return true }
    return stackLevel.map { $0.stack.isCovered(at: $0.depth) } ?? false
  }

  private var phaseView: some View {
    ScreenPhaseView(
      model: model, screenId: screenId, fillsSpace: fillsSpace, loading: loading, failure: failure,
      sdkViews: sdkViews)
  }

  /// The environment for a container `width` points wide on this device.
  private func screenEnvironment(width: Double) -> ScreenEnvironment {
    (injectedDevice ?? DeviceSizes.current).environment(
      colorScheme: colorScheme, layoutDirection: layoutDirection, width: width)
  }
}

struct ScreenEnvironmentKey: Equatable {
  let colorScheme: ColorScheme
  let layoutDirection: LayoutDirection
  let reach: String
  let sizeClass: String
}

private struct StartKey: Equatable {
  let key: SessionKey
  let measured: Bool
}
