import CoreFoundation
import Foundation
import KarnakCore

/// Why a custom action's payload cannot be read: the classes `custom_action.payload_invalid` has for a decoder.
public enum KarnakPayloadProblemKind: String, Sendable {
  /// A required field is missing, or `null`.
  case required
  /// A field is present with a value of another type.
  case wrongType = "wrong_type"
  /// A field is a string outside the values its enum allows.
  case notInEnum = "not_in_enum"
}

/// A payload field that ``KarnakPayload`` cannot read. Thrown out of a handler, it drops the action and logs the
/// field; any other error a handler throws is logged, never rethrown.
public struct KarnakPayloadError: Error, Equatable, Sendable, CustomStringConvertible {
  /// The field's JSON Pointer, such as `/sku`.
  public let pointer: String
  /// Why it cannot be read.
  public let kind: KarnakPayloadProblemKind

  /// Creates the error for the field at `pointer`.
  public init(pointer: String, kind: KarnakPayloadProblemKind) {
    self.pointer = pointer
    self.kind = kind
  }

  public var description: String { "\(pointer): \(kind.rawValue)" }
}

/// A custom action's resolved payload, read with typed accessors that generated code builds on. A field that is
/// missing, or `null`, is ``KarnakPayloadProblemKind/required``; one of another type is
/// ``KarnakPayloadProblemKind/wrongType``. The same rules hold on Kotlin (`PayloadFields`) and TypeScript
/// (`PayloadFields`). Numbers read as an `Int` only when exact, within 32 bits. A field the handler does not read is
/// ignored.
///
/// ```swift
/// configuration.customAction("nia.bookmark") { payload in
///   bookmarks.add(try payload.string("articleId"), position: try payload.optional.int("position"))
/// }
/// ```
public struct KarnakPayload: @unchecked Sendable {
  /// The payload as JSON host values: `String`, `NSNumber`, `NSNull`, arrays and dictionaries.
  public let values: [String: Any]

  /// The readers for fields a payload may leave out: they return `nil` for a missing or `null` field.
  public var optional: KarnakOptionalPayload { KarnakOptionalPayload(values: values) }

  /// Creates a payload over `values`.
  public init(_ values: [String: Any]) { self.values = values }

  /// A string field.
  public func string(_ name: String) throws -> String { try required(name, optional.string(name)) }

  /// An exact 32-bit integer field.
  public func int(_ name: String) throws -> Int { try required(name, optional.int(name)) }

  /// A number field.
  public func double(_ name: String) throws -> Double { try required(name, optional.double(name)) }

  /// A boolean field.
  public func bool(_ name: String) throws -> Bool { try required(name, optional.bool(name)) }

  /// An array field, its items as JSON host values.
  public func list(_ name: String) throws -> [Any] { try required(name, optional.list(name)) }

  /// An object field, its members as JSON host values.
  public func map(_ name: String) throws -> [String: Any] { try required(name, optional.map(name)) }

  /// A string field that is one of `allowed`; any other string is ``KarnakPayloadProblemKind/notInEnum``.
  public func enumValue(_ name: String, in allowed: Set<String>) throws -> String {
    try required(name, optional.enumValue(name, in: allowed))
  }

  private func required<T>(_ name: String, _ value: T?) throws -> T {
    guard let value else { throw KarnakPayloadError(pointer: "/\(name)", kind: .required) }
    return value
  }
}

/// The readers of ``KarnakPayload/optional``: a missing or `null` field is `nil`, a wrong type still throws.
public struct KarnakOptionalPayload: @unchecked Sendable {
  let values: [String: Any]

  /// A string field, or `nil`.
  public func string(_ name: String) throws -> String? { try read(name) { $0 as? String } }

  /// An exact 32-bit integer field, or `nil`.
  public func int(_ name: String) throws -> Int? {
    try read(name) { value in
      guard let number = value as? NSNumber, !number.isBoolean else { return nil }
      let double = number.doubleValue
      let fits = double.isFinite && double.rounded() == double
      return fits && double >= Double(Int32.min) && double <= Double(Int32.max) ? Int(double) : nil
    }
  }

  /// A number field, or `nil`.
  public func double(_ name: String) throws -> Double? {
    try read(name) { value in
      guard let number = value as? NSNumber, !number.isBoolean, number.doubleValue.isFinite else {
        return nil
      }
      return number.doubleValue
    }
  }

  /// A boolean field, or `nil`.
  public func bool(_ name: String) throws -> Bool? {
    try read(name) { value in
      guard let number = value as? NSNumber, number.isBoolean else { return nil }
      return number.boolValue
    }
  }

  /// An array field, or `nil`.
  public func list(_ name: String) throws -> [Any]? { try read(name) { $0 as? [Any] } }

  /// An object field, or `nil`.
  public func map(_ name: String) throws -> [String: Any]? {
    try read(name) { $0 as? [String: Any] }
  }

  /// A string field that is one of `allowed`, or `nil`; any other string is ``KarnakPayloadProblemKind/notInEnum``.
  public func enumValue(_ name: String, in allowed: Set<String>) throws -> String? {
    guard let value = try string(name) else { return nil }
    guard allowed.contains(value) else {
      throw KarnakPayloadError(pointer: "/\(name)", kind: .notInEnum)
    }
    return value
  }

  private func read<T>(_ name: String, _ cast: (Any) -> T?) throws -> T? {
    guard let value = values[name], !(value is NSNull) else { return nil }
    guard let typed = cast(value) else {
      throw KarnakPayloadError(pointer: "/\(name)", kind: .wrongType)
    }
    return typed
  }
}

extension NSNumber {
  /// Whether this is a boolean: a Swift `Bool`, or the `KotlinBoolean` the engine boxes one in.
  var isBoolean: Bool { self is KotlinBoolean || CFGetTypeID(self) == CFBooleanGetTypeID() }
}
