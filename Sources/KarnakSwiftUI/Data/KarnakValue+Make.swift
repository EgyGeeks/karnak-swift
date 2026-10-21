import KarnakCore

// The JSON value models export no initializer (ADR 0024 D6): Kotlin/Native drops their internal
// constructors, and a class extension can't add an `init` with nothing to delegate to. These
// helpers call each model's public factory, which Swift sees as `companion.invoke(...)`.

extension KarnakValueBool {
  static func make(value: Bool) -> KarnakValueBool { companion.invoke(value: value) }
}

extension KarnakValueNumber {
  /// `value` must be finite; the factory rejects any other number.
  static func make(value: Double) -> KarnakValueNumber { companion.invoke(value: value) }
}

extension KarnakValueText {
  static func make(value: String) -> KarnakValueText { companion.invoke(value: value) }
}

extension KarnakValueArray {
  static func make(values: [KarnakValue]) -> KarnakValueArray { companion.invoke(values: values) }
}

extension KarnakValueObject {
  static func make(fields: [String: KarnakValue]) -> KarnakValueObject {
    companion.invoke(fields: fields)
  }
}
