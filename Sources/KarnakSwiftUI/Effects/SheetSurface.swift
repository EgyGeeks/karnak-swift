import SwiftUI

extension View {
  /// Paints the sheet this view is the content of in `surface`, the theme's surface as the engine's ARGB
  /// (`docs/renderer-contract.md`, Contained stacks, Style), as Compose's sheet is: behind the content and under the
  /// home indicator, which the sheet's measured height includes (``fitsSheet()``), so the system's material never
  /// shows what is behind the sheet there (#3589). Nil keeps the system's sheet background.
  @ViewBuilder
  func sheetSurface(_ surface: Int32?) -> some View {
    if let surface { presentationBackground(resolvedColor(argb: surface)) } else { self }
  }
}
