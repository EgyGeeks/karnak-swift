import Foundation

/// A JSON value: what a data adapter receives as request params and emits in its own shape
/// (`docs/integration.md`, Data adapters). It is `Sendable`, so an adapter's stream can run on any
/// task, and it has literals, so a small emission reads like the JSON it stands for.
///
/// ```swift
/// let badge: KarnakJSON = ["itemCount": 3, "currency": "EGP", "items": [1, 2, 3]]
/// ```
public enum KarnakJSON: Sendable, Equatable {
  /// JSON `null`.
  case null
  /// A boolean.
  case bool(Bool)
  /// A finite number. Integers beyond 2^53 lose precision: send them as strings.
  case number(Double)
  /// A string.
  case string(String)
  /// An array.
  case array([KarnakJSON])
  /// An object.
  case object([String: KarnakJSON])

  /// The string of a ``string``, else nil.
  public var string: String? {
    if case .string(let value) = self { value } else { nil }
  }

  /// The number of a ``number``, else nil.
  public var number: Double? {
    if case .number(let value) = self { value } else { nil }
  }

  /// The boolean of a ``bool``, else nil.
  public var bool: Bool? {
    if case .bool(let value) = self { value } else { nil }
  }

  /// The member `key` of an ``object``, else nil.
  public subscript(key: String) -> KarnakJSON? {
    if case .object(let members) = self { members[key] } else { nil }
  }
}

extension KarnakJSON: ExpressibleByNilLiteral {
  /// `nil` is JSON `null`.
  public init(nilLiteral: ()) { self = .null }
}

extension KarnakJSON: ExpressibleByBooleanLiteral {
  /// A boolean literal.
  public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension KarnakJSON: ExpressibleByIntegerLiteral {
  /// An integer literal, as a number.
  public init(integerLiteral value: Int) { self = .number(Double(value)) }
}

extension KarnakJSON: ExpressibleByFloatLiteral {
  /// A floating-point literal, as a number.
  public init(floatLiteral value: Double) { self = .number(value) }
}

extension KarnakJSON: ExpressibleByStringLiteral {
  /// A string literal.
  public init(stringLiteral value: String) { self = .string(value) }
}

extension KarnakJSON: ExpressibleByArrayLiteral {
  /// An array literal.
  public init(arrayLiteral elements: KarnakJSON...) { self = .array(elements) }
}

extension KarnakJSON: ExpressibleByDictionaryLiteral {
  /// A dictionary literal, as an object.
  public init(dictionaryLiteral elements: (String, KarnakJSON)...) {
    self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
  }
}

extension KarnakJSON: Decodable {
  /// Decodes any JSON value, so an `Encodable` model can be emitted (see ``KarnakDataAdapter``).
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([KarnakJSON].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: KarnakJSON].self))
    }
  }
}
