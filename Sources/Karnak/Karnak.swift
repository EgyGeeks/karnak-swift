// The `Karnak` product: one import for the SwiftUI renderer and HTTP data.
// The modules stay separate inside the package; this file only re-exports them. `KarnakCore` (the Kotlin framework) is
// not re-exported, so its names do not collide with the renderer's: import it where you need the Kotlin types.
// Navigation is its own product, `KarnakNavigation`.
@_exported import KarnakDataHttp
@_exported import KarnakSwiftUI
