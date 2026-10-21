import KarnakCore

/// How a renderer that draws its own chrome (the toast) looks, from the engine's `EffectStyle`.
/// The system alert and sheet keep the system look.
struct EffectAppearance {
  /// The container's background, as the engine's ARGB.
  let surface: Int32
  /// Text on the container, as the engine's ARGB.
  let onSurface: Int32
  /// The theme's body font; nil draws the system body font (tests).
  let body: ResolvedFont?
}

/// A toast the engine asked for: a transient message.
struct ToastRequest {
  let id: String
  /// The tree generation the toast was computed against.
  let generation: Int64
  let message: String
  /// How long it shows.
  let milliseconds: Int64
  let appearance: EffectAppearance
}

/// A dialog the engine asked for. Its buttons' actions stay in the engine.
struct DialogRequest {
  let id: String
  let generation: Int64
  /// The heading; nil for none.
  let title: String?
  let message: String
  let confirm: String
  /// The declining button's label; nil for a dialog with one button.
  let dismiss: String?
}

/// A sheet the engine asked for: a child screen instance the renderer draws like a screen.
struct SheetRequest: Identifiable {
  let id: String
  let generation: Int64
  /// The child instance. The engine closes it; the renderer never does.
  let screen: any ScreenSession
}

/// An overlay the engine asked for (`open_screen` with `presentation` `modal` or `sheet`): a
/// stack the engine owns and the renderer draws with a `NavigationStack` of its own.
struct OverlayRequest {
  let id: String
  let generation: Int64
  /// `sheet` for a bottom sheet, `modal` for a full-screen cover.
  let presentation: KarnakPresentation
  let stack: any StackSession
}

/// What the engine's effects stream delivers, as the views use it, so tests drive the views
/// with plain values (the engine builds its own effects, and Swift can't).
enum EffectRequest {
  case toast(ToastRequest)
  case dialog(DialogRequest)
  case sheet(SheetRequest)
  case overlay(OverlayRequest)
  /// Close the effect with this id if it is still shown.
  case dismiss(id: String)
}

extension EffectRequest {
  /// Maps the engine's effect; nil for one this renderer ignores (`FocusRequest`, until inputs).
  init?(_ effect: Effect, session makeSession: @escaping (ScreenController) -> any ScreenSession) {
    switch effect {
    case let toast as Toast:
      self = .toast(
        ToastRequest(
          id: toast.id, generation: toast.generation, message: toast.message,
          milliseconds: toast.duration.millis,
          appearance: EffectAppearance(
            surface: toast.style.surface.value, onSurface: toast.style.onSurface.value,
            body: toast.style.body)))
    case let dialog as Dialog:
      self = .dialog(
        DialogRequest(
          id: dialog.id, generation: dialog.generation, title: dialog.title,
          message: dialog.message, confirm: dialog.confirm.label, dismiss: dialog.dismiss?.label))
    case let sheet as Sheet:
      self = .sheet(
        SheetRequest(
          id: sheet.id, generation: sheet.generation, screen: makeSession(sheet.screen)))
    case let overlay as Overlay:
      self = .overlay(
        OverlayRequest(
          id: overlay.id, generation: overlay.generation,
          presentation: KarnakPresentation(overlay.stack.presentation),
          stack: ControllerStack(overlay.stack, session: makeSession)))
    case let dismiss as Dismiss:
      self = .dismiss(id: dismiss.id)
    default:
      return nil
    }
  }
}
