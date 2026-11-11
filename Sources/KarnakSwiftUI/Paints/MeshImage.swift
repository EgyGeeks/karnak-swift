import CoreGraphics
import Foundation
import KarnakCore
import SwiftUI

/// A mesh ready to draw (`docs/renderer-contract.md`, Mesh paints): the engine's raster as an image this renderer
/// stretches over the box it paints, so it draws no patch itself. The image of a mesh is made once and kept.
struct MeshImage: Equatable {
  /// The mesh as the engine resolved it.
  let mesh: ResolvedPaintMesh

  init(_ mesh: ResolvedPaintMesh) { self.mesh = mesh }

  /// The raster as an image; nil when Core Graphics refuses it.
  var image: CGImage? { MeshImages.shared.image(of: mesh) }

  /// Fills `path` with the mesh stretched over `box`, its pixels filtered.
  func fill(_ path: Path, in box: CGRect, context: GraphicsContext) {
    guard box.width > 0, box.height > 0, let image else { return }
    var clipped = context
    clipped.clip(to: path)
    clipped.draw(Image(decorative: image, scale: 1).interpolation(.medium), in: box)
  }

  static func == (lhs: MeshImage, rhs: MeshImage) -> Bool { lhs.mesh.isEqual(rhs.mesh) }
}

/// The images of the meshes on screen, by mesh: equal meshes share one image.
private final class MeshImages: @unchecked Sendable {
  static let shared = MeshImages()

  private let images = NSCache<ResolvedPaintMesh, CGImage>()

  private init() { images.countLimit = 64 }

  func image(of mesh: ResolvedPaintMesh) -> CGImage? {
    if let kept = images.object(forKey: mesh) { return kept }
    guard let image = MeshPixels(mesh.raster).image else { return nil }
    images.setObject(image, forKey: mesh)
    return image
  }
}

/// A raster's pixels as Core Graphics reads them: red, green, blue, alpha bytes with the alpha multiplied in, so
/// stretching the image mixes premultiplied colors as the other renderers do.
struct MeshPixels {
  /// The pixels of one side.
  let side: Int
  /// Four bytes a pixel, row by row from the top left.
  let bytes: [UInt8]

  init(_ raster: MeshRaster) {
    side = Int(raster.size)
    var bytes = [UInt8]()
    bytes.reserveCapacity(side * side * 4)
    for index in 0..<(side * side) {
      let argb = UInt32(bitPattern: raster.pixels.get(index: Int32(index)))
      let alpha = argb >> 24
      for shift: UInt32 in [16, 8, 0] {
        bytes.append(UInt8((((argb >> shift) & 0xFF) * alpha + 127) / 255))
      }
      bytes.append(UInt8(alpha))
    }
    self.bytes = bytes
  }

  /// The pixels as an sRGB image.
  var image: CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let provider = CGDataProvider(data: Data(bytes) as CFData)
    else { return nil }
    return CGImage(
      width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
      space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }
}
