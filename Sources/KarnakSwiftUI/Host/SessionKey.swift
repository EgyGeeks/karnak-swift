import KarnakCore

/// Which screen a view shows, for telling when it must open another.
struct SessionKey: Equatable {
  let screenId: String
  /// The params in the client's canonical text form, without what isn't a JSON value.
  let params: String
  let opener: ObjectIdentifier?
  let entryId: String?

  init(screenId: String, params: [String: Any], opener: ScreenOpening?, entryId: String? = nil) {
    self.screenId = screenId
    self.entryId = entryId
    self.opener = opener.map(ObjectIdentifier.init)
    // The client's own canonical form, so equal params in any order are one screen. Release
    // mode drops what isn't a JSON value, as the client does, and never throws.
    let converter = KarnakParamsConverter(debug: false, log: { _ in })
    self.params = (try? converter.convert(params)).map(CanonicalParamsKt.canonicalJson) ?? ""
  }
}
