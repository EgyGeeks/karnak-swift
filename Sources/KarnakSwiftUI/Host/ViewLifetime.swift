import SwiftUI

/// The life of a screen view's identity, as SwiftUI keeps a `@StateObject`: only the view holds it,
/// so it is released when the view is gone for good (popped, its tab or branch removed), however
/// long anyone else keeps the view's ``ScreenModel``. Its release stops that model, which closes the
/// screen. A view that is only hidden (covered, in another tab) keeps it.
final class ViewLifetime: ObservableObject, @unchecked Sendable {
  /// The model whose screen ends with the view. Held strongly, so it is still there to stop when
  /// the view's state is released, whichever of the two SwiftUI releases first.
  var model: ScreenModel?

  deinit {
    let model = model
    Task { @MainActor in model?.stop() }
  }
}
