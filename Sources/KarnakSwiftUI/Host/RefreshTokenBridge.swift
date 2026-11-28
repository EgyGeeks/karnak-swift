import Foundation
import KarnakCore

/// `hook`, a refresh of the person's credentials, as the Kotlin face takes it (ADR 0061 D7): run in a task, its answer
/// passed to the completion once. The client's ``KarnakConfiguration/refreshToken`` and a connection's or auth
/// profile's in `KarnakDataHttp` all go through it.
package func refreshTokenBridge(
  _ hook: @escaping @Sendable () async -> Bool
) -> (@escaping (KotlinBoolean) -> KotlinUnit) -> Void {
  { completion in
    // The Kotlin completion is safe to call from any thread, once.
    nonisolated(unsafe) let completion = completion
    Task {
      let renewed = await hook()
      _ = completion(KotlinBoolean(bool: renewed))
    }
  }
}
