import Foundation
import KarnakCore
import SwiftUI

/// The project's strings and theme colors for your own screens, the ones that are not
/// server-driven (`docs/integration.md`, Resources for your own screens). Static and Karnak screens
/// then read the same copy and colors, and a change on the platform reaches installed apps
/// without a release. Get it from ``KarnakSwiftClient/resources``, or in a view from
/// `@Environment(\.karnakResources)`, which ``SwiftUI/View/karnakHost(_:onNavigate:onOpenUrl:onCustom:onTrack:onDismiss:onOpenScreen:onNavigation:)``
/// sets.
///
/// ```swift
/// struct CartFooter: View {
///   @Environment(\.karnakResources) private var resources
///   let total: String
///   var body: some View {
///     VStack {
///       Text(resources.string("cart.total", args: ["total": total]))
///       Button(resources.string("cart.checkout")) { checkout() }
///         .tint(resources.color("primary"))
///     }
///   }
/// }
///
/// // Outside SwiftUI
/// let title = karnak.resources.string("orders.shipped_title", args: ["order": order.number])
/// for await _ in karnak.resources.updates { reloadTable() }
/// ```
///
/// **No main-thread I/O.** Nothing is read at construction. The first load (the cache or the
/// bundled snapshot, ``KarnakConfiguration/bundledResources``) runs off the main thread, started by
/// ``KarnakSwiftClient/warmUp(prefetch:)`` (with a bundle), ``ready()`` or the first ``string(_:args:)``
/// or ``color(_:theme:)``; `.karnakHost` alone starts nothing.
/// Until it ends, ``string(_:args:)`` returns the key and ``color(_:theme:)`` returns `nil`; the
/// views below `.karnakHost` draw again when it arrives. An app that shows static text on its first
/// frame awaits ``ready()`` behind its splash screen.
///
/// The value is cheap to copy and safe from any thread.
public struct KarnakSwiftResources: Sendable, Equatable {
  let core: ResourcesCore
  /// Changes with the content, so a view that reads the environment value draws again.
  let generation: Int

  init(core: ResourcesCore, generation: Int = 0) {
    self.core = core
    self.generation = generation
  }

  /// The text for `key` in the current language, with each `{placeholder}` replaced by the entry of
  /// `args` of the same name: a string as it is, a number in its canonical JSON form. A key nothing
  /// holds answers the key itself, and an argument that isn't a string or a number is logged and
  /// left out, since Swift's `String` return can't throw. Locale-aware number and date formatting
  /// is not in version 1: format the value first.
  public func string(_ key: String, args: [String: Any] = [:]) -> String {
    core.string(key, args: args)
  }

  /// The color `name` as a dynamic `Color` that follows the system's light and dark appearance, from
  /// the theme called `theme` or the environment's default theme; `nil` when the theme or the name
  /// is unknown, or before the first load ends. The `Color` reads the content when SwiftUI
  /// resolves it, so switching to dark mode changes it without a request.
  public func color(_ name: String, theme: String? = nil) -> Color? {
    core.color(name, theme: theme)
  }

  /// ``color(_:theme:)``, or `fallback` when it is `nil`.
  public func color(_ name: String, fallback: Color, theme: String? = nil) -> Color {
    core.color(name, theme: theme) ?? fallback
  }

  /// The language of the strings (`en`, `ar-EG`), or `nil` before any table is available.
  public var locale: String? { core.current.locale }

  /// The layout direction of ``locale``; left to right before any table is available.
  public var layoutDirection: LayoutDirection { core.current.layoutDirection }

  /// Yields each time a newer revision or another language is applied, not for the content that is
  /// there now. The stream ends when its task is cancelled.
  public var updates: AsyncStream<KarnakResourcesUpdate> { core.updates() }

  /// Returns when the first content is published: the cache or the bundled snapshot has been read,
  /// off the main thread. It returns at once afterwards, and when nothing was found. Cancelling the
  /// task stops the wait.
  public func ready() async {
    await core.untilCompleted(core.whenReady)
  }

  /// Revalidates the strings with the server now and returns when the request ends. A newer table is
  /// published through ``updates``. Failures are logged and keep what is held. Cancelling the task
  /// stops the wait.
  public func refresh() async {
    await core.untilCompleted(core.whenRefreshed)
  }

  public static func == (left: KarnakSwiftResources, right: KarnakSwiftResources) -> Bool {
    left.core === right.core && left.generation == right.generation
  }
}

/// What changed in the resources: the content now in use.
public struct KarnakResourcesUpdate: Sendable, Equatable {
  /// The language of the strings, or `nil` before any table is available.
  public let locale: String?
  /// The layout direction of ``locale``.
  public let layoutDirection: LayoutDirection
  /// The revision of the string table in use (`strings@7`), or `nil`.
  public let stringsRevision: String?
  /// The revision of the default theme the colors come from (`theme@12`), or `nil`.
  public let themeRevision: String?
}

extension EnvironmentValues {
  /// The resources of the enclosing `.karnakHost`, drawn again when they change. Outside one it
  /// answers every key with the key and every color with `nil`.
  @Entry public var karnakResources: KarnakSwiftResources = .unavailable
}

extension KarnakSwiftResources {
  /// Resources over nothing: keys for texts, no colors.
  static let unavailable = KarnakSwiftResources(
    core: ResourcesCore(resources: nil, debug: false, log: { _ in }))
}
