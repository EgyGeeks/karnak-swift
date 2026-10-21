import CoreGraphics
import Foundation
import OSLog

/// Built-in HTTPS image adapter with bounded URLCache storage, a decoded-image memory cache and
/// coalesced, cancellable loads.
public actor URLSessionImageLoader: KarnakImageLoader {
  /// The renderer's loader when the host injects none (``SwiftUI/View/karnakImageLoader(_:)``). It adopts the capacities of a
  /// host loader created first on the default directory, without a diagnostic: the host chose them.
  static let shared = adopting(
    cacheDirectory: ImageSessionConfiguration.defaultCacheDirectory, diagnostic: logDiagnostic)

  /// 20 MiB of memory for encoded responses, the default of `init(memoryCapacity:)`.
  @usableFromInline static let defaultMemoryCapacity = 20 * 1024 * 1024
  /// 100 MiB of disk for encoded responses, the default of `init(diskCapacity:)`.
  @usableFromInline static let defaultDiskCapacity = 100 * 1024 * 1024
  /// 50 MiB of decoded pixels, the default of `init(decodedImageCapacity:)`.
  @usableFromInline static let defaultDecodedImageCapacity = 50 * 1024 * 1024
  /// Writes diagnostics to the system log, the default of `init(diagnostic:)`.
  @usableFromInline static let logDiagnostic: @Sendable (String) -> Void = { message in
    Logger(subsystem: "com.egygeeks.karnak.swiftui", category: "images").warning(
      "\(message, privacy: .public)")
  }

  private struct Flight {
    let id: UUID
    let task: Task<Void, Never>
    var callers: [UUID: CheckedContinuation<CGImage?, Never>]
  }

  /// Immutable and Sendable, so tests read its configuration without hopping to the actor.
  nonisolated let session: URLSession
  /// Read synchronously by `cachedImage(for:targetPixelSize:scaling:)`; it has its own lock.
  nonisolated let decoded: DecodedImageCache
  private let download: ImageDownload
  private var flights: [ImageRequest: Flight] = [:]

  var activeCallerCount: Int { flights.values.reduce(0) { $0 + $1.callers.count } }

  /// Creates a private session with HTTP-aware memory/disk caching (20 MiB / 100 MiB by default).
  /// Decoded images are also kept in memory, up to `decodedImageCapacity` bytes of pixels (50 MiB
  /// by default), and dropped on a memory warning.
  /// Capacities are bytes; zero disables that cache, and negative values become zero.
  /// Disk storage defaults to `Caches/com.egygeeks.karnak.images`, apart from `URLCache.shared`;
  /// `cacheDirectory` overrides it.
  /// Loaders with the same directory share one cache, sized by the first loader created for it;
  /// a later loader asking for other capacities emits a diagnostic naming the ones in use.
  /// The session sends no cookies or stored credentials to image hosts. Responses over
  /// `maxImageBytes` (20 MiB by default) are rejected, and reading stops once it is passed.
  /// Diagnostics omit URLs and run off the main actor; the default writes to the system log.
  public init(
    memoryCapacity: Int = defaultMemoryCapacity,
    diskCapacity: Int = defaultDiskCapacity,
    decodedImageCapacity: Int = defaultDecodedImageCapacity,
    cacheDirectory: URL? = nil,
    maxImageBytes: Int = ImageLimits.defaultMaxBytes,
    diagnostic: @escaping @Sendable (String) -> Void = logDiagnostic
  ) {
    self.init(
      cacheDirectory: cacheDirectory ?? ImageSessionConfiguration.defaultCacheDirectory,
      capacities: (memoryCapacity, diskCapacity), reportsConflict: true,
      limits: ImageLimits(maxBytes: max(0, maxImageBytes)),
      decodedImageCapacity: decodedImageCapacity, diagnostic: diagnostic)
  }

  /// A default-sized loader on `cacheDirectory` that silently adopts an existing cache there.
  static func adopting(
    cacheDirectory: URL, diagnostic: @escaping @Sendable (String) -> Void
  ) -> URLSessionImageLoader {
    URLSessionImageLoader(
      cacheDirectory: cacheDirectory, capacities: (defaultMemoryCapacity, defaultDiskCapacity),
      reportsConflict: false, limits: ImageLimits(),
      decodedImageCapacity: defaultDecodedImageCapacity, diagnostic: diagnostic)
  }

  /// The one setup behind the public init and `adopting`: they differ only in `reportsConflict`.
  private init(
    cacheDirectory: URL, capacities: (memory: Int, disk: Int), reportsConflict: Bool,
    limits: ImageLimits, decodedImageCapacity: Int,
    diagnostic: @escaping @Sendable (String) -> Void
  ) {
    let shared = ImageSessionConfiguration.cache(
      directory: cacheDirectory, memoryCapacity: capacities.memory, diskCapacity: capacities.disk)
    self.init(
      configuration: ImageSessionConfiguration.make(cache: shared.cache), limits: limits,
      decodedImageCapacity: decodedImageCapacity, diagnostic: diagnostic)
    let conflict = shared.conflict(
      memoryCapacity: capacities.memory, diskCapacity: capacities.disk)
    if reportsConflict, let conflict {
      // Like every other diagnostic, off the caller's thread: hosts often create loaders on the
      // main actor, and a diagnostic closure may block or hop to it.
      Task.detached { [download] in download.report(conflict) }
    }
  }

  init(
    configuration: URLSessionConfiguration, limits: ImageLimits = ImageLimits(),
    decodedImageCapacity: Int = defaultDecodedImageCapacity,
    diagnostic: @escaping @Sendable (String) -> Void
  ) {
    decoded = DecodedImageCache(capacity: decodedImageCapacity)
    session = URLSession(
      configuration: configuration, delegate: HTTPSImageSessionDelegate(diagnostic: diagnostic),
      delegateQueue: nil)
    download = ImageDownload(session: session, limits: limits, diagnostic: diagnostic)
  }

  deinit { session.invalidateAndCancel() }

  /// Returns a downsampled image, or nil on failure/cancellation. Loads with equal URL, rounded
  /// size and scaling share work, and a decoded image kept from an earlier load returns at once.
  public func image(
    for url: URL, targetPixelSize: CGSize, scaling: KarnakImageScaling
  ) async -> CGImage? {
    guard !Task.isCancelled else { return nil }
    guard url.scheme?.lowercased() == "https" else {
      download.report("Image rejected: use an HTTPS URL.")
      return nil
    }
    guard let request = ImageRequest(url: url, size: targetPixelSize, scaling: scaling) else {
      download.report(
        "Image rejected: pixel dimensions must be finite, positive and at most "
          + "\(ImageRequest.maxPixelDimension).")
      return nil
    }
    if let kept = decoded.image(for: request) { return kept }
    let caller = UUID()
    let result = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if var flight = flights[request] {
          flight.callers[caller] = continuation
          flights[request] = flight
        } else {
          let id = UUID()
          let task = Task { [weak self, download] in
            let image = await download.image(for: request)
            await self?.finish(request, id: id, image: image)
          }
          flights[request] = Flight(id: id, task: task, callers: [caller: continuation])
        }
      }
    } onCancel: {
      Task { await self.cancel(request, caller: caller) }
    }
    return Task.isCancelled ? nil : result
  }

  /// The decoded image kept from an earlier load with equal URL, rounded size and scaling, or nil.
  /// Never loads, decodes or reports.
  public nonisolated func cachedImage(
    for url: URL, targetPixelSize: CGSize, scaling: KarnakImageScaling
  ) -> CGImage? {
    guard url.scheme?.lowercased() == "https",
      let request = ImageRequest(url: url, size: targetPixelSize, scaling: scaling)
    else { return nil }
    return decoded.image(for: request)
  }

  private func cancel(_ request: ImageRequest, caller: UUID) {
    guard var flight = flights[request] else { return }
    flight.callers.removeValue(forKey: caller)?.resume(returning: nil)
    if flight.callers.isEmpty {
      flights.removeValue(forKey: request)
      flight.task.cancel()
    } else {
      flights[request] = flight
    }
  }

  private func finish(_ request: ImageRequest, id: UUID, image: CGImage?) {
    guard let flight = flights[request], flight.id == id else { return }
    flights.removeValue(forKey: request)
    // Only finished loads get here: a flight whose callers all cancelled was already removed.
    if let image { decoded.store(image, for: request) }
    for continuation in flight.callers.values { continuation.resume(returning: image) }
  }
}
