import CoreGraphics
import CoreText
import Foundation

/// Registers font files with Core Text (`docs/theme.md`, Fonts), once per file.
///
/// A file becomes a `CGFont` from its bytes and is registered for the process with
/// `CTFontManagerRegisterGraphicsFont`; the font is then reachable by its PostScript name, as
/// `Font.custom` needs. Registration is process-wide and can't be undone here, so a file that
/// is registered already (by this renderer or the app) counts as registered.
enum FontRegistration {
  private static let known = KnownFonts()

  /// The PostScript name of the font in the file at `path`, registered; nil when the file
  /// can't be read or isn't a font Core Text accepts. Reads and registers off the caller's
  /// thread, so it never blocks the main thread.
  static func register(path: String) async -> String? {
    await Task.detached(priority: .utility) { registerNow(path: path) }.value
  }

  /// ``register(path:)`` on the current thread.
  static func registerNow(path: String) -> String? {
    if let name = known.name(for: path) { return name }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
      let provider = CGDataProvider(data: data as CFData),
      let font = CGFont(provider),
      let name = font.postScriptName as String?
    else { return nil }
    var error: Unmanaged<CFError>?
    if !CTFontManagerRegisterGraphicsFont(font, &error) {
      let code = error.map { CFErrorGetCode($0.takeRetainedValue()) }
      guard code == CTFontManagerError.alreadyRegistered.rawValue else { return nil }
    }
    known.set(name, for: path)
    return name
  }
}

/// The files registered so far, by path.
private final class KnownFonts: @unchecked Sendable {
  private let lock = NSLock()
  private var names: [String: String] = [:]

  func name(for path: String) -> String? {
    lock.lock()
    defer { lock.unlock() }
    return names[path]
  }

  func set(_ name: String, for path: String) {
    lock.lock()
    defer { lock.unlock() }
    names[path] = name
  }
}
