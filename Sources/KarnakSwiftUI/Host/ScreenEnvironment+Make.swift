import KarnakCore

// The engine's models export no initializer (ADR 0024 D6): Kotlin/Native drops their internal
// constructors, and a class extension can't add an `init` with nothing to delegate to. This
// helper calls the public factory, which Swift sees as `companion.invoke(...)`.

extension ScreenEnvironment {
  /// An environment for a container of the compact size class; the renderer sets the class once
  /// it knows the width.
  static func make(
    colorMode: ColorMode, layoutDirection: KarnakLayoutDirection
  ) -> ScreenEnvironment {
    companion.invoke(colorMode: colorMode, layoutDirection: layoutDirection)
  }
}
