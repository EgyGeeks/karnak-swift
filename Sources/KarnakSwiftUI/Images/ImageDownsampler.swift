import Foundation
import ImageIO

enum ImageDownsampler {
  enum Outcome {
    case image(CGImage)
    case tooManyPixels
    case unreadable
  }

  /// Sources declaring more than `maxSourcePixels` are refused before decoding.
  static func decode(_ data: Data, request: ImageRequest, maxSourcePixels: Int) -> Outcome {
    guard
      let source = CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Double,
      let height = properties[kCGImagePropertyPixelHeight] as? Double,
      width > 0, height > 0
    else { return .unreadable }
    guard width * height <= Double(maxSourcePixels) else { return .tooManyPixels }
    let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
    let rotated = (5...8).contains(orientation)
    let ratio = scale(
      width: rotated ? height : width, height: rotated ? width : height, request: request)
    let maximum = max(1, (max(width, height) * ratio).rounded(.up))
    let thumbnail = CGImageSourceCreateThumbnailAtIndex(
      source, 0,
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maximum,
      ] as CFDictionary)
    return thumbnail.map(Outcome.image) ?? .unreadable
  }

  /// The factor from the oriented source to the target; at most 1, so images never upscale.
  private static func scale(width: Double, height: Double, request: ImageRequest) -> Double {
    let horizontal = Double(request.width) / width
    let vertical = Double(request.height) / height
    switch request.scaling {
    case .fit: return min(1, horizontal, vertical)
    case .fill: return min(1, max(horizontal, vertical))
    }
  }
}
