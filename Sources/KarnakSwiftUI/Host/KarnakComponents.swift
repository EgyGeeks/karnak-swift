import KarnakCore
import SwiftUI

/// A custom node as its renderer gets it (`docs/renderer-contract.md`, `Custom`).
public struct KarnakCustomNode {
  /// The node's namespaced type, such as `acme.map`.
  public let type: String
  /// The node's props as JSON host values: `String`, `NSNumber`, `NSNull`, arrays and dictionaries. They are opaque to
  /// the SDK, so the renderer checks them itself.
  public let props: [String: Any]

  init(_ node: ResolvedCustom) {
    type = node.type
    props = KarnakValueObject.make(fields: node.props).toParams()
  }
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
  ///   - renderer: Draws the node from its props. Calling its second argument has the node's resolved fallback drawn
  ///     instead, in the node's place and with the fallback's own style, or nothing when the node has none: return
  ///     `fallback()` when the props fail the component's own checks. It is a view builder: the SDK may run it more
  ///     than once for one drawing, so it has no side effects.
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
