import Foundation

final class HTTPSImageSessionDelegate: NSObject, URLSessionTaskDelegate {
  let diagnostic: @Sendable (String) -> Void

  init(diagnostic: @escaping @Sendable (String) -> Void) {
    self.diagnostic = diagnostic
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    guard request.url?.scheme?.lowercased() == "https" else {
      diagnostic(
        "Image redirect rejected: use HTTPS for every redirect. See sdk/swiftui/README.md#images.")
      // Cancel rather than deliver the 3xx as the final response, so this is the only diagnostic.
      task.cancel()
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }
}
