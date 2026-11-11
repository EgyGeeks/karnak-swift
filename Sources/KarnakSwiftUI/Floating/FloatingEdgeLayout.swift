import KarnakCore
import SwiftUI

/// What an edge or center view tells the layout that places it: everything the engine resolved about where it sits.
/// Immutable, so `@unchecked Sendable` holds though the Kotlin enum it carries has no conformance.
struct FloatingSlot: Equatable, @unchecked Sendable {
  let key: String
  let group: StackGroup
  /// `true` at the top edge, `false` at the bottom one, nil at the center.
  let top: Bool?
  let align: ResolvedFloatingPlacementAlign
  let fills: Bool
  let margin: CGFloat
  let offset: CGSize

  init(_ view: ResolvedFloating) {
    key = view.key
    group = view.stackGroup
    let edge = view.edge
    top = edge.map(\.top)
    align = edge?.align ?? .center
    fills = edge?.align == .fill
    margin = edge.map { points(dp: $0.margin) } ?? 0
    offset =
      edge.map { CGSize(width: points(dp: $0.offsetX), height: points(dp: $0.offsetY)) } ?? .zero
  }
}

private struct FloatingSlotKey: LayoutValueKey {
  static let defaultValue: FloatingSlot? = nil
}

extension View {
  /// Marks a view of the layer's own layout with its ``FloatingSlot``.
  func floatingSlot(_ slot: FloatingSlot) -> some View {
    layoutValue(key: FloatingSlotKey.self, value: slot)
  }
}

/// Places the views that sit at the screen's edges or its center (ADR 0038, D4 and D6): at their margin, aligned,
/// offset, and stacked away from the edge by ``FloatingGeometry/stackDistances(_:gap:)``. A change of the stack
/// (a view shown, ended or resized) animates in the transaction that caused it.
struct FloatingEdgeLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    proposal.replacingUnspecifiedDimensions()
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let placed: [Placed] = subviews.compactMap { subview in
      guard let slot = subview[FloatingSlotKey.self] else { return nil }
      return Placed(subview: subview, slot: slot, size: size(of: subview, slot: slot, in: bounds))
    }
    var distances: [String: CGFloat] = [:]
    for top in [true, false] {
      let items = placed.filter { $0.slot.top == top }.map { $0.item(in: bounds) }
      distances.merge(FloatingGeometry.stackDistances(items, gap: FloatingGeometry.stackGap)) { $1 }
    }
    for entry in placed {
      let origin = CGPoint(
        x: bounds.minX + entry.x(in: bounds),
        y: bounds.minY + entry.y(in: bounds, distance: distances[entry.slot.key]))
      entry.subview.place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(entry.size))
    }
  }

  /// The size the view takes: `fill` the width less the margins up to the readable maximum, anything else its own.
  private func size(of subview: LayoutSubview, slot: FloatingSlot, in bounds: CGRect) -> CGSize {
    let available = max(0, bounds.width - 2 * slot.margin)
    if slot.fills {
      let width = min(available, FloatingGeometry.fillMaxWidth)
      let height = subview.sizeThatFits(ProposedViewSize(width: width, height: bounds.height))
        .height
      return CGSize(width: width, height: height)
    }
    return subview.sizeThatFits(ProposedViewSize(width: available, height: bounds.height))
  }

  private struct Placed {
    let subview: LayoutSubview
    let slot: FloatingSlot
    let size: CGSize

    func x(in bounds: CGRect) -> CGFloat {
      let base: CGFloat =
        switch slot.align {
        case .left: slot.margin
        case .right: bounds.width - slot.margin - size.width
        default: (bounds.width - size.width) / 2
        }
      return base + slot.offset.width
    }

    func y(in bounds: CGRect, distance: CGFloat?) -> CGFloat {
      switch slot.top {
      case true?: (distance ?? slot.margin) + slot.offset.height
      case false?: bounds.height - size.height - (distance ?? slot.margin) - slot.offset.height
      case nil: (bounds.height - size.height) / 2 + slot.offset.height
      }
    }

    func item(in bounds: CGRect) -> StackItem {
      StackItem(
        key: slot.key, group: slot.group, left: x(in: bounds), width: size.width,
        height: size.height,
        margin: slot.margin)
    }
  }
}
