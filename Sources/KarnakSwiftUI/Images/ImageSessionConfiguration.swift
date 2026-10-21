import Foundation
import os

/// The isolated session setup behind `URLSessionImageLoader`: a dedicated cache store per
/// directory and a configuration that never shares the host's cookies or credentials.
enum ImageSessionConfiguration {
  /// `Caches/com.egygeeks.karnak.images`, kept apart from `URLCache.shared` and the host's HTTP
  /// cache.
  static var defaultCacheDirectory: URL {
    URL.cachesDirectory.appending(path: "com.egygeeks.karnak.images", directoryHint: .isDirectory)
  }

  // One URLCache per directory: two instances on one store would each enforce their own
  // capacity against the same files.
  private static let caches = OSAllocatedUnfairLock<[URL: SharedImageCache]>(initialState: [:])

  /// Returns the process-wide cache for `directory`, creating it with these capacities on first
  /// use. Later calls for the same directory reuse that cache and its original capacities.
  static func cache(directory: URL, memoryCapacity: Int, diskCapacity: Int) -> SharedImageCache {
    let key = directory.standardizedFileURL
    return caches.withLock { caches in
      if let existing = caches[key] { return existing }
      let shared = SharedImageCache(
        directory: key, memoryCapacity: max(0, memoryCapacity),
        diskCapacity: max(0, diskCapacity))
      caches[key] = shared
      return shared
    }
  }

  /// HTTP-cache-aware configuration that sends no cookies or stored credentials to image hosts,
  /// which remote screen content chooses.
  static func make(cache: URLCache) -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.default
    configuration.urlCache = cache
    configuration.requestCachePolicy = .useProtocolCachePolicy
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.urlCredentialStorage = nil
    return configuration
  }
}

/// A directory's `URLCache` and the capacities its first loader asked for. Conflicts compare
/// requests, not the cache's own values, which URLCache may adjust (iOS raises a small disk
/// capacity).
struct SharedImageCache: @unchecked Sendable {
  // URLCache is thread-safe; the capacities are immutable.
  let cache: URLCache
  let memoryCapacity: Int
  let diskCapacity: Int

  fileprivate init(directory: URL, memoryCapacity: Int, diskCapacity: Int) {
    cache = URLCache(
      memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, directory: directory)
    self.memoryCapacity = memoryCapacity
    self.diskCapacity = diskCapacity
  }

  /// A diagnostic when a loader asks for capacities other than the ones in use; nil when they
  /// match, as they do for the loader that created the cache. Negative requests count as zero.
  func conflict(memoryCapacity memory: Int, diskCapacity disk: Int) -> String? {
    guard max(0, memory) != memoryCapacity || max(0, disk) != diskCapacity else { return nil }
    return "Image cache capacities ignored: another loader already uses this cacheDirectory with "
      + "\(memoryCapacity) bytes of memory and \(diskCapacity) bytes of disk, and this loader "
      + "shares them. Pass a separate cacheDirectory for different capacities."
  }
}
