import KarnakCore
import SwiftUI
import UIKit

/// `canvas`: the node's draw list in a SwiftUI `Canvas` (`docs/renderer-contract.md`, Canvas; ADR 0037, D12 and D20),
/// drawn in the view box's space scaled to the node's box by `contentScale`, clipped to the box and flipped when
/// `mirrorInRtl` and the layout is right-to-left. A canvas with a loop is redrawn by a `TimelineView(.animation)`
/// that runs only while the canvas is on screen and in the foreground and Reduce Motion is off; a canvas that isn't
/// running draws every loop at its `rest`. To assistive technology it is the node's one image (`semantics`); its ops
/// are never exposed.
struct CanvasView: View {
  /// The canvas.
  let canvas: ResolvedCanvas
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.displayScale) private var displayScale
  @Environment(\.karnakFonts) private var fonts
  @Environment(\.karnakImageLoader) private var loader
  @State private var onScreen = true
  @State private var box = CGSize.zero
  @State private var images = CanvasImages()

  var body: some View {
    TimelineView(.animation(paused: !running)) { timeline in
      Canvas { context, size in
        draw(into: &context, size: size, at: timeline.date)
      }
    }
    .onGeometryChange(for: CGSize.self, of: \.size) { box = $0 }
    .onAppear { onScreen = true }
    .onDisappear { onScreen = false }
    .task(id: ImageKey(canvas: canvas, box: box)) {
      await images.load(canvas, box: box, scale: displayScale, loader: loader)
    }
    .accessibilityElement(children: .ignore)
  }

  private var running: Bool { canvas.loops && onScreen && scenePhase == .active && !reduceMotion }

  private var viewBox: CGSize {
    CGSize(width: canvas.viewBoxWidth, height: canvas.viewBoxHeight)
  }

  private func draw(into context: inout GraphicsContext, size: CGSize, at date: Date) {
    guard size.width > 0, size.height > 0, viewBox.width > 0, viewBox.height > 0 else { return }
    let scale = Self.scale(canvas.contentScale, viewBox: viewBox, box: size)
    let mirrored = canvas.mirrorInRtl && layoutDirection == .rightToLeft
    var frame = CanvasFrame(
      values: DrawValues(
        nowMillis: Int64((date.timeIntervalSinceReferenceDate * 1000).rounded()),
        running: running),
      bounds: CGRect(origin: .zero, size: viewBox), scale: scale, mirrored: mirrored,
      rightToLeft: layoutDirection == .rightToLeft, font: font(of:),
      image: { images.image(for: $0) })
    context.clip(to: Path(CGRect(origin: .zero, size: size)))
    if mirrored {
      context.translateBy(x: size.width, y: 0)
      context.scaleBy(x: -1, y: 1)
    }
    context.translateBy(
      x: (size.width - viewBox.width * scale.width) / 2,
      y: (size.height - viewBox.height * scale.height) / 2)
    context.scaleBy(x: scale.width, y: scale.height)
    CanvasPainter(frame: frame).draw(canvas.draw, into: &context)
  }

  private func font(of font: ResolvedFont) -> Font {
    let traits = UITraitCollection(
      preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
    return resolvedFont(
      font, scaledPoints: textPoints(sp: font.size, traits: traits),
      postScriptName: font.face.flatMap { fonts?.postScriptName(for: $0) })
  }

  /// The scale from the view box to `box` that `mode` draws with, per axis: `fit` and `crop` keep the aspect ratio.
  static func scale(_ mode: ContentScale, viewBox: CGSize, box: CGSize) -> CGSize {
    let x = box.width / viewBox.width
    let y = box.height / viewBox.height
    switch mode {
    case .fit: return CGSize(width: min(x, y), height: min(x, y))
    case .crop: return CGSize(width: max(x, y), height: max(x, y))
    default: return CGSize(width: x, height: y)
    }
  }
}

/// What a canvas's images are loaded for: the canvas and the size it is drawn at, which decide their pixel size.
private struct ImageKey: Hashable {
  let canvas: ResolvedCanvas
  let box: CGSize
}
