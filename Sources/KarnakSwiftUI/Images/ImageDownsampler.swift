import Foundation
import ImageIO

enum ImageDownsampler {
  enum Outcome: Sendable {
    case image(CGImage)
    case tooManyPixels
    case unreadable
  }

  /// Sources declaring more than `limits.maxSourcePixels` are refused before decoding, and the
  /// image decodes to about `limits.maxDecodePixels` at most, whatever the request's box.
  static func decode(_ data: Data, request: ImageRequest, limits: ImageLimits) -> Outcome {
    guard
      let source = CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Double,
      let height = properties[kCGImagePropertyPixelHeight] as? Double,
      width > 0, height > 0
    else { return .unreadable }
    guard width * height <= Double(limits.maxSourcePixels) else { return .tooManyPixels }
    let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
    let rotated = (5...8).contains(orientation)
    let ratio = scale(
      width: rotated ? height : width, height: rotated ? width : height, request: request)
    let maximum = longestSide(
      width: width * ratio, height: height * ratio, maxDecodePixels: limits.maxDecodePixels)
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

  /// The longest side to decode an image of this scaled size at: its own, rounded up so a covering
  /// image is never a pixel short of its box, or a smaller one of the same shape when the image
  /// would pass `maxDecodePixels`. That one rounds down, so the decode stays within the budget
  /// but for ImageIO's rounding of the shorter side (under one row or column of pixels).
  private static func longestSide(width: Double, height: Double, maxDecodePixels: Int) -> Double {
    let longest = max(width, height)
    let pixels = width * height
    guard pixels > Double(maxDecodePixels) else { return max(1, longest.rounded(.up)) }
    return max(1, (longest * (Double(maxDecodePixels) / pixels).squareRoot()).rounded(.down))
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
