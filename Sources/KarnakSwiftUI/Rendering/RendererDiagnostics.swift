import KarnakCore
import OSLog

/// Renderer problems worth a log line; they never throw or change what is drawn.
enum RendererDiagnostics {
  private static let logger = Logger(subsystem: "com.egygeeks.karnak", category: "renderer")

  /// The default destination: the unified system log.
  static let systemLog: @Sendable (String) -> Void = { message in
    logger.error("\(message, privacy: .public)")
  }

  /// Reports every node in `screen` that ``NodeView`` skips, once per tree
  /// (`docs/renderer-contract.md`, Principles: skipped and reported, never thrown on).
  static func reportUnsupported(in screen: ResolvedScreen, to log: (String) -> Void) {
    guard let root = screen.root else { return }
    var pending: [ResolvedNode] = [root]
    while let node = pending.popLast() {
      let kind = NodeKind(node)
      if case .unsupported = kind {
        log(
          "Karnak: skipped node \(node.key.value) of unsupported type \(type(of: node)) "
            + "in screen \(screen.screenId); see docs/renderer-contract.md#principles.")
      }
      pending.append(contentsOf: kind.children.reversed())
    }
  }
}
