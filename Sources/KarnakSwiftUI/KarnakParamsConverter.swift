import CoreFoundation
import Foundation
import KarnakCore

/// Host-input errors include the offending parameter path, never its value.
public struct ParamsError: Error, CustomStringConvertible {
  /// An actionable diagnostic suitable for the host logger.
  public let description: String
}

/// Converts Swift host params to the shared JSON model, preserving nil and NSNull as JSON null.
public struct KarnakParamsConverter {
  private let debug: Bool
  private let log: (String) -> Void

  /// Supply the host application's debug flag and error logger.
  public init(debug: Bool, log: @escaping (String) -> Void) {
    self.debug = debug
    self.log = log
  }

  /// Throws for unsupported debug input; release drops and logs invalid fields/elements.
  public func convert(_ params: [String: Any]) throws -> KarnakValueObject {
    let root = params as NSDictionary
    var ancestors: [AnyObject] = [root]
    return try object(root, path: "$", ancestors: &ancestors)
  }

  private func object(
    _ params: NSDictionary,
    path: String,
    ancestors: inout [AnyObject]
  ) throws -> KarnakValueObject {
    var fields: [String: KarnakValue] = [:]
    for (key, value) in params {
      guard let key = key as? String else {
        _ = try invalid(path, reason: "object key must be a string")
        continue
      }
      fields[key] = try convertValue(
        value, path: "\(path)[\(jsonKey(key))]", ancestors: &ancestors)
    }
    return KarnakValueObject.make(fields: fields)
  }

  private func convertValue(
    _ value: Any,
    path: String,
    ancestors: inout [AnyObject]
  ) throws -> KarnakValue? {
    if value is NSNull { return KarnakValueNull.shared }
    if let text = value as? String { return KarnakValueText.make(value: text) }
    if let number = value as? NSNumber {
      return try convertNumber(number, path: path)
    }
    let reference = value as AnyObject
    if reference is NSNull { return KarnakValueNull.shared }
    guard !ancestors.contains(where: { $0 === reference }) else { return try invalid(path) }
    ancestors.append(reference)
    defer { ancestors.removeLast() }
    if let map = value as? NSDictionary {
      return try object(map, path: path, ancestors: &ancestors)
    }
    if let list = value as? NSArray {
      var items: [KarnakValue] = []
      for index in 0..<list.count {
        let itemPath = "\(path)[\(index)]"
        let value = list.object(at: index)
        if let item = try convertValue(value, path: itemPath, ancestors: &ancestors) {
          items.append(item)
        }
      }
      return KarnakValueArray.make(values: items)
    }
    return try invalid(path)
  }

  private func jsonKey(_ key: String) -> String {
    // Use the shared canonical string escaping so diagnostics agree across SDKs.
    CanonicalParamsKt.canonicalJson(KarnakValueText.make(value: key))
  }

  private func convertNumber(_ number: NSNumber, path: String) throws -> KarnakValue? {
    if CFGetTypeID(number) == CFBooleanGetTypeID() {
      return KarnakValueBool.make(value: number.boolValue)
    }
    let encoding = String(cString: number.objCType)
    let maximum = NSNumber(value: 9_007_199_254_740_992 as Int64)
    let minimum = NSNumber(value: -9_007_199_254_740_992 as Int64)
    let outsideRange =
      number.compare(maximum) == .orderedDescending
      || number.compare(minimum) == .orderedAscending
    if "cCsSiIlLqQ".contains(encoding) && outsideRange {
      return try invalid(path, reason: "integer exceeds 2^53; pass it as a string")
    }
    guard number.doubleValue.isFinite else { return try invalid(path) }
    return KarnakValueNumber.make(value: number.doubleValue)
  }

  private func invalid(
    _ path: String, reason: String = "expected a finite JSON value"
  ) throws -> KarnakValue? {
    let message =
      "Invalid param at \(path): \(reason). See docs/integration.md#params."
    if debug { throw ParamsError(description: message) }
    log(message)
    return nil
  }
}
