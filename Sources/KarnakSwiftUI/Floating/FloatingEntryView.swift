import KarnakCore
import SwiftUI

/// What a floating view tells the screen it sits over: where its end goes (the instance's `floatingDismissed`) and
/// whether a dialog the SDK shows covers the screen, which pauses its timer (ADR 0038, D7).
struct FloatingHost {
  /// The view `key` ended for `reason`.
  var dismiss: (_ key: String, _ reason: FloatingDismissReason) -> Void = { _, _ in }
  /// Whether a dialog covers the screen now.
  var dialogCovers = false
}

/// One floating view as a person sees it: its surface and content, its time, its swipe, its announcement and its
/// "Dismiss" action (ADR 0038, D7 to D10). It holds the view by value and is split per key by the layer's `ForEach`, so
/// a show updates this one view and the layer, and nothing in the screen's tree.
struct FloatingEntryView: View {
  let view: ResolvedFloating
  let host: FloatingHost

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverRuns
  @State private var pressed = false
  @State private var drag: CGFloat = 0
  @State private var width: CGFloat = 0
  @State private var countdown: FloatingCountdown

  init(view: ResolvedFloating, host: FloatingHost) {
    self.view = view
    self.host = host
    _countdown = State(initialValue: FloatingCountdown(milliseconds: view.durationMillis ?? 0))
  }

  private var timer: FloatingTimerRule {
    FloatingTimerRule(
      hasDuration: view.durationMillis != nil, interactive: view.holdsAction,
      screenReaderRunning: voiceOverRuns,
      pressed: pressed, coveredByDialog: host.dialogCovers)
  }

  var body: some View {
    FloatingSurface(surface: view.surface) {
      NodeView(node: view.content, placement: .standalone).equatable()
    }
    .offset(x: drag)
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      width = $0
    }
    .simultaneousGesture(touch)
    .accessibilityElement(children: .contain)
    .accessibilityActions {
      if view.behavior.swipe || view.behavior.tapOutside {
        Button(view.dismissLabel) { host.dismiss(view.key, view.dismissGestureReason) }
      }
    }
    .task(id: view.key) { announce() }
    .task(id: timer.runs) { await runTimer() }
  }

  /// A press pauses the timer; a horizontal drag of a view that takes a swipe moves it, and past half its width or a
  /// fling it ends (ADR 0038, D7).
  private var touch: some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        pressed = true
        if view.behavior.swipe { drag = value.translation.width }
      }
      .onEnded { value in
        pressed = false
        guard view.behavior.swipe else { return }
        let flung = abs(value.predictedEndTranslation.width) > width
        if abs(value.translation.width) > width / 2 || flung {
          withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            drag = value.translation.width < 0 ? -width : width
          }
          host.dismiss(view.key, .swipe)
        } else {
          withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { drag = 0 }
        }
      }
  }

  /// Runs the view's time while ``FloatingTimerRule`` says so; a pause keeps what is left (ADR 0038, D7 and D10).
  private func runTimer() async {
    guard timer.runs else { return }
    countdown.start()
    do {
      try await Task.sleep(for: countdown.left)
      host.dismiss(view.key, .timeout)
    } catch {
      countdown.pause()
    }
  }

  /// Tells VoiceOver the view appeared, in the priority its declaration asked for.
  private func announce() {
    guard view.announce != .none, let text = view.announcement, !text.isEmpty else { return }
    FloatingAnnouncer.post(text, view.announce == .assertive)
  }
}
