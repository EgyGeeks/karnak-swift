import Foundation
import KarnakCore
import SwiftUI

/// The `modal` or `sheet` a tab bar's action item opened over the whole app (ADR 0047, D10;
/// `KarnakNavigationModule.runTabAction`), for the tab integrations (`KarnakNavigation`): ``show(_:)``
/// it, and apply ``SwiftUICore/View/karnakShellOverlays(_:)`` to the view that holds the bar. It is
/// drawn as a screen's overlay is (a bottom sheet or a full-screen cover over a `NavigationStack`),
/// with the host's hooks. One is open at a time: another ``show(_:)`` closes the one before.
@MainActor
package final class ShellOverlays: ObservableObject {
  @Published private(set) var current: OverlayModel?
  /// The engine's side of ``current``, closed when it goes.
  private var open: TabOverlay?
  /// The factory of the models that follow each entry's screen, with the host's hooks and environment.
  fileprivate let screens = ScreenModel()
  /// The background of an open `sheet` for the color scheme (dark when true): the theme's surface as the engine's ARGB.
  /// The tab integration sets it from its client; nil, or a nil answer, keeps the system's sheet background.
  package var surface: (@MainActor (_ dark: Bool) -> Int32?)?

  package init() {}

  /// Whether an overlay is open now.
  package var isOpen: Bool { current != nil }

  /// Shows `overlay`; nothing for nil, an action item that ran on a tab's stack.
  package func show(_ overlay: TabOverlay?) {
    guard let overlay else { return }
    close()
    let presentation = KarnakPresentation(overlay.presentation)
    open = overlay
    let request = OverlayRequest(
      id: "karnak-tab-\(UUID().uuidString)", generation: 0, presentation: presentation,
      stack: ControllerStack(overlay.stack, session: { ControllerSession($0) }))
    let model = OverlayModel(request, makeModel: screens.effects.openOverlayEntry)
    model.onEnded = { [weak self, weak model] in
      guard let self, let model, self.current === model else { return }
      self.close()
    }
    current = model
    model.start()
  }

  /// Ends the open overlay, if any: its entries leave as cancelled.
  package func close() {
    let overlay = open
    open = nil
    current?.stop()
    current = nil
    overlay?.close()
  }

  fileprivate func dismissedByUser() {
    current?.dismissedByUser()
  }

  fileprivate func update(callbacks: KarnakHostCallbacks, environment: ScreenEnvironment) {
    screens.updateHostCallbacks(callbacks)
    screens.setEnvironment(environment)
  }
}

extension View {
  /// Presents what `overlays` shows over this view (``ShellOverlays``): a `sheet` as a bottom sheet,
  /// a `modal` as a full-screen cover. Apply it to the tab view, inside the `karnakHost`.
  package func karnakShellOverlays(_ overlays: ShellOverlays) -> some View {
    modifier(ShellOverlayPresenter(overlays: overlays))
  }
}

private struct ShellOverlayPresenter: ViewModifier {
  @ObservedObject var overlays: ShellOverlays
  @Environment(\.karnakHostCallbacks) private var callbacks
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.karnakDeviceSizes) private var injectedDevice
  @State private var width: CGFloat?

  func body(content: Content) -> some View {
    // The model keeps the latest hooks and environment (no published state changes), as the screens do.
    // swiftlint:disable:next redundant_discardable_let
    let _ = overlays.update(callbacks: callbacks, environment: environment)
    content
      .measuringContainerWidth($width)
      .sheet(item: overlay(.sheet)) { presented in
        ContainedStackView(overlay: presented, fillsSpace: false)
          .presentationDragIndicator(.visible)
          .sheetSurface(overlays.surface?(colorScheme == .dark))
      }
      .fullScreenCover(item: overlay(.modal)) { presented in
        ContainedStackView(overlay: presented, fillsSpace: true)
      }
  }

  private var environment: ScreenEnvironment {
    (injectedDevice ?? DeviceSizes.current).environment(
      colorScheme: colorScheme, layoutDirection: layoutDirection, width: Double(width ?? 0))
  }

  private func overlay(_ presentation: KarnakPresentation) -> Binding<OverlayModel?> {
    Binding(
      get: { overlays.current.flatMap { $0.presentation == presentation ? $0 : nil } },
      set: { if $0 == nil { overlays.dismissedByUser() } })
  }
}
