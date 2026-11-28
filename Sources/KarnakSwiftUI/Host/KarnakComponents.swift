import KarnakCore
import SwiftUI

/// A custom node as its renderer gets it (`docs/renderer-contract.md`, `Custom`), and what the renderer sends back for
/// it: the form value it edits and the events it declares.
public struct KarnakCustomNode {
  /// The node's namespaced type, such as `acme.map`.
  public let type: String
  /// The node's props as JSON host values: `String`, `NSNumber`, `NSNull`, arrays and dictionaries. They are opaque to
  /// the SDK, so the renderer checks them itself. A prop bound with `$bind` (one its definition marks `bindable`) holds
  /// the value it reads now, and the renderer runs again with new props whenever what it reads changes.
  public let props: [String: Any]
  /// The events the node declares (its `actions` beyond `click`, `appear` and `contextMenu`), which
  /// ``raise(_:payload:byUser:)`` raises.
  public let events: Set<String>
  /// The form value the node edits when it has an `input` group (ADR 0051): what it holds now, `.null` for nothing;
  /// nil for a node that edits none.
  public let value: KarnakJSON?
  /// The message the component shows for its value now (the first failing rule's, or the server's); nil for none.
  public let error: String?
  /// Whether the node takes a written value now: `false` for a disabled input and while its form submits.
  public let isEnabled: Bool

  private let key: NodeKey
  private let handles: [String: ActionHandle]
  private let sinks: CustomSinks?

  init(_ node: ResolvedCustom, sinks: CustomSinks?) {
    type = node.type
    props = KarnakValueObject.make(fields: node.props).toParams()
    events = Set(node.events.keys)
    value = node.input.map { KarnakJSON($0.value) }
    error = node.input?.error
    isEnabled = node.input?.enabled ?? false
    key = node.key
    handles = node.events
    self.sinks = sinks
  }

  /// Writes `value` as the form value the node edits: the form checks its rules and submit sends it, as for any input.
  /// Write the settled value (the picked date, the full code), not each keystroke's. Ignored for a node with no
  /// `input` group, while ``isEnabled`` is `false`, and for a value over 4 KiB as JSON.
  @MainActor
  public func setValue(_ value: KarnakJSON) {
    guard self.value != nil, let sinks, let typed = value.karnakValue() else { return }
    sinks.inputs.send(.customValue(key, typed))
    sinks.inputs.send(.focusChange(key, false))
  }

  /// Raises the event `name` the node declares (one of ``events``, such as `complete` or `verified`) with `payload`,
  /// the fields its definition declares, which the trigger reads as `event.<field>`. `byUser` says whether a person
  /// caused it: an event no person caused runs only its immediate actions, never a navigation or a submit. Ignored
  /// for an event the node doesn't declare, and dropped for a payload over 4 KiB as JSON.
  @MainActor
  public func raise(_ name: String, payload: [String: KarnakJSON] = [:], byUser: Bool = true) {
    guard let handle = handles[name], let sinks,
      let typed = KarnakJSON.object(payload).karnakValue()
    else { return }
    sinks.actions.event(handle, payload: typed, byUser: byUser)
  }
}

/// Where a drawn custom node sends its value and its events: the screen's input and action sinks.
struct CustomSinks {
  let inputs: InputSink
  let actions: ActionSink
}

/// What a custom renderer returns to have the node's fallback drawn: the value of calling its `fallback` argument. It
/// draws nothing itself: the SDK draws the node's resolved fallback in the node's place.
public struct KarnakCustomFallback: View {
  init() {}

  /// Nothing: the fallback is drawn by the SDK, where the node would have been.
  public var body: some View { EmptyView() }
}

/// A custom renderer with its view type erased, so the registry can hold one per type.
typealias CustomRenderer =
  @MainActor (_ node: KarnakCustomNode, _ fallback: () -> KarnakCustomFallback) -> AnyView

/// Registers the app's custom components, inside ``KarnakConfiguration/components(_:)``.
public final class KarnakComponentsBuilder {
  private(set) var renderers: [String: CustomRenderer]

  init(_ existing: [String: CustomRenderer]) { renderers = existing }

  /// Draws custom nodes of `type` with `renderer`. A later registration of the same type replaces the earlier one.
  ///
  /// The SDK applies the node's size, decoration, semantics and click handling around the view `renderer` returns, so
  /// the view draws the content only.
  ///
  /// - Parameters:
  ///   - type: A namespaced type with a dot, such as `acme.map`; built-in primitive types can't be replaced. A type
  ///     with no dot is a programmer error and stops the app.
  ///   - renderer: Draws the node from its props and, for a form input, its ``KarnakCustomNode/value`` and
  ///     ``KarnakCustomNode/error``; it writes the value with ``KarnakCustomNode/setValue(_:)`` and raises the node's
  ///     events with ``KarnakCustomNode/raise(_:payload:byUser:)``, from its own actions. Calling its second
  ///     argument has the node's resolved fallback drawn instead, in the node's place and with the fallback's own
  ///     style, or nothing when the node has none: return `fallback()` when the props fail the component's own
  ///     checks. It is a view builder: the SDK may run it more than once for one drawing, so it has no side effects.
  public func register<Content: View>(
    _ type: String,
    @ViewBuilder _ renderer:
      @escaping @MainActor (_ node: KarnakCustomNode, _ fallback: () -> KarnakCustomFallback) ->
      Content
  ) {
    precondition(
      type.contains("."),
      "Custom component type '\(type)' has no namespace. Register it as '<namespace>.\(type)', for example "
        + "'acme.\(type)'; built-in primitives can't be replaced (docs/components.md, Common fields)."
    )
    renderers[type] = { node, fallback in AnyView(renderer(node, fallback)) }
  }
}

extension KarnakConfiguration {
  /// Registers the app's custom components (`docs/integration.md`, Setup), as `components { }` does in Compose:
  ///
  /// ```swift
  /// configuration.components { components in
  ///   components.register("acme.map") { node, fallback in
  ///     if let stores = node.props["stores"] as? [Any] { AcmeMap(stores: stores) } else { fallback() }
  ///   }
  /// }
  /// ```
  ///
  /// The client announces the registered types in `X-Karnak-Components`, and its engine resolves a node of one of them
  /// to the registered renderer instead of the node's fallback. A custom type nothing is registered for draws its
  /// fallback, or nothing without one. Blocks add up: a later one adds its types, and a type registered again is
  /// replaced.
  public mutating func components(_ configure: (KarnakComponentsBuilder) -> Void) {
    let builder = KarnakComponentsBuilder(componentRenderers)
    configure(builder)
    componentRenderers = builder.renderers
  }
}

/// The custom components of a client: one renderer per namespaced type. The initializer runs anywhere; the renderers
/// run on the main actor.
final class ComponentRegistry: @unchecked Sendable {
  /// No custom components.
  static let empty = ComponentRegistry([:])

  private let renderers: [String: CustomRenderer]

  init(_ renderers: [String: CustomRenderer]) { self.renderers = renderers }

  /// The registered types, which the client announces to the engine.
  var types: Set<String> { Set(renderers.keys) }

  /// The renderer registered for `type`, or nil.
  func renderer(for type: String) -> CustomRenderer? { renderers[type] }
}

extension EnvironmentValues {
  /// The custom components the client's configuration registered.
  @Entry var karnakComponents = ComponentRegistry.empty
}
