import Foundation
import KarnakCore

/// When a paragraph with a live countdown redraws: at each second of the time left, which is a second of the server's
/// clock, not of the device's (`docs/renderer-contract.md`, Countdown).
struct Countdown {
  /// The first boundary of a second of the time left, as a date a `TimelineView(.periodic)` starts from.
  let firstTick: Date

  /// The countdown of the first run that has one; nil for a paragraph with fixed text.
  init?(_ paragraph: ResolvedParagraph) {
    guard let countdown = paragraph.runs.lazy.compactMap(\.countdown).first else { return nil }
    self.init(countdown)
  }

  init(_ countdown: ResolvedCountdown) {
    // The time left changes when `end - (now + offset)` crosses a whole second.
    firstTick = Date(
      timeIntervalSince1970: Double(
        Self.boundary(end: countdown.endEpochMillis, offset: countdown.serverOffsetMillis))
        / 1000)
  }

  /// Where in a second, in milliseconds, the time left changes: `end - offset` modulo a second, never negative.
  static func boundary(end: Int64, offset: Int64) -> Int64 {
    ((end - offset) % 1000 + 1000) % 1000
  }
}
