import KarnakCore

/// What the SwiftUI renderer announces to the engine (`docs/renderer-contract.md`, Announcing; ADR 0037, D18): the
/// built-in primitives, the opt-in `canvas` and the custom types the host registered, the effects it presents, the reactive features it draws and the
/// floating layer (ADR 0038, D13). The engine
/// resolves only what a renderer announces, so this lists exactly what the views draw: a feature added here without
/// its drawing would be resolved and then dropped.
enum SwiftRendererProfile {
  /// The profile of the SwiftUI client; `loadingLabel` is the name VoiceOver reads for the loading state, and
  /// `custom` the types of the host's custom components.
  static func make(loadingLabel: String, custom: Set<String> = []) -> RendererProfile {
    let profile = RendererProfile.companion
    return ScreenResolversKt.iosRendererProfile(
      components: profile.PRIMITIVES.union(profile.OPT_IN_PRIMITIVES).union(custom),
      loadingLabel: loadingLabel,
      effects: profile.EFFECTS, drawnFeatures: profile.DRAWN_FEATURES, floatingLayer: true)
  }
}
