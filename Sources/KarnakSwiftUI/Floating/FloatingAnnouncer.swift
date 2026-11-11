import Foundation
import SwiftUI

/// Tells VoiceOver a floating view appeared (ADR 0038, D10): the engine resolved the spoken text, so this only posts
/// it, with the priority the declaration asked for.
@MainActor
enum FloatingAnnouncer {
  /// Where announcements go unless a test replaced it: VoiceOver.
  static var post: @MainActor (_ text: String, _ assertive: Bool) -> Void = postToVoiceOver

  private static func postToVoiceOver(_ text: String, _ assertive: Bool) {
    var spoken = AttributedString(text)
    if assertive { spoken.accessibilitySpeechAnnouncementPriority = .high }
    AccessibilityNotification.Announcement(spoken).post()
  }
}
