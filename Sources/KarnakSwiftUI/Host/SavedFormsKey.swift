import KarnakCore

/// The name a screen's form state has in the ``SavedFormsStore``: one per client (`scope`: its server and client
/// key, so two projects or environments in one app never share a name), screen id, params and host-stack entry, so
/// two entries of one screen in a stack keep their own text. The engine still checks the text against the instance
/// it is handed to (screen, params, account), so a name that two views share loses a restore and never mixes them.
enum SavedFormsKey {
  /// Whether a new process can open the same screen under the same name, so keeping its text is of use: a full
  /// screen (a section closes when it is hidden) that is no entry, or an entry of the app's own router, which the
  /// app restores with its id. An entry the SDK pushed on a host stack (``KarnakHostStack``, `karnakDestinations`)
  /// is not: the SDK restores no stack, and its entry ids are new in every process, so what was written would only
  /// lie on disk unread.
  static func names(fullScreen: Bool, isEntry: Bool, inHostStack: Bool) -> Bool {
    fullScreen && !(isEntry && inHostStack)
  }

  static func name(scope: String, screen: String, params: [String: Any], entry: String?) -> String {
    let converter = KarnakParamsConverter(debug: false, log: { _ in })
    let canonical = (try? converter.convert(params)).map(CanonicalParamsKt.canonicalJson) ?? ""
    // JSON text of the parts: no part can run into the next one.
    let parts = [scope, screen, entry ?? "", canonical]
    let text = (try? JSONEncoder().encode(parts)).flatMap { String(data: $0, encoding: .utf8) }
    return "karnak.forms.\(text ?? parts.joined(separator: "\n"))"
  }
}
