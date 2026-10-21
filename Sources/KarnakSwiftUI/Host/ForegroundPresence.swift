/// Why a screen is, or is not, in the foreground (ADR 0018, D8): the three things that stop its
/// data streams. The screen model sends the result to the engine as
/// `ScreenController.setForeground`, so a covered screen or a backgrounded app stops its code
/// adapters, keeps their values and starts them again on return.
struct ForegroundPresence: Equatable {
  /// The screen's view is on screen: false while a push, a tab or a pushed UIKit controller
  /// covers it.
  var shown = true
  /// The app is not in the background. Becoming inactive (the app switcher, a system alert) is a
  /// moment, not a stop, so streams keep running through it.
  var appActive = true
  /// An entry of the host stack that `.karnakDestinations()` draws lies above the screen.
  var covered = false

  /// Whether the screen's sources should run.
  var isForeground: Bool { shown && appActive && !covered }
}
