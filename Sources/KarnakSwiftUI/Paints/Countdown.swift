import Foundation
import KarnakCore

/// When a paragraph with a live countdown redraws: at each instant the floored time left drops a second, which is a
/// second of the server's clock, not of the device's (`docs/renderer-contract.md`, Countdown). Every paragraph of one
/// end redraws on the same dates and reads its text from the date, not from the clock, so boxes of one end change
/// together.
struct Countdown {
  /// The first instant the text changes, as a date a `TimelineView(.periodic)` starts from.
  let firstTick: Date

  /// The countdown of the first run that has one; nil for a paragraph with fixed text.
  init?(_ paragraph: ResolvedParagraph) {
    guard let countdown = paragraph.runs.lazy.compactMap(\.countdown).first else { return nil }
    self.init(countdown)
  }

  init(_ countdown: ResolvedCountdown) {
    firstTick = Date(
      timeIntervalSince1970: Double(
        Self.change(end: countdown.endEpochMillis, offset: countdown.serverOffsetMillis))
        / 1000)
  }

  /// Where in a second, in milliseconds, the floored time left drops: the millisecond after `end - offset` crosses a
  /// whole second (at the crossing itself the old count still shows), from 1 to 1000.
  static func change(end: Int64, offset: Int64) -> Int64 {
    ((end - offset) % 1000 + 1000) % 1000 + 1
  }
}

/// Raises a text's `elapsed` once, when one of its countdowns reaches zero after a tick saw it with time left
/// (`docs/renderer-contract.md`, Countdown; the engine's `CountdownElapse`). A new paragraph, with other countdowns,
/// starts over.
@MainActor
final class ElapsedWatch {
  private var countdowns: [ResolvedCountdown] = []
  private var elapse: CountdownElapse?

  /// Whether `paragraph` raises `elapsed` at `nowMillis`.
  func elapsed(_ paragraph: ResolvedParagraph, at nowMillis: Int64) -> Bool {
    elapsed(paragraph.runs.compactMap(\.countdown), at: nowMillis)
  }

  /// Whether a text showing `current` raises `elapsed` at `nowMillis`.
  func elapsed(_ current: [ResolvedCountdown], at nowMillis: Int64) -> Bool {
    if elapse == nil || current != countdowns {
      countdowns = current
      elapse = CountdownElapse(countdowns: current)
    }
    return elapse?.elapsedAt(deviceNowEpochMillis: nowMillis) ?? false
  }
}

/// The payload of `elapsed`, which has no fields.
var elapsedPayload: KarnakValue { KarnakValueObject.make(fields: [:]) }

/// The event a text raises when a countdown it shows reaches zero.
let elapsedEvent = "elapsed"
