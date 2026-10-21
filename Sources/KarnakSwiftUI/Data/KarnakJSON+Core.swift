import KarnakCore

extension KarnakJSON {
  /// The value as the shared JSON model, or nil when it holds a number that is not finite, which
  /// JSON cannot express.
  func karnakValue() -> KarnakValue? {
    switch self {
    case .null: return KarnakValueNull.shared
    case .bool(let value): return KarnakValueBool.make(value: value)
    case .number(let value): return value.isFinite ? KarnakValueNumber.make(value: value) : nil
    case .string(let value): return KarnakValueText.make(value: value)
    case .array(let items):
      let values = items.compactMap { $0.karnakValue() }
      return values.count == items.count ? KarnakValueArray.make(values: values) : nil
    case .object(let members):
      let fields = members.compactMapValues { $0.karnakValue() }
      return fields.count == members.count ? KarnakValueObject.make(fields: fields) : nil
    }
  }

  /// The shared JSON model as a value; a node of a type this SDK does not know reads as `null`.
  init(_ value: KarnakValue) {
    switch value {
    case let text as KarnakValueText: self = .string(text.value)
    case let number as KarnakValueNumber: self = .number(number.value)
    case let flag as KarnakValueBool: self = .bool(flag.value)
    case let array as KarnakValueArray: self = .array(array.values.map(KarnakJSON.init))
    case let object as KarnakValueObject: self = .object(object.fields.mapValues(KarnakJSON.init))
    default: self = .null
    }
  }
}
