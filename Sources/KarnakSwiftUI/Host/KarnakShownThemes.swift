import Combine
import KarnakCore
import SwiftUI

/// The themes of the screens that are on screen right now, in the order they began to report, so a
/// view that draws around its screens reads the theme of the one that is shown (``KarnakScreenColors``).
/// The shown screen is the content of the host's stack (`docs/renderer-contract.md`, Theme of the shown
/// screen): a ``KarnakScreen`` (a destination) or a ``KarnakFlow`` step. Overlays (sheets and modals)
/// and sections never report.
///
/// One per `.karnakHost`: a screen reports into the host it is drawn in and takes its report back when
/// its view is covered or gone, so no theme outlives its screen, and going back brings the earlier
/// screen's theme back with no reload. A screen that reloads, or changes theme, keeps its place.
@MainActor
final class KarnakShownThemes: ObservableObject {
  /// One screen's report: a token per report, so two screens on one theme are told apart.
  final class Report {
    fileprivate(set) var theme: ScreenTheme
    init(_ theme: ScreenTheme) { self.theme = theme }
  }

  @Published private(set) var reports: [Report] = []

  /// The theme of the screen shown last that is still shown, or `nil` when none is.
  var current: ScreenTheme? { reports.last?.theme }

  func show(_ theme: ScreenTheme) -> Report {
    let report = Report(theme)
    reports.append(report)
    return report
  }

  /// Reports `theme` for `report` in the same place. A theme of the same revision changes nothing.
  func update(_ report: Report, to theme: ScreenTheme) {
    guard reports.contains(where: { $0 === report }), report.theme.revision != theme.revision
    else { return }
    objectWillChange.send()
    report.theme = theme
  }

  func hide(_ report: Report) {
    reports.removeAll { $0 === report }
  }
}

/// One screen's report into the host's ``KarnakShownThemes``: ``update(theme:shown:)`` with what is
/// true now, and the report is made, changed in place or taken back to match.
@MainActor
final class ShownThemeReport {
  private var registry: KarnakShownThemes?
  private var report: KarnakShownThemes.Report?

  /// Where to report, or `nil` for a screen that reports nothing (a section, an overlay's content).
  func use(_ registry: KarnakShownThemes?) {
    guard registry !== self.registry else { return }
    clear()
    self.registry = registry
  }

  /// Reports `theme` while the screen is `shown`; either one missing takes the report back.
  func update(theme: ScreenTheme?, shown: Bool) {
    guard let registry, shown, let theme else { return clear() }
    if let report {
      registry.update(report, to: theme)
    } else {
      report = registry.show(theme)
    }
  }

  /// Takes the report back.
  func clear() {
    if let report { registry?.hide(report) }
    report = nil
  }
}
