import CoreGraphics
import Foundation
import UIKit

/// Decoded images kept in memory by `ImageRequest`, so an image view that re-appears or asks for a
/// size it had before skips both the network and ImageIO. Bounded by decoded bytes, evicting the
/// least recently used, and emptied when the system warns about memory.
final class DecodedImageCache: @unchecked Sendable {
  private struct Entry {
    let image: CGImage
    let cost: Int
    /// The access clock at the last store or read; lower is less recently used.
    var lastUse: UInt64
  }

  /// The most bytes of decoded pixels kept; zero disables the cache.
  let capacity: Int
  // Read synchronously from view bodies and written from the loader actor, so a lock guards it.
  // Reads are O(1), since view bodies make them on the main thread; only a store that has to
  // evict sorts the entries.
  private let lock = NSLock()
  private var entries: [ImageRequest: Entry] = [:]
  private var clock: UInt64 = 0
  private var totalCost = 0
  private var memoryWarning: (any NSObjectProtocol)?

  init(capacity: Int) {
    self.capacity = max(0, capacity)
    memoryWarning = NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
    ) { [weak self] _ in
      self?.removeAll()
    }
  }

  deinit {
    if let memoryWarning { NotificationCenter.default.removeObserver(memoryWarning) }
  }

  /// Bytes of decoded pixels currently kept.
  var cost: Int { lock.withLock { totalCost } }

  /// The decoded bitmap's memory: bytes per row times rows.
  static func cost(of image: CGImage) -> Int { image.bytesPerRow * image.height }

  /// The kept image for `request`, which becomes the most recently used.
  func image(for request: ImageRequest) -> CGImage? {
    lock.withLock {
      guard entries[request] != nil else { return nil }
      clock += 1
      entries[request]?.lastUse = clock
      return entries[request]?.image
    }
  }

  /// Keeps `image`, evicting the least recently used until it fits. An image larger than the
  /// whole capacity isn't kept.
  func store(_ image: CGImage, for request: ImageRequest) {
    let cost = Self.cost(of: image)
    guard cost <= capacity else { return }
    lock.withLock {
      if let replaced = entries.removeValue(forKey: request) { totalCost -= replaced.cost }
      if totalCost + cost > capacity { evict(toFit: cost) }
      clock += 1
      entries[request] = Entry(image: image, cost: cost, lastUse: clock)
      totalCost += cost
    }
  }

  func removeAll() {
    lock.withLock {
      entries.removeAll()
      totalCost = 0
    }
  }

  /// Drops the least recently used entries until `cost` more bytes fit. Called with the lock held.
  private func evict(toFit cost: Int) {
    for (request, entry) in entries.sorted(by: { $0.value.lastUse < $1.value.lastUse }) {
      guard totalCost + cost > capacity else { return }
      entries.removeValue(forKey: request)
      totalCost -= entry.cost
    }
  }
}
