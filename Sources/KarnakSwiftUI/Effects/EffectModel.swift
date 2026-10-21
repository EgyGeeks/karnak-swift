import Combine
import Foundation
import KarnakCore
import SwiftUI
import UIKit

/// A sheet on screen: its id and the model that follows its child screen.
struct PresentedSheet: Identifiable {
  let id: String
  let model: ScreenModel
}

/// What one screen instance presents: a toast, a dialog and a sheet, one of each at a time, each
/// kind in the order the engine sent it (`docs/renderer-contract.md`, Effects and Dialog
/// lifecycle). An effect waits until the tree it was computed against is on screen, and while the
/// screen is hidden (covered, in another tab) it waits in the model and shows once the screen
/// shows again: it is state with an id, never an event the view could miss. It answers
/// the engine as each effect ends: a toast when its time is up, a sheet when the user closes it,
/// a dialog once it is off screen however it ended.
@MainActor
final class EffectModel: ObservableObject {
  @Published private(set) var toast: ToastRequest?
  @Published private(set) var dialog: DialogRequest?
  @Published private(set) var sheet: PresentedSheet?
  /// The overlay on screen: a stack of the engine's, drawn in its own `NavigationStack`.
  @Published private(set) var overlay: OverlayModel?

  private var pending: [EffectRequest] = []
  private var generation: Int64 = -1
  private var session: (any ScreenSession)?
  private var answeredDialogs: Set<String> = []
  private var blockedUntilClear: Set<Kind> = []
  private var toastTimer: Task<Void, Never>?
  /// Whether the screen is on screen; nothing new is presented while it is hidden.
  private var visible = true
  /// Opens the screen of a sheet for drawing: the owning ``ScreenModel`` sets it, so the child
  /// gets the parent's host hooks and environment.
  var openChild: @MainActor (SheetRequest) -> ScreenModel = { request in
    let child = ScreenModel()
    child.follow(
      request.screen, environment: ScreenEnvironment.make(colorMode: .light, layoutDirection: .ltr))
    return child
  }
  /// Opens the screen of an overlay's entry for drawing, as ``openChild`` does for a sheet.
  var openOverlayEntry: @MainActor (any ScreenSession) -> ScreenModel = { screen in
    let child = ScreenModel()
    child.follow(
      screen, environment: ScreenEnvironment.make(colorMode: .light, layoutDirection: .ltr))
    return child
  }
  private let pause: @Sendable (Int64) async -> Void
  private let announce: @MainActor (String) -> Void

  private enum Kind { case toast, dialog, sheet, overlay }

  /// - Parameters:
  ///   - pause: Waits this many milliseconds; tests pass a shorter one.
  ///   - announce: Tells VoiceOver a toast appeared.
  init(
    pause: @escaping @Sendable (Int64) async -> Void = {
      try? await Task.sleep(for: .milliseconds($0))
    },
    announce: @escaping @MainActor (String) -> Void = { EffectModel.announcer($0) }
  ) {
    self.pause = pause
    self.announce = announce
  }

  /// Where a toast's announcement goes unless a model was given its own: VoiceOver. The
  /// conformance suite replaces it to record what a screen reader is told.
  static var announcer: @MainActor (String) -> Void = EffectModel.announceToVoiceOver

  /// How long a dialog or sheet that just left makes the next one of its kind wait: SwiftUI
  /// can't present one while the previous is still animating away.
  static let presentationGap: Int64 = 400

  /// Answers the engine through `session` from now on.
  func bind(_ session: any ScreenSession) {
    self.session = session
  }

  /// Takes an effect from the engine.
  func offer(_ effect: EffectRequest) {
    if case .dismiss(let id) = effect {
      close(id: id)
    } else {
      pending.append(effect)
      promote()
    }
  }

  /// The screen became visible (`true`) or hidden (`false`): what waits is presented once it shows.
  func setVisible(_ visible: Bool) {
    guard visible != self.visible else { return }
    self.visible = visible
    if visible { promote() }
  }

  /// The generation of the tree on screen: effects computed against a later one wait.
  func setGeneration(_ generation: Int64) {
    guard generation > self.generation else { return }
    self.generation = generation
    promote()
  }

  /// Closes what is presented and forgets what waits, as the screen going away does. The engine
  /// closes its side.
  func reset() {
    toastTimer?.cancel()
    toastTimer = nil
    toast = nil
    dialog = nil
    closeSheet()
    closeOverlay()
    pending = []
    answeredDialogs = []
    blockedUntilClear = []
    // The next instance counts its own generations from the start.
    generation = -1
    session = nil
  }

  /// A dialog button was activated: the engine answers with a dismiss that removes the dialog.
  func choose(_ choice: DialogChoice) {
    guard let dialog, answeredDialogs.insert(dialog.id).inserted else { return }
    session?.dialogButton(dialog.id, choice)
  }

  /// The system took the dialog away. Without a button before it, that is a cancellation.
  /// The check waits one turn, so a button's action runs first whichever order SwiftUI uses.
  func dialogWentAway() {
    guard let gone = dialog else { return }
    Task { [weak self] in
      guard let self, let current = self.dialog, current.id == gone.id,
        !self.answeredDialogs.contains(gone.id)
      else { return }
      self.close(id: gone.id)
    }
  }

  /// The user closed the sheet (swipe or drag indicator).
  func sheetClosedByUser(id: String) {
    guard sheet?.id == id else { return }
    closeSheet()
    session?.effectDismissed(id)
    blockThenPromote(.sheet)
  }

  /// The user dismissed the overlay (swiped the sheet down): the engine closes the stack, and
  /// the overlay ends with it.
  func overlayClosedByUser(id: String) {
    guard overlay?.id == id else { return }
    overlay?.dismissedByUser()
  }

  private func overlayEnded(id: String) {
    guard overlay?.id == id else { return }
    closeOverlay()
    blockThenPromote(.overlay)
  }

  private func closeOverlay() {
    overlay?.stop()
    overlay = nil
  }

  private func present(_ request: OverlayRequest) {
    let presented = OverlayModel(request, makeModel: openOverlayEntry)
    presented.onEnded = { [weak self] in self?.overlayEnded(id: request.id) }
    overlay = presented
    presented.start()
  }

  private func close(id: String) {
    if toast?.id == id {
      toastTimer?.cancel()
      toast = nil
      promote()
    } else if let gone = dialog, gone.id == id {
      dialog = nil
      // Off screen, one turn later than the state, and once: to the instance it belonged to.
      let owner = session
      Task { owner?.effectDismissed(gone.id) }
      blockThenPromote(.dialog)
    } else if sheet?.id == id {
      closeSheet()
      blockThenPromote(.sheet)
    } else if overlay?.id == id {
      overlayEnded(id: id)
    } else {
      pending.removeAll { $0.id == id }
    }
  }

  /// Removes the sheet and stops following its screen. The engine closes the instance.
  private func closeSheet() {
    sheet?.model.stop()
    sheet = nil
  }

  private func blockThenPromote(_ kind: Kind) {
    blockedUntilClear.insert(kind)
    let pause = pause
    Task { [weak self] in
      await pause(Self.presentationGap)
      self?.blockedUntilClear.remove(kind)
      self?.promote()
    }
  }

  private func promote() {
    guard visible else { return }
    if toast == nil, let request = take(\.asToast) { show(request) }
    if dialog == nil, !blockedUntilClear.contains(.dialog), let request = take(\.asDialog) {
      dialog = request
    }
    if sheet == nil, !blockedUntilClear.contains(.sheet), let request = take(\.asSheet) {
      sheet = PresentedSheet(id: request.id, model: openChild(request))
    }
    if overlay == nil, !blockedUntilClear.contains(.overlay), let request = take(\.asOverlay) {
      present(request)
    }
  }

  /// The oldest waiting effect of one kind whose tree is on screen.
  private func take<Request>(_ kind: KeyPath<EffectRequest, Request?>) -> Request? {
    guard
      let index = pending.firstIndex(where: {
        $0[keyPath: kind] != nil && $0.generation <= generation
      })
    else { return nil }
    return pending.remove(at: index)[keyPath: kind]
  }

  private func show(_ request: ToastRequest) {
    toast = request
    announce(request.message)
    let pause = pause
    toastTimer = Task { [weak self] in
      await pause(request.milliseconds)
      guard !Task.isCancelled else { return }
      self?.toastExpired(id: request.id)
    }
  }

  private func toastExpired(id: String) {
    guard toast?.id == id else { return }
    toast = nil
    session?.effectDismissed(id)
    promote()
  }

  /// Posts a VoiceOver announcement for `message`.
  static func announceToVoiceOver(_ message: String) {
    if #available(iOS 17, *) {
      AccessibilityNotification.Announcement(message).post()
    } else {
      UIAccessibility.post(notification: .announcement, argument: message)
    }
  }
}

extension EffectRequest {
  var id: String {
    switch self {
    case .toast(let request): request.id
    case .dialog(let request): request.id
    case .sheet(let request): request.id
    case .overlay(let request): request.id
    case .dismiss(let id): id
    }
  }

  var generation: Int64 {
    switch self {
    case .toast(let request): request.generation
    case .dialog(let request): request.generation
    case .sheet(let request): request.generation
    case .overlay(let request): request.generation
    case .dismiss: -1
    }
  }
}

extension EffectRequest {
  var asToast: ToastRequest? {
    if case .toast(let request) = self { request } else { nil }
  }

  var asDialog: DialogRequest? {
    if case .dialog(let request) = self { request } else { nil }
  }

  var asSheet: SheetRequest? {
    if case .sheet(let request) = self { request } else { nil }
  }

  var asOverlay: OverlayRequest? {
    if case .overlay(let request) = self { request } else { nil }
  }
}
