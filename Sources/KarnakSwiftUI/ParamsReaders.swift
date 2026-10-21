import CoreFoundation
import Foundation
import KarnakCore

extension Dictionary where Key == String, Value == Any {
  /// Reads a string without coercion; absent/null/mismatched fields return nil.
  public func string(_ key: String) -> String? { self[key] as? String }

  /// Reads an exact signed 32-bit integer, matching the Kotlin and web readers.
  public func int(_ key: String) -> Int? {
    guard let number = self[key] as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID()
    else { return nil }
    let value = number.doubleValue
    guard value.isFinite, value.rounded() == value,
      value >= Double(Int32.min), value <= Double(Int32.max)
    else { return nil }
    return Int(value)
  }

  /// Reads a boolean without accepting numeric NSNumber values.
  public func boolean(_ key: String) -> Bool? {
    guard let number = self[key] as? NSNumber,
      CFGetTypeID(number) == CFBooleanGetTypeID()
    else { return nil }
    return number.boolValue
  }

  /// Reads an array without coercion.
  public func list(_ key: String) -> [Any]? { self[key] as? [Any] }

  /// Reads an object without coercion.
  public func map(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
}

extension KarnakValueObject {
  /// Converts shared JSON values to Swift values, representing explicit null with NSNull.
  public func toParams() -> [String: Any] {
    fields.mapValues(hostValue)
  }

  /// Returns the shared canonical JSON representation for the params portion of cache keys.
  public func canonicalParams() -> String {
    CanonicalParamsKt.canonicalJson(self)
  }
}

private func hostValue(_ value: KarnakValue) -> Any {
  switch value {
  case let text as KarnakValueText: return text.value
  case let number as KarnakValueNumber: return number.value
  case let boolean as KarnakValueBool: return boolean.value
  case let array as KarnakValueArray: return array.values.map(hostValue)
  case let object as KarnakValueObject: return object.toParams()
  default: return NSNull()
  }
}
