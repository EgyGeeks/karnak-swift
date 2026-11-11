import KarnakCore
import SwiftUI

/// The space between a tooltip and its node, and between a tooltip and the screen's edge.
let tooltipGap: CGFloat = 8

/// The widest a tooltip grows before its text wraps.
let tooltipMaxWidth: CGFloat = 280

extension View {
  /// Draws the tooltip a node of this screen shows over everything, floating views included
  /// (`docs/renderer-contract.md`, Tooltips and cursors). The bubble takes no touches and is no accessibility
  /// element: VoiceOver reads the text as the node's hint.
  func tooltipLayer() -> some View {
    overlayPreferenceValue(TooltipAnchorKey.self) { shown in
      GeometryReader { proxy in
        if let shown {
          TooltipPlacement(anchor: proxy[shown.anchor]) { TooltipBubble(tooltip: shown.tooltip) }
            .transition(.opacity)
        }
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }
}

private struct TooltipBubble: View {
  let tooltip: ResolvedTooltip
  @Environment(\.karnakFonts) private var fonts
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Text(tooltip.text)
      .font(font)
      .foregroundStyle(resolvedColor(tooltip.content))
      .padding(.horizontal, tooltipGap)
      .padding(.vertical, tooltipGap / 2)
      .background(
        resolvedColor(tooltip.background),
        in: RoundedRectangle(cornerRadius: CGFloat(tooltip.radius)))
  }

  private var font: Font {
    let traits = UITraitCollection(
      preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
    return resolvedFont(
      tooltip.font, scaledPoints: textPoints(sp: tooltip.font.size, traits: traits),
      postScriptName: tooltip.font.face.flatMap { fonts?.postScriptName(for: $0) })
  }
}

/// Places the bubble 8 points above `anchor` and centred on it, below when it doesn't fit above, and kept 8 points
/// inside the screen.
private struct TooltipPlacement: Layout {
  let anchor: CGRect

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    proposal.replacingUnspecifiedDimensions()
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    guard let bubble = subviews.first else { return }
    let inside = bounds.insetBy(dx: tooltipGap, dy: tooltipGap)
    let width = min(tooltipMaxWidth, max(inside.width, 0))
    let size = bubble.sizeThatFits(ProposedViewSize(width: width, height: nil))
    let origin = tooltipOrigin(
      anchor: anchor.offsetBy(dx: bounds.minX, dy: bounds.minY), size: size, inside: inside)
    bubble.place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(size))
  }
}

/// Where a bubble of `size` goes for a node at `anchor`: above it, else below when only that fits, centred along it
/// and moved to stay in `inside`.
func tooltipOrigin(anchor: CGRect, size: CGSize, inside: CGRect) -> CGPoint {
  let above = anchor.minY - tooltipGap - size.height
  let below = anchor.maxY + tooltipGap
  let fitsAbove = above >= inside.minY
  let fitsBelow = below + size.height <= inside.maxY
  let y = fitsAbove || !fitsBelow ? above : below
  let x = min(max(anchor.midX - size.width / 2, inside.minX), inside.maxX - size.width)
  return CGPoint(x: x, y: min(max(y, inside.minY), inside.maxY - size.height))
}
