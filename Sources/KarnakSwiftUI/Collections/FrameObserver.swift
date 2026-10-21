import SwiftUI

extension EnvironmentValues {
  /// Receives the frame, in window coordinates, of each node a lazy list draws and of each labelled node, by key.
  /// Nil outside the conformance runner: a UIKit-backed `ScrollView` keeps its content out of an in-process
  /// accessibility traversal, and a labelled container's accessibility frame is the union of its accessible
  /// children, so the runner reads where those nodes are from the renderer's own geometry reports.
  @Entry var karnakFrameObserver: ((String, CGRect) -> Void)?
  /// Whether every labelled node reports its frame to ``karnakFrameObserver``, not only a lazy collection's: the nodes
  /// inside a carousel's items are out of reach of an accessibility traversal, labelled or not.
  @Entry var karnakReportsLabelledFrames = false
}

/// Reports a node's frame to ``EnvironmentValues/karnakFrameObserver``; it does nothing without
/// one.
struct FrameReport: ViewModifier {
  /// The node's key.
  let key: String
  @Environment(\.karnakFrameObserver) private var observer

  func body(content: Content) -> some View {
    if let observer {
      content.onGeometryChange(for: CGRect.self) {
        $0.frame(in: .global)
      } action: {
        observer(key, $0)
      }
    } else {
      content
    }
  }
}
