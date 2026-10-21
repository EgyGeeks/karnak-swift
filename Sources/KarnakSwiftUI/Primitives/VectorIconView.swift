import KarnakCore
import SwiftUI

/// An icon in its square box (`docs/renderer-contract.md`, `ResolvedIcon`): the engine's parsed
/// vector scaled from its viewport to the box and filled with the tint, each path with its own
/// fill rule. A missing vector draws an empty box of the same size. Icons are decorative, as
/// the node's semantics name the control, and are never mirrored in RTL.
struct VectorIconView: View {
  /// The icon's paths, converted once.
  let glyph: VectorGlyph?
  /// The box's side in points.
  let size: CGFloat
  /// The fill color.
  let tint: Color

  init(_ icon: ResolvedIcon) {
    glyph = icon.vector.flatMap(VectorGlyph.init)
    size = points(dp: icon.size)
    tint = resolvedColor(icon.tint)
  }

  var body: some View {
    ZStack {
      if let glyph {
        ForEach(glyph.paths.indices, id: \.self) { index in
          let path = glyph.paths[index]
          ViewportShape(path: path.path, viewport: glyph.viewport)
            .fill(tint, style: FillStyle(eoFill: path.evenOdd))
        }
      }
    }
    // SwiftUI mirrors drawing in a right-to-left subtree; icons keep their drawn direction.
    .environment(\.layoutDirection, .leftToRight)
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

/// A `ResolvedVector` as SwiftUI paths in viewport coordinates.
struct VectorGlyph {
  /// One filled path.
  struct Part {
    let path: Path
    /// Whether the path fills by the even-odd rule rather than non-zero.
    let evenOdd: Bool
  }

  let paths: [Part]
  /// The coordinate space of ``paths``: `viewportWidth × viewportHeight` from the origin.
  let viewport: CGSize

  /// Nil for a viewport that isn't positive and finite, which the engine never emits.
  init?(_ vector: ResolvedVector) {
    let viewport = CGSize(
      width: CGFloat(vector.viewportWidth), height: CGFloat(vector.viewportHeight))
    guard viewport.width > 0, viewport.height > 0, viewport.width.isFinite,
      viewport.height.isFinite
    else { return nil }
    self.viewport = viewport
    paths = vector.paths.map {
      Part(path: Path(commands: $0.commands), evenOdd: $0.fillRule == .evenodd)
    }
  }
}

extension Path {
  /// The absolute commands of a `VectorPath`, in order. A command of a type a newer engine adds
  /// is skipped.
  init(commands: [PathCommand]) {
    self.init()
    for command in commands {
      switch command {
      case let start as PathCommandMoveTo:
        move(to: point(start.x, start.y))
      case let segment as PathCommandLineTo:
        addLine(to: point(segment.x, segment.y))
      case let curve as PathCommandCubicTo:
        addCurve(
          to: point(curve.x, curve.y), control1: point(curve.x1, curve.y1),
          control2: point(curve.x2, curve.y2))
      case is PathCommandClose:
        closeSubpath()
      default:
        break
      }
    }
  }
}

private func point(_ horizontal: Float, _ vertical: Float) -> CGPoint {
  CGPoint(x: CGFloat(horizontal), y: CGFloat(vertical))
}

/// A path in viewport coordinates, scaled to fill the frame it's drawn in.
struct ViewportShape: Shape {
  let path: Path
  let viewport: CGSize

  func path(in rect: CGRect) -> Path {
    path.applying(
      CGAffineTransform(translationX: rect.minX, y: rect.minY)
        .scaledBy(x: rect.width / viewport.width, y: rect.height / viewport.height))
  }
}
