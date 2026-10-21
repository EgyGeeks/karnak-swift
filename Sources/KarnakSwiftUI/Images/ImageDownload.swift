import CoreGraphics
import Foundation

/// Bounds on what an image host can make the loader read and decode.
@usableFromInline
struct ImageLimits: Sendable {
  /// 20 MiB: the byte cap here and the default of `URLSessionImageLoader.init(maxImageBytes:)`.
  @usableFromInline static let defaultMaxBytes = 20 * 1024 * 1024
  /// Larger responses are rejected, and reading stops once the cap is passed.
  var maxBytes = ImageLimits.defaultMaxBytes
  /// Sources declaring more pixels are refused before decoding: ImageIO can't subsample every
  /// format, so a small "decompression bomb" could otherwise force a huge decode. 50 megapixels
  /// admits 48 MP camera photos.
  var maxSourcePixels = 50_000_000
}

/// One network load and decode for `URLSessionImageLoader`. Remote screen content chooses image
/// URLs, so responses are bounded in bytes and in declared pixels, never trusted.
struct ImageDownload: Sendable {
  let session: URLSession
  let limits: ImageLimits
  let diagnostic: @Sendable (String) -> Void

  /// Returns the decoded image, or nil after emitting at most one diagnostic. Cancellation,
  /// including a redirect the session delegate rejected and already reported, stays silent.
  func image(for request: ImageRequest) async -> CGImage? {
    do {
      let data = try await ImageTransfer.body(
        of: request.url, in: session, maxBytes: limits.maxBytes)
      try Task.checkCancellation()
      return decode(data, request: request)
    } catch ImageTransfer.Failure.status {
      report("Image load failed: expected HTTP 2xx. Check the image endpoint.")
    } catch ImageTransfer.Failure.tooLarge {
      report(
        "Image rejected: the response is over \(limits.maxBytes) bytes. "
          + "Serve a smaller image or raise maxImageBytes.")
    } catch let error as URLError where error.code == .cancelled {
      // Cancelled by the caller or by the redirect check; neither is a download failure.
    } catch {
      if !Task.isCancelled {
        report("Image download failed: check connectivity and the HTTPS endpoint.")
      }
    }
    return nil
  }

  private func decode(_ data: Data, request: ImageRequest) -> CGImage? {
    let outcome = ImageDownsampler.decode(
      data, request: request, maxSourcePixels: limits.maxSourcePixels)
    switch outcome {
    case .image(let image):
      return Task.isCancelled ? nil : image
    case .tooManyPixels:
      report(
        "Image rejected: the source has over \(limits.maxSourcePixels) pixels. "
          + "Serve a smaller image.")
    case .unreadable:
      report("Image decode failed: provide supported image bytes.")
    }
    return nil
  }

  /// Emits `message` with the README link. Messages never include URLs.
  func report(_ message: String) {
    diagnostic("\(message) See sdk/swiftui/README.md#images.")
  }
}
