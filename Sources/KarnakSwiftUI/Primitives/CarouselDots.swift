import KarnakCore
import SwiftUI

/// What the dots show now: the state the carousel draws them from, reported to ``EnvironmentValues/karnakDotsObserver``.
struct CarouselDotsDrawing {
  let indicator: ResolvedCarouselIndicator
  let count: Int
  let current: Int
  /// The width of the row, in points.
  let width: CGFloat
}

extension EnvironmentValues {
  /// Receives, by the carousel's key, what the dots of each carousel show. Nil outside the conformance runner: a window
  /// without a scene is not composited, so its pixels can't be read, and the runner draws the dots again from this.
  @Entry var karnakDotsObserver: ((String, CarouselDotsDrawing) -> Void)?
}

/// The dots below a carousel's items (`docs/renderer-contract.md`, Display primitives, `carousel`): one per item,
/// centred, the current one in `selectedColor`. They are decorative, so hidden from accessibility, and they change at
/// once: nothing animates, with or without reduced motion.
struct CarouselDots: View {
  let key: String
  let indicator: ResolvedCarouselIndicator
  let count: Int
  let current: Int
  @Environment(\.layoutDirection) private var direction
  @Environment(\.karnakDotsObserver) private var observer
  @State private var width: CGFloat = 0

  var body: some View {
    let dot = points(dp: indicator.dotSize)
    let gap = points(dp: indicator.gap)
    let selected = resolvedColor(indicator.selectedColor)
    let other = resolvedColor(indicator.color)
    Canvas { context, size in
      let starts = carouselDotStarts(
        count: count, dot: dot, gap: gap, width: size.width, current: current)
      for (index, start) in starts.enumerated() {
        let left = direction == .rightToLeft ? size.width - start - dot : start
        let rect = CGRect(x: left, y: (size.height - dot) / 2, width: dot, height: dot)
        context.fill(Path(ellipseIn: rect), with: .color(index == current ? selected : other))
      }
    }
    .accessibilityHidden(true)
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      width = $0
    }
    .onAppear { report(shown) }
    .onChange(of: shown) { report($0) }
  }

  /// What the dots show now, which the observer is told each time it changes.
  private var shown: Shown { Shown(width: width, current: current, count: count) }

  private struct Shown: Equatable {
    let width: CGFloat
    let current: Int
    let count: Int
  }

  private func report(_ shown: Shown) {
    observer?(
      key,
      CarouselDotsDrawing(
        indicator: indicator, count: shown.count, current: shown.current, width: shown.width))
  }
}
