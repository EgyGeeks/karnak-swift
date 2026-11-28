import KarnakCore
import SwiftUI

/// What `\.karnakTheme` reads: the theme the client holds now, and a one-time load that the first read starts, so a
/// host whose views never read the theme fixes and fetches nothing (ADR 0056, D3).
struct KarnakThemeState: @unchecked Sendable {
  /// No host: `\.karnakTheme` is nil.
  static let none = KarnakThemeState(theme: nil, firstRead: nil)

  // The engine's theme is immutable and safe to share between threads; the registry is read on the main actor only.
  let theme: ScreenTheme?
  /// Starts the load once; nil outside a host.
  let firstRead: (@Sendable () -> Void)?
  /// The host's theme fonts, and how many faces they had registered when the host last drew.
  var fonts: ThemeFontRegistry?
  var fontsRegistered = 0

  func read(isDark: Bool, dynamicTypeSize: DynamicTypeSize) -> KarnakTheme? {
    firstRead?()
    return theme.map {
      KarnakTheme(
        $0, isDark: isDark, dynamicTypeSize: dynamicTypeSize, fonts: fonts,
        fontsRegistered: fontsRegistered)
    }
  }
}

extension EnvironmentValues {
  /// The host's theme state behind the public, read-only `\.karnakTheme`.
  @Entry var karnakThemeState = KarnakThemeState.none
}

/// Gives the views below `.karnakHost` the client's theme through `\.karnakTheme`, and draws them again when the
/// client holds another one. It observes the client from the start (that reads nothing), and loads the theme only on
/// the first read. A host given another client (a new one after sign-out) follows that client from then on.
struct KarnakThemeHost: ViewModifier {
  @StateObject private var model: KarnakThemeModel
  let client: KarnakSwiftClient

  init(client: KarnakSwiftClient) {
    _model = StateObject(wrappedValue: KarnakThemeModel(source: client))
    self.client = client
  }

  func body(content: Content) -> some View {
    // Reading `registered` here draws the host again when a face lands, so `\.karnakTheme` changes with it.
    var state = model.state
    state.fonts = client.fonts
    state.fontsRegistered = client.fonts.registered
    return content.environment(\.karnakThemeState, state)
      .onChange(of: ObjectIdentifier(client)) { model.follow(client) }
  }
}

/// Where the theme comes from: the client, or a fake in tests.
@MainActor
protocol KarnakThemeSource: AnyObject {
  /// The theme held now, then each one the client holds after, on the main thread.
  func themes() -> AsyncStream<ScreenTheme?>
  /// Loads the theme as a first screen would; returns whether one is held.
  func loadTheme() async -> Bool
}

extension KarnakSwiftClient: KarnakThemeSource {}

/// The theme state the host publishes: the client's held theme, and the load the first read starts.
@MainActor
final class KarnakThemeModel: ObservableObject {
  @Published private(set) var state = KarnakThemeState.none

  // Cancelled in deinit, which is nonisolated; it is set on the main actor only, by `follow`.
  nonisolated(unsafe) private var observation: Task<Void, Never>?

  init(source: any KarnakThemeSource) {
    follow(source)
  }

  deinit { observation?.cancel() }

  /// Reads `source`'s theme from now on, in place of the one before: its held theme, and a first read that loads it.
  func follow(_ source: any KarnakThemeSource) {
    observation?.cancel()
    state = KarnakThemeState(theme: nil, firstRead: Self.firstRead(of: source))
    let themes = source.themes()
    observation = Task { [weak self] in
      for await theme in themes {
        guard let self, !Task.isCancelled else { return }
        self.state = KarnakThemeState(theme: theme, firstRead: self.state.firstRead)
      }
    }
  }

  /// A view's read runs during a draw, so it only flips a flag; the first flip starts the load on the main actor.
  private static func firstRead(of source: any KarnakThemeSource) -> @Sendable () -> Void {
    let once = Once()
    let box = WeakSource(source)
    return {
      guard once.claim() else { return }
      Task { @MainActor in _ = await box.source?.loadTheme() }
    }
  }
}

/// A flag that one caller claims, from any thread.
private final class Once: @unchecked Sendable {
  private let lock = NSLock()
  private var claimed = false

  func claim() -> Bool {
    lock.withLock {
      defer { claimed = true }
      return !claimed
    }
  }
}

/// The source, held weakly so a read closure that outlives the host keeps no client alive.
private final class WeakSource: @unchecked Sendable {
  weak var source: (any KarnakThemeSource)?

  init(_ source: any KarnakThemeSource) { self.source = source }
}
