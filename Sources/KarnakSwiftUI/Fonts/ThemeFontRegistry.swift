import Foundation
import KarnakCore
import SwiftUI

/// Where the file of a theme font face comes from: the client's font cache, or a fake in tests.
protocol FontFileSource: Sendable {
  /// The absolute path of `face`'s file, downloaded and cached on first use; nil when it has no
  /// usable format or can't be fetched.
  func fontFile(for face: FontFaceHandle) async -> String?
}

/// A resolved face passed to a font source. The engine's resolved values are immutable, so
/// sharing one between threads is safe.
struct FontFaceHandle: @unchecked Sendable {
  let face: ResolvedFontFace
}

/// Loads and registers the theme fonts the views draw (`docs/renderer-contract.md`, Resources).
///
/// A view asks ``postScriptName(for:)`` while it builds its text. The first ask for a face
/// starts loading it off the main thread and answers nil, so the text is drawn in the system
/// font at the same size and weight; when the face is registered the registry publishes a
/// change and the views ask again and get the name. A face that can't be loaded stays nil, and
/// its text keeps the system font, and is tried again on the next draw after `retryAfter`
/// seconds: a failure can be transient (offline at launch), and the app can live for days.
@MainActor
final class ThemeFontRegistry: ObservableObject {
  /// A registry with no font source: every face keeps the system font.
  static let unavailable = ThemeFontRegistry(source: nil)

  private enum State {
    case loading
    case ready(String)
    case failed(Date)
  }

  private let source: (any FontFileSource)?
  private var states: [String: State] = [:]

  private let retryAfter: TimeInterval
  private let now: () -> Date

  init(
    source: (any FontFileSource)?,
    retryAfter: TimeInterval = 30,
    now: @escaping () -> Date = Date.init
  ) {
    self.source = source
    self.retryAfter = retryAfter
    self.now = now
  }

  /// The registered PostScript name of `face`, or nil while it loads or if it can't be used.
  func postScriptName(for face: ResolvedFontFace) -> String? {
    let key = Self.key(face)
    switch states[key] {
    case .ready(let name): return name
    case .loading: return nil
    case .failed(let date) where now().timeIntervalSince(date) < retryAfter: return nil
    case .failed, nil:
      guard let source else { return nil }
      states[key] = .loading
      let handle = FontFaceHandle(face: face)
      Task { await load(handle, key: key, from: source) }
      return nil
    }
  }

  private func load(_ face: FontFaceHandle, key: String, from source: any FontFileSource) async {
    let name: String?
    if let path = await source.fontFile(for: face) {
      name = await FontRegistration.register(path: path)
    } else {
      name = nil
    }
    states[key] = name.map(State.ready) ?? .failed(now())
    if name != nil { objectWillChange.send() }
  }

  /// Faces are identified by their sources: revision URLs name immutable bytes.
  private static func key(_ face: ResolvedFontFace) -> String {
    face.sources.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
  }
}

extension EnvironmentValues {
  /// The theme fonts below; nil outside `.karnakHost`, where text keeps the system font.
  @Entry var karnakFonts: ThemeFontRegistry?
}
