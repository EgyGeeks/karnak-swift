import Foundation

/// Reads one response body as the chunks URLSession delivers, instead of byte by byte, and stops
/// the transfer as soon as the body passes the byte cap.
final class ImageTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  enum Failure: Error {
    /// The response wasn't HTTP 2xx.
    case status
    /// The declared length or the bytes received passed the cap.
    case tooLarge
  }

  private struct State {
    var body = Data()
    var failure: Failure?
    var continuation: CheckedContinuation<Data, any Error>?
    /// Set when the task completes before the caller starts waiting, as a task cancelled before
    /// it resumes can.
    var outcome: Result<Data, any Error>?
  }

  private let maxBytes: Int
  // URLSession calls the delegate on its own queue; the lock also covers the start of the load.
  private let lock = NSLock()
  private var state = State()

  private init(maxBytes: Int) {
    self.maxBytes = maxBytes
  }

  /// The body of `url`, bounded by `maxBytes`. Task cancellation cancels the transfer, which
  /// throws `URLError.cancelled`. A completed read is left alone so the cache can store it.
  static func body(of url: URL, in session: URLSession, maxBytes: Int) async throws -> Data {
    let transfer = ImageTransfer(maxBytes: maxBytes)
    let task = session.dataTask(with: url)
    // The task delegate receives the body; the session delegate still vets redirects.
    task.delegate = transfer
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        transfer.wait(with: continuation)
        task.resume()
      }
    } onCancel: {
      task.cancel()
    }
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    let failure = Self.check(response, maxBytes: maxBytes)
    lock.withLock {
      state.failure = failure
      // Reserve only a length within the cap. -1 means unknown; each chunk is still checked.
      guard failure == nil else { return }
      state.body.reserveCapacity(Int(max(0, response.expectedContentLength)))
    }
    completionHandler(failure == nil ? .allow : .cancel)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    let passedCap = lock.withLock {
      // Chunks can still arrive after a rejection, until the cancellation takes effect.
      guard state.failure == nil else { return false }
      // Check before copying, so a chunk that crosses the cap is never held.
      guard state.body.count + data.count <= maxBytes else {
        state.failure = .tooLarge
        return true
      }
      state.body.append(data)
      return false
    }
    if passedCap { dataTask.cancel() }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
  ) {
    let (continuation, outcome) = lock.withLock {
      let failure = state.failure.map { $0 as any Error } ?? error
      let outcome = failure.map { Result<Data, any Error>.failure($0) } ?? .success(state.body)
      let continuation = state.continuation
      state = State()
      if continuation == nil { state.outcome = outcome }
      return (continuation, outcome)
    }
    continuation?.resume(with: outcome)
  }

  private func wait(with continuation: CheckedContinuation<Data, any Error>) {
    let outcome = lock.withLock {
      if state.outcome == nil { state.continuation = continuation }
      return state.outcome
    }
    if let outcome { continuation.resume(with: outcome) }
  }

  private static func check(_ response: URLResponse, maxBytes: Int) -> Failure? {
    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode)
    else { return .status }
    return response.expectedContentLength > Int64(maxBytes) ? .tooLarge : nil
  }
}
