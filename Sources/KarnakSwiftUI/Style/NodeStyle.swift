import KarnakCore
import SwiftUI

extension View {
  /// Applies a node's common style as one modifier chain on its primitive
  /// (`docs/renderer-contract.md`, Primitive mapping): padding, the sized box, clip, shadows and
  /// background, border, alpha, semantics, click and the touch target.
  ///
  /// - Parameters:
  ///   - node: The node drawn by this view.
  ///   - placement: What the node's parent decides about its box.
  ///   - contentPosition: Where the primitive sits when its box is larger than it.
  ///   - content: How the primitive relates to its box.
  func nodeStyle(
    _ node: ResolvedNode, placement: ChildPlacement,
    contentPosition: ContentPosition = .topStart, content: BoxContent = .measured
  ) -> some View {
    let semantics = accessibilitySemantics(of: node)
    let isContainer = node is ResolvedContainer
    let isBox =
      node is ResolvedIconNode || node is ResolvedProgressNode || node is ResolvedCanvasNode
    let isGroup = (isContainer || isBox) && !semantics.hidden && !semantics.mergeDescendants
    return nodeBox(node, placement: placement, contentPosition: contentPosition, content: content)
      .modifier(
        NodeSemantics(
          semantics: semantics, isContainer: isContainer,
          isBoxElement: isBox && node.onClick == nil)
      )
      // After semantics: an accessibility action added before `.accessibilityElement(children:
      // .combine)` stops the element from combining its children's labels.
      .modifier(
        NodeClick(
          handle: node.onClick, touchTarget: touchTarget(of: node),
          group: isGroup ? semantics : nil, menu: node.layout.contextMenu)
      )
      .modifier(
        NodeTooltip(
          key: node.key.value, tooltip: node.layout.tooltip,
          longPressShows: node.layout.contextMenu == nil)
      )
      .modifier(NodeContextMenu(menu: node.layout.contextMenu, inGroup: isGroup))
      // A node with interaction styles of its own shows them in place of the system's hover effect.
      .modifier(
        NodeHover(
          isActive: !node.interactive && (node.onClick != nil || node.layout.cursor == .pointer))
      )
      .modifier(
        ReservedTouchTarget(minimum: placement.reservesTouchTarget ? touchTarget(of: node) : 0)
      )
      .modifier(NodeAppear(handle: node.onAppear))
      .modifier(NodeNear(handle: node.layout.onNear))
  }

  /// The drawn part of a node's common style: padding, the sized box, clip, shadows and
  /// background, border and alpha. A button draws this from the node its interaction state
  /// selects, and takes its semantics and touch target from ``ButtonView``.
  func nodeBox(
    _ node: ResolvedNode, placement: ChildPlacement,
    contentPosition: ContentPosition = .topStart, content: BoxContent = .measured
  ) -> some View {
    modifier(
      NodeBox(
        layout: node.layout, placement: placement, contentPosition: contentPosition,
        content: content))
  }
}

/// A node's touch target's side in points; 0 for none.
func touchTarget(of node: ResolvedNode) -> CGFloat {
  CGFloat(node.layout.touchTarget?.floatValue ?? 0)
}

/// A node's box and what it draws around its content. Each part is a modifier on the one
/// element, so the node adds no wrapper views of its own.
private struct NodeBox: ViewModifier {
  let layout: ResolvedLayout
  let placement: ChildPlacement
  let contentPosition: ContentPosition
  let content: BoxContent
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// How `field` moves to a new value (``BoxMotionField``).
  private func animation(of field: BoxMotionField) -> Animation? {
    layout.animation(of: field, reduceMotion: reduceMotion)
  }

  /// One axis of the box: its own sizing, or the whole proposal for a root that fills the host.
  private func axis(_ axis: Axis) -> AxisSizing {
    if placement.fillsHost { return AxisSizing(mode: .fill) }
    let horizontal = axis == .horizontal
    return AxisSizing(
      size: horizontal ? layout.width : layout.height,
      minimum: horizontal ? layout.minWidth : layout.minHeight,
      maximum: horizontal ? layout.maxWidth : layout.maxHeight,
      acceptsProposal: placement.acceptsProposal.contains(horizontal ? .horizontal : .vertical))
  }

  func body(content primitive: Content) -> some View {
    let shape = NodeShape(radius: points(dp: layout.radius))
    let frame = NodeFrameLayout(
      width: axis(.horizontal), height: axis(.vertical), position: contentPosition, content: content
    )
    primitive.padding(edgeInsets(layout.padding))
      .modifier(
        MovingFrame(
          frame: frame, widthAnimation: animation(of: .width),
          heightAnimation: animation(of: .height))
      )
      .modifier(NodeClip(shape: shape, clips: layout.clip))
      .background {
        NodeBackground(
          shape: shape, fill: layout.background.map(resolvedColor), paint: layout.backgroundTarget,
          transition: layout.transition(of: "style.background"), shadows: layout.shadows)
      }
      .overlay {
        if let border = layout.border { NodeBorder(shape: shape, border: border) }
      }
      .modifier(FieldMotion(value: shape.radius, animation: animation(of: .radius)))
      .loopEffect(layout.loopEffect, shape: shape)
      .modifier(AlphaMotion(alpha: Double(layout.alpha), animation: animation(of: .alpha)))
  }
}

/// Moves the views it wraps with `animation` when `value` changes, as a `motion` transition of one box field
/// (`docs/renderer-contract.md`, Motion); a field without one applies at once.
private struct FieldMotion<Value: Equatable>: ViewModifier {
  let value: Value
  let animation: Animation?

  func body(content: Content) -> some View {
    content.transaction(value: value) { $0.move(with: animation) }
  }
}

/// The node's alpha, moved by its `style.alpha` transition. The animation reaches the opacity alone, so the content's
/// own changes in the same tree draw at once.
private struct AlphaMotion: ViewModifier {
  let alpha: Double
  let animation: Animation?

  func body(content: Content) -> some View {
    // One branch keeps the content's identity when a new tree adds or drops the transition; nil applies at once.
    content.animation(animation) { $0.opacity(alpha) }
  }
}

/// Clips the content to the node's shape when the node asks for it.
private struct NodeClip: ViewModifier {
  let shape: NodeShape
  let clips: Bool

  func body(content: Content) -> some View {
    if clips { content.clipShape(shape) } else { content }
  }
}

/// A node's semantics as SwiftUI reads them. A list, a carousel or a pager speaks its size ("3 items") as its value, labelled or
/// not: SwiftUI has no collection count of its own (`docs/renderer-contract.md`, `list` and `carousel`,
/// Accessibility).
func accessibilitySemantics(of node: ResolvedNode) -> AccessibilitySemantics {
  var semantics = AccessibilitySemantics(node)
  if let list = node as? ResolvedList, semantics.stateDescription == nil {
    semantics.stateDescription = list.countLabel
  }
  if let carousel = node as? ResolvedCarousel, semantics.stateDescription == nil {
    semantics.stateDescription = carousel.countLabel
  }
  if let pager = node as? ResolvedPager, semantics.stateDescription == nil {
    semantics.stateDescription = pager.countLabel
  }
  return semantics
}
