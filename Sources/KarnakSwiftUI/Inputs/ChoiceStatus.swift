import KarnakCore
import SwiftUI

/// Where a choice input's options stand (`docs/renderer-contract.md`, Choice status): the members every choice input
/// carries, read off whichever of the five it is. Literal options keep every member's quiet default.
struct ChoiceStatus {
  /// The options are reloading: drawn, but not pickable, and focus stays where it is.
  var busy = false
  /// Why there is nothing to offer, drawn where the options would be.
  var notice: InputText?
  /// The options failed to load: its message and a retry.
  var optionsError: OptionsError?
  /// What to post politely once its sequence moves.
  var announcement: Announcement?

  init(_ input: ResolvedInput) {
    switch input {
    case let select as ResolvedSelect:
      self.init(select.busy, select.notice, select.optionsError, select.announcement)
    case let group as ResolvedRadioGroup:
      self.init(group.busy, group.notice, group.optionsError, group.announcement)
    case let group as ResolvedCheckboxGroup:
      self.init(group.busy, group.notice, group.optionsError, group.announcement)
    case let group as ResolvedChipGroup:
      self.init(group.busy, group.notice, group.optionsError, group.announcement)
    case let control as ResolvedSegmented:
      self.init(control.busy, control.notice, control.optionsError, control.announcement)
    default:
      self.init(false, nil, nil, nil)
    }
  }

  private init(
    _ busy: Bool, _ notice: InputText?, _ optionsError: OptionsError?, _ announcement: Announcement?
  ) {
    self.busy = busy
    self.notice = notice
    self.optionsError = optionsError
    self.announcement = announcement
  }
}

/// The opacity of options drawn while they reload (ADR 0062, D6): visibly not pickable, without the platform's
/// disabled state, which would take focus away.
let busyOptionsOpacity = 0.5

extension View {
  /// Draws a choice input's options while they reload (`busy`): dimmed, and read by VoiceOver as not interactive, but
  /// never `disabled`, so the focus a person had stays. The views refuse a pick themselves, as the engine does.
  func busyOptions(_ busy: Bool) -> some View {
    opacity(busy ? busyOptionsOpacity : 1)
      .accessibilityRespondsToUserInteraction(!busy)
  }

  /// Posts the choice's polite announcement once per landing (``ChoiceAnnouncement``).
  func postsAnnouncement(_ announcement: Announcement?) -> some View {
    modifier(ChoiceAnnouncement(announcement: announcement))
  }
}

/// What a choice input shows under its options for its status: the notice when it has nothing to offer (spoken as
/// its own text), then the options error with a retry. Nothing for a choice whose options are there.
struct ChoiceStatusView: View {
  let status: ChoiceStatus

  var body: some View {
    if let notice = status.notice { ChoiceNoticeView(notice: notice) }
    if let error = status.optionsError { OptionsErrorView(error: error) }
  }
}

/// A choice's notice ("Choose City first", "No options") in the input's helper look, read by VoiceOver as text.
struct ChoiceNoticeView: View {
  let notice: InputText

  var body: some View {
    InputTextView(notice)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(notice.words)
      .accessibilityAddTraits(.isStaticText)
  }
}

/// A choice's options error (ADR 0062, D5): the message in the input's error look, then a button that asks the
/// failed source again (`click(retry)`). The button's text is the project's `common.retry`, else "Retry" from the
/// host's string catalog, as the default error view's.
struct OptionsErrorView: View {
  let error: OptionsError
  @Environment(\.karnakActions) private var actions
  @Environment(\.karnakResources) private var resources

  var body: some View {
    HStack(spacing: optionsErrorGap) {
      InputTextView(error.message)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(error.message.words)
        .accessibilityAddTraits(.isStaticText)
      Button {
        actions.click(error.retry)
      } label: {
        resources.text("common.retry", fallback: "Retry")
          .frame(minWidth: minimumTouchTarget, minHeight: minimumTouchTarget)
      }
      .contentShape(Rectangle())
    }
  }
}

/// Between an options error's message and its retry button, in points.
private let optionsErrorGap: CGFloat = 8

/// The least width and height of the retry button, in points: Apple's minimum touch target.
private let minimumTouchTarget: CGFloat = 44

/// Posts a choice's announcement politely, once per landing, without moving focus (ADR 0062, D6). The announcement
/// stays on the node until the next landing, so the one a view first draws is never posted: a node drawn again (back
/// navigation, a lazy row scrolled back) stays silent.
private struct ChoiceAnnouncement: ViewModifier {
  let announcement: Announcement?
  @State private var seen: Int64?

  func body(content: Content) -> some View {
    content
      .onAppear { seen = announcement?.sequence ?? 0 }
      .onChange(of: announcement?.sequence) { _, sequence in
        guard let announcement, let sequence, sequence > (seen ?? 0) else { return }
        seen = sequence
        ChoiceAnnouncer.post(announcement.text)
      }
  }
}

/// Where a choice's announcements go unless a test replaced it: VoiceOver, politely. A low priority queues the
/// announcement after the speech in progress (the option just picked) instead of cutting it off, as the default
/// priority would.
@MainActor
enum ChoiceAnnouncer {
  static var post: @MainActor (String) -> Void = {
    var spoken = AttributedString($0)
    spoken.accessibilitySpeechAnnouncementPriority = .low
    AccessibilityNotification.Announcement(spoken).post()
  }
}
