import KarnakCore
import SwiftUI

extension View {
  /// Presents the effects of `model` over this view: a toast overlay, a system alert for a
  /// dialog and a sheet with detents for a sheet.
  func presentingEffects(_ model: EffectModel) -> some View {
    modifier(EffectsPresentation(model: model))
  }
}

/// A toast overlay, an alert and a sheet for what one screen instance asks to present
/// (`docs/renderer-contract.md`, Effects). The alert keeps the system look and ignores the
/// engine's `EffectStyle`; the toast is drawn from it.
private struct EffectsPresentation: ViewModifier {
  @ObservedObject var model: EffectModel
  @Environment(\.karnakFonts) private var fonts
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @StateObject private var toastWindow = ToastWindow()

  func body(content: Content) -> some View {
    content
      .background(OverlayPresentation(model: model))
      // The toast lives in a window of its own, so it sits at the bottom of the display even
      // when this screen is the tall content of a scroll view. Without a scene (tests), it is
      // an overlay of the screen.
      .task(id: model.toast?.id) {
        toastWindow.show(model.toast, fonts: fonts, dynamicTypeSize: dynamicTypeSize)
      }
      .onDisappear { toastWindow.show(nil, fonts: fonts, dynamicTypeSize: dynamicTypeSize) }
      .overlay(alignment: .bottom) {
        if let toast = model.toast, !toastWindow.isPresenting {
          ToastView(toast: toast).id(toast.id).padding(.bottom, 24).padding(.horizontal, 16)
            .allowsHitTesting(false)
        }
      }
      .alert(
        model.dialog.map { $0.title ?? $0.message } ?? "",
        isPresented: Binding(
          get: { model.dialog != nil },
          set: { if !$0 { model.dialogWentAway() } }),
        presenting: model.dialog
      ) { dialog in
        if let dismiss = dialog.dismiss {
          Button(dismiss, role: .cancel) { model.choose(.dismiss) }
        }
        Button(dialog.confirm) { model.choose(.confirm) }
      } message: { dialog in
        if dialog.title != nil { Text(dialog.message) }
      }
      .sheet(
        item: Binding(
          get: { model.sheet },
          set: { if $0 == nil, let open = model.sheet { model.sheetClosedByUser(id: open.id) } })
      ) { presented in
        SheetScreenView(model: presented.model)
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
      }
  }
}

/// A transient message near the bottom, in the theme's surface, text color and body font. It is
/// announced to VoiceOver when it appears (``EffectModel``), and never takes a touch.
struct ToastView: View {
  let toast: ToastRequest
  @Environment(\.karnakFonts) private var fonts
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let appearance = toast.appearance
    Text(toast.message)
      .font(font(appearance))
      .foregroundColor(resolvedColor(argb: appearance.onSurface))
      .multilineTextAlignment(.leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(resolvedColor(argb: appearance.surface))
          .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
      )
      .frame(maxWidth: 560)
      .accessibilityElement(children: .combine)
  }

  private func font(_ appearance: EffectAppearance) -> Font {
    guard let body = appearance.body else { return .body }
    let points = textPoints(
      sp: body.size,
      traits: UITraitCollection(
        preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize)))
    return resolvedFont(
      body, scaledPoints: points,
      postScriptName: body.face.flatMap { (fonts ?? .unavailable).postScriptName(for: $0) })
  }
}
