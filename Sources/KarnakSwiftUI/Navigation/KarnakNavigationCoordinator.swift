import KarnakCore
import SwiftUI
import UIKit

/// Karnak navigation for UIKit apps (`docs/integration.md`, Navigation on iOS): drives a
/// `UINavigationController` with the operations screens ask for. A tap on an `open_screen`
/// button pushes a ``KarnakViewController`` (`replace` and `reset` swap controllers, `back`,
/// `back` to a screen or the root, and `finish` pop), the system back button and the swipe back
/// work, and every controller the navigation controller drops is reported to the SDK, so the
/// screen that opened it hears `cancelled`.
///
/// ```swift
/// let navigation = UINavigationController()
/// let coordinator = KarnakNavigationCoordinator(client: karnak, navigationController: navigation)
/// navigation.setViewControllers([coordinator.makeRoot(screenId: "home")], animated: false)
/// ```
///
/// The coordinator is the navigation controller's `delegate`; a delegate of your own goes in
/// ``forwardingDelegate``. Keep a strong reference to the coordinator: the navigation controller
/// holds it weakly. `modal` and `sheet` screens need nothing from it: each controller draws them
/// with a `NavigationStack` of its own.
@MainActor
public final class KarnakNavigationCoordinator: NSObject, UINavigationControllerDelegate {
  /// What the coordinator needs of the SDK, so tests drive it with controllers of their own.
  struct Environment {
    /// Makes the controller for a screen: its id, params, entry id and the receiver of its outcome.
    var makeController:
      @MainActor (
        _ screenId: String, _ params: [String: Any], _ entryId: String?,
        _ receiver: ((String, [String: Any]) -> Void)?,
        _ perform: @escaping (KarnakNavigation) -> Void
      ) -> UIViewController
    var entryRemoved: @MainActor (String) -> Void
    var report: @MainActor (String) -> Void
    var registry: HostStackRegistry
  }

  private let sdk: Environment
  /// The client that made this coordinator, whose links ``linkHost`` opens (nil in tests).
  private weak var client: KarnakSwiftClient?
  private lazy var links = KarnakLinkHost()
  private weak var navigationController: UINavigationController?
  private let hooks: Hooks
  private var records: [Record] = []
  private var waiting: [() -> Void] = []
  private var draining = false

  /// Receives the delegate calls this coordinator doesn't need. Held weakly.
  public weak var forwardingDelegate: UINavigationControllerDelegate?

  /// Whether pushes and pops animate. Turn it off for tests.
  public var animated = true

  /// The native screens of the routes the app declares, by route id (`karnak.routes.json`): a
  /// `route` step of a flow pushes the controller it makes for the route's params. Give the
  /// controller the step's ``KarnakFlowHandle`` and end the step with
  /// ``KarnakFlowHandle/finish(_:result:)``; the swipe back is the step's `back`. A route with no
  /// entry here shows a plain message and is logged.
  public var routes:
    [String: (_ params: [String: Any], _ handle: KarnakFlowHandle?) -> UIViewController] = [:]

  /// The hooks for what screens ask the app to do, as for ``SwiftUI/View/karnakHost(_:onNavigate:onOpenUrl:onCustom:onTrack:onDismiss:onOpenScreen:onNavigation:)``.
  /// `onDismiss` is also what a `back` with nothing left to pop calls.
  public struct Hooks {
    var onNavigate: ((_ route: String, _ params: [String: Any]) -> Void)?
    var onOpenUrl: ((_ url: URL) -> Void)?
    var onCustom: ((_ type: String, _ params: [String: Any]) -> Void)?
    var onTrack: ((_ event: String, _ properties: [String: Any]) -> Void)?
    var onDismiss: (() -> Void)?

    /// Creates the hooks; every one is optional.
    public init(
      onNavigate: ((_ route: String, _ params: [String: Any]) -> Void)? = nil,
      onOpenUrl: ((_ url: URL) -> Void)? = nil,
      onCustom: ((_ type: String, _ params: [String: Any]) -> Void)? = nil,
      onTrack: ((_ event: String, _ properties: [String: Any]) -> Void)? = nil,
      onDismiss: (() -> Void)? = nil
    ) {
      self.onNavigate = onNavigate
      self.onOpenUrl = onOpenUrl
      self.onCustom = onCustom
      self.onTrack = onTrack
      self.onDismiss = onDismiss
    }
  }

  /// A controller the coordinator made: the SDK's entry id (nil for a root), the screen it shows.
  private struct Record {
    let entryId: String?
    let screenId: String
    weak var controller: UIViewController?
  }

  /// Creates a coordinator for `navigationController`, whose `delegate` it becomes. Screens load
  /// through `client`; images through `imageLoader`, or the built-in loader when nil.
  public convenience init(
    client: KarnakSwiftClient, navigationController: UINavigationController,
    imageLoader: (any KarnakImageLoader)? = nil, hooks: Hooks = Hooks()
  ) {
    self.init(
      navigationController: navigationController, hooks: hooks,
      sdk: Environment(
        makeController: { screenId, params, entryId, receiver, perform in
          KarnakViewController(
            client: client, screenId: screenId, params: params, imageLoader: imageLoader,
            onNavigate: hooks.onNavigate, onOpenUrl: hooks.onOpenUrl, onCustom: hooks.onCustom,
            onTrack: hooks.onTrack, onDismiss: hooks.onDismiss,
            onNavigation: perform,
            entryId: entryId, onFinish: receiver)
        },
        entryRemoved: { client.navigator.entryRemoved($0) }, report: { client.report($0) },
        registry: client.stacks))
    self.client = client
  }

  init(navigationController: UINavigationController, hooks: Hooks, sdk: Environment) {
    self.sdk = sdk
    self.navigationController = navigationController
    self.hooks = hooks
    super.init()
    navigationController.delegate = self
    sdk.registry.register(self)
  }

  /// What a link that opened the app needs of this coordinator (`handleLink` of the
  /// `KarnakNavigation` product): its hooks, and `perform` as the way screens open. Nil without a client.
  package func linkContext() -> KarnakLinkContext? {
    guard let client else { return nil }
    links.update(
      client: client,
      callbacks: KarnakHostCallbacks(
        onNavigate: hooks.onNavigate, onOpenUrl: hooks.onOpenUrl, onCustom: hooks.onCustom,
        onTrack: hooks.onTrack, onDismiss: hooks.onDismiss,
        onNavigation: { [weak self] request in
          MainActor.assumeIsolated { self?.perform(request) }
        }))
    return links.context
  }

  /// A controller for `screenId`, to be the root of the navigation controller (or any controller
  /// the app pushes itself). It is recorded for `back` with `to`.
  public func makeRoot(screenId: String, params: [String: Any] = [:]) -> UIViewController {
    let controller = makeController(screenId: screenId, params: params, entryId: nil, receiver: nil)
    records.append(Record(entryId: nil, screenId: screenId, controller: controller))
    return controller
  }

  /// Performs `request` on the navigation controller, one operation at a time: a push made
  /// while another animates waits for it.
  public func perform(_ request: KarnakNavigation) {
    schedule { [self] in
      switch request {
      case .open(let entryId, .screen(let screenId), let params, let presentation):
        open(entryId: entryId, screenId: screenId, params: params, presentation, receiver: nil)
      case .open(let entryId, .route(let id, let handle), let params, let presentation):
        openRoute(
          entryId: entryId, route: KarnakRouteTarget(id: id, params: params, handle: handle),
          presentation)
      case .back(let screenId, let toRoot, let before):
        back(to: screenId, root: toRoot, before: before)
      }
    }
  }

  // MARK: - Operations

  private func open(
    entryId: String, screenId: String, params: [String: Any], _ presentation: KarnakPresentation,
    receiver: ((String, [String: Any]) -> Void)?
  ) {
    let controller = makeController(
      screenId: screenId, params: params, entryId: entryId, receiver: receiver)
    place(
      controller, Record(entryId: entryId, screenId: screenId, controller: controller), presentation
    )
  }

  /// Opens the native route of a flow step: the controller the app registered for it
  /// (``routes``), or a plain message when it registered none.
  private func openRoute(
    entryId: String, route: KarnakRouteTarget, _ presentation: KarnakPresentation
  ) {
    let controller: UIViewController
    if let make = routes[route.id] {
      controller = make(route.params, route.handle)
    } else {
      sdk.report(KarnakRouteEntryView.missing(route.id))
      // Inside `.karnakHost`, so the registered default error view and the project's strings apply.
      let missing = client.map { AnyView(KarnakMissingRouteView().karnakHost($0)) }
      controller = UIHostingController(rootView: missing ?? AnyView(KarnakMissingRouteView()))
    }
    place(
      controller, Record(entryId: entryId, screenId: route.id, controller: controller), presentation
    )
  }

  /// Puts `controller` on the navigation controller as `presentation` says, and records it.
  private func place(
    _ controller: UIViewController, _ record: Record, _ presentation: KarnakPresentation
  ) {
    guard let navigation = navigationController else { return }
    var stack = navigation.viewControllers
    switch presentation {
    case .replace where !stack.isEmpty:
      stack[stack.count - 1] = controller
    case .reset where !stack.isEmpty:
      stack = [stack[0], controller]
    default:
      if presentation == .modal || presentation == .sheet {
        sdk.report(
          "Karnak: opened a \(presentation) screen as a push: the host stack has no overlay.")
      }
      stack.append(controller)
    }
    records.append(record)
    navigation.setViewControllers(stack, animated: animated && stack.count > 1)
    reconcile()
  }

  private func back(to screenId: String?, root: Bool, before: String?) {
    guard let navigation = navigationController else { return }
    let stack = navigation.viewControllers
    if let before {
      guard let index = stack.firstIndex(where: { entryId(of: $0) == before }), index > 0 else {
        return sdk.report("Karnak: ignored a back before '\(before)': no controller has it.")
      }
      navigation.popToViewController(stack[index - 1], animated: animated)
    } else if let screenId {
      guard let target = stack.last(where: { screenId == shownScreenId(of: $0) }) else {
        return sdk.report("Karnak: ignored a back to '\(screenId)': no controller shows it.")
      }
      navigation.popToViewController(target, animated: animated)
    } else if root {
      navigation.popToRootViewController(animated: animated)
    } else if stack.count > 1 {
      navigation.popViewController(animated: animated)
    } else {
      leave()
    }
    reconcile()
  }

  /// A `back` with nothing to pop leaves the navigation controller: the app's `onDismiss`, or
  /// dismissing it when it is presented.
  private func leave() {
    if let onDismiss = hooks.onDismiss {
      onDismiss()
    } else {
      navigationController?.presentingViewController?.dismiss(animated: animated)
    }
  }

  // MARK: - Controllers

  private func makeController(
    screenId: String, params: [String: Any], entryId: String?,
    receiver: ((String, [String: Any]) -> Void)?
  ) -> UIViewController {
    sdk.makeController(screenId, params, entryId, receiver) { [weak self] request in
      self?.perform(request)
    }
  }

  private func entryId(of controller: UIViewController) -> String? {
    records.first { $0.controller === controller }?.entryId
  }

  private func shownScreenId(of controller: UIViewController) -> String? {
    records.first { $0.controller === controller }?.screenId
  }

  /// Tells the SDK about the controllers that left the navigation controller, deepest first, and
  /// forgets them.
  private func reconcile() {
    let alive = Set((navigationController?.viewControllers ?? []).map(ObjectIdentifier.init))
    let gone = records.filter { record in
      record.controller.map { !alive.contains(ObjectIdentifier($0)) } ?? true
    }
    records.removeAll { record in gone.contains { $0.controller === record.controller } }
    for record in gone.reversed() {
      guard let id = record.entryId else { continue }
      sdk.entryRemoved(id)
      nativeReceivers.removeValue(forKey: id)?.deliver("cancelled", [:])
    }
  }

  private var nativeReceivers: [String: OnceReceiver] = [:]

  // MARK: - Queue

  private func schedule(_ operation: @escaping () -> Void) {
    waiting.append(operation)
    drain()
  }

  /// Runs the waiting operations while no transition is on its way.
  private func drain() {
    guard !draining else { return }
    draining = true
    defer { draining = false }
    while !waiting.isEmpty {
      if let transition = navigationController?.transitionCoordinator {
        transition.animate(alongsideTransition: nil) { [weak self] _ in self?.drain() }
        return
      }
      waiting.removeFirst()()
    }
  }

  // MARK: - UINavigationControllerDelegate

  /// Reports the controllers that left, and runs what waited for the transition.
  public func navigationController(
    _ navigationController: UINavigationController, didShow viewController: UIViewController,
    animated: Bool
  ) {
    reconcile()
    forwardingDelegate?.navigationController?(
      navigationController, didShow: viewController, animated: animated)
    drain()
  }

  /// Passed on to ``forwardingDelegate``.
  public func navigationController(
    _ navigationController: UINavigationController, willShow viewController: UIViewController,
    animated: Bool
  ) {
    forwardingDelegate?.navigationController?(
      navigationController, willShow: viewController, animated: animated)
  }
}

extension KarnakNavigationCoordinator: KarnakEntryHost {
  func push(
    _ screenId: String, params: [String: Any], entryId: String,
    receiver: @escaping (String, [String: Any]) -> Void
  ) {
    let once = OnceReceiver(receiver)
    nativeReceivers[entryId] = once
    schedule { [self] in
      open(
        entryId: entryId, screenId: screenId, params: params, .push,
        receiver: { outcome, result in
          MainActor.assumeIsolated { once.deliver(outcome, result) }
        })
    }
  }

  func remove(_ entryId: String) {
    schedule { [self] in back(to: nil, root: false, before: entryId) }
  }
}
