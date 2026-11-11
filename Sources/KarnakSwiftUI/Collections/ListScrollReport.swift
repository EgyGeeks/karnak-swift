import KarnakCore
import SwiftUI

/// The event a list raises when its `scroll` value changes (ADR 0038, D11).
let scrollChangeEvent = "scrollChange"

/// Folds the scroll a list moved into its `scroll` value (ADR 0038, D11): `top` while it is at its start, otherwise
/// the direction of the last ``threshold`` points of travel that went one way. It starts at `top`, and each call
/// answers a new value only when there is one.
struct ListScrollTracker {
  /// A list's `scroll` value, as the wire names it.
  enum Value: String {
    case top, forward, back
  }

  /// The points a list moves one way before it is `forward` or `back`.
  static let hysteresis: CGFloat = 32

  /// The travel, in points, that turns the value.
  var threshold = ListScrollTracker.hysteresis
  /// The value now.
  private(set) var value = Value.top
  private var travel: CGFloat = 0

  /// The list's content moved `delta` points toward its end (positive) or its start (negative), and is at `offset`
  /// points from its start now. A turn of direction starts the sum again.
  mutating func moved(by delta: CGFloat, to offset: CGFloat) -> Value? {
    let consumed = -delta
    if consumed != 0 { travel = travel * consumed < 0 ? consumed : travel + consumed }
    if offset <= 0.5 { return move(to: .top) }
    if travel <= -threshold { return move(to: .forward) }
    if travel >= threshold { return move(to: .back) }
    return nil
  }

  /// The list was restored part-way: it is `back`, reported once.
  mutating func restored() -> Value? { move(to: .back) }

  private mutating func move(to next: Value) -> Value? {
    travel = 0
    guard next != value else { return nil }
    value = next
    return next
  }
}

/// Reports a list's `scrollChange` (ADR 0038, D11): the change of its `scroll` value, at once and never per frame, and
/// once with `initial: true` for a list that first draws part-way down. A scroll the user's finger made is a person's.
@MainActor
final class ListScrollReporter {
  /// Receives a report: the payload, and whether a person caused it.
  var send: (_ payload: KarnakValue, _ byUser: Bool) -> Void = { _, _ in }
  /// Whether a finger is moving the list now.
  var isGestureActive: () -> Bool = { true }
  private var tracker = ListScrollTracker()
  private var last: CGFloat?

  /// The list's content is `offset` points from its start (0 at rest, never below it for a rubber band's pull).
  func moved(to offset: CGFloat) {
    defer { last = offset }
    guard let last else {
      if offset > 0.5, let value = tracker.restored() {
        send(Self.payload(value, initial: true), false)
      }
      return
    }
    if let value = tracker.moved(by: offset - last, to: offset) {
      send(Self.payload(value, initial: false), isGestureActive())
    }
  }

  /// The payload of a `scrollChange`: `scroll` and `initial`.
  static func payload(_ value: ListScrollTracker.Value, initial: Bool) -> KarnakValue {
    KarnakValueObject.make(fields: [
      "scroll": KarnakValueText.make(value: value.rawValue),
      "initial": KarnakValueBool.make(value: initial),
    ])
  }
}

/// The name a list's scroll view gives its coordinate space, for the sentinel below iOS 18.
private let listScrollSpace = "karnak.list.scroll"

extension View {
  /// Makes this scroll view's offset readable in the coordinate space the sentinel below measures in.
  func measuresScroll() -> some View {
    coordinateSpace(.named(listScrollSpace))
  }

  /// Reports this scroll view's offset (the points scrolled from its start) as it changes, when `isEnabled`: the scroll
  /// view's own geometry on iOS 18 (`onScrollGeometryChange`), read once per change.
  @ViewBuilder
  func reportsScrollOffset(isEnabled: Bool, _ report: @escaping (CGFloat) -> Void) -> some View {
    if isEnabled, #available(iOS 18.0, *) {
      onScrollGeometryChange(for: CGFloat.self) {
        $0.contentOffset.y + $0.contentInsets.top
      } action: { _, new in
        report(new)
      }
    } else {
      self
    }
  }

  /// A sentinel at the top of this scroll content that reports the offset below iOS 18 (iOS 17), where the scroll view
  /// has no geometry to read: its position in the scroll view's coordinate space is minus the offset.
  @ViewBuilder
  func scrollSentinel(isEnabled: Bool, _ report: @escaping (CGFloat) -> Void) -> some View {
    if isEnabled, #unavailable(iOS 18.0) {
      overlay(alignment: .top) {
        Color.clear.frame(height: 0)
          .onGeometryChange(for: CGFloat.self) {
            -$0.frame(in: .named(listScrollSpace)).minY
          } action: {
            report($0)
          }
      }
    } else {
      self
    }
  }
}
