import CoreGraphics
import KarnakCore
import SwiftUI

/// What this renderer does for one resolved kind (`ResolvedNode.kind`): its drawing, as an `AnyView`, and the
/// facts the dispatch reads besides drawing. The node's `key` is the view identity: containers draw their
/// children `ForEach(id: \.key.value)`.
struct NodeRegistration {
  /// Whether ``NodeView`` draws this kind itself; see ``NodeRenderers/drawnNode(_:)`` for the others.
  var isDrawn = true
  /// Whether this renderer knows the kind at all; an unsupported node is skipped and reported.
  var isSupported = true
  /// Whether the node lays children out: the roots that fill the screen. A `text`, `image` or `button` root keeps
  /// its own size at the top start corner.
  var isContainer = false
  /// Whether the node reports its whole box to the frame observer: a collection whose items the conformance runner
  /// cannot read, as a UIKit-backed scroll view keeps its content out of an in-process accessibility traversal.
  var reportsFrame = false
  /// Whether the drawing is the node's whole box, with its own style and interaction states: a button and an input.
  /// A custom node too: ``CustomNodeView`` styles the host's view, and a fallback drawn in the node's place has its
  /// own style.
  var drawsOwnBox = false
  /// Where the primitive sits when its box is larger than it: a stack's content alignment, a paragraph's alignment,
  /// a button's center, else the top start corner.
  var contentPosition: (ResolvedNode) -> ContentPosition = { _ in .topStart }
  /// How the primitive relates to its box: an image fills it, and the rest are measured.
  var boxContent: (ResolvedNode) -> BoxContent = { _ in .measured }
  /// The nodes drawn inside this one: a container's children or a custom node's fallback.
  var children: (ResolvedNode) -> [ResolvedNode] = { _ in [] }
  /// The node drawn in the node's place, or nil when nothing is.
  var drawn: (ResolvedNode) -> ResolvedNode? = { $0 }
  /// The node as one native element, in its parent's `placement`.
  var draw: @MainActor (ResolvedNode, ChildPlacement) -> AnyView = { _, _ in AnyView(EmptyView()) }
}

extension NodeRegistration {
  /// A registration for nodes of class `N`: each closure gets the node cast once, and a node of another class,
  /// which the kind's key rules out, draws nothing.
  static func of<N: ResolvedNode>(
    _ type: N.Type,
    isContainer: Bool = false,
    reportsFrame: Bool = false,
    drawsOwnBox: Bool = false,
    contentPosition: ((N) -> ContentPosition)? = nil,
    boxContent: ((N) -> BoxContent)? = nil,
    children: ((N) -> [ResolvedNode])? = nil,
    draw: @escaping @MainActor (N, ChildPlacement) -> AnyView
  ) -> NodeRegistration {
    var registration = NodeRegistration()
    registration.isContainer = isContainer
    registration.reportsFrame = reportsFrame
    registration.drawsOwnBox = drawsOwnBox
    if let contentPosition {
      registration.contentPosition = { ($0 as? N).map(contentPosition) ?? .topStart }
    }
    if let boxContent {
      registration.boxContent = { ($0 as? N).map(boxContent) ?? .measured }
    }
    if let children {
      registration.children = { ($0 as? N).map(children) ?? [] }
    }
    registration.draw = { node, placement in
      (node as? N).map { draw($0, placement) } ?? AnyView(EmptyView())
    }
    return registration
  }
}

/// The drawing of each resolved kind, by name. A kind this renderer has no drawing for is skipped, except a
/// host's custom type, which ``CustomNodeView`` draws with the renderer the host registered for it; nothing else
/// dispatches on a node's class or type.
enum NodeRenderers {
  /// The registration for `node`'s kind.
  static func registration(for node: ResolvedNode) -> NodeRegistration {
    registration(forKind: node.kind)
  }

  /// The registration for the kind named `kind`: a custom type (it has a namespace) is drawn by the host's renderer,
  /// and any other unknown kind is unsupported.
  static func registration(forKind kind: String) -> NodeRegistration {
    if let registered = table[kind] { return registered }
    return kind.contains(".") ? custom : unsupported
  }

  /// The nodes drawn inside `node`: a container's children or a custom node's fallback.
  static func children(of node: ResolvedNode) -> [ResolvedNode] {
    registration(for: node).children(node)
  }

  /// The node drawn in `node`'s place, or nil when nothing is: an unsupported node is skipped. Containers draw only these, so a skipped node takes no slot and no spacing.
  static func drawnNode(_ node: ResolvedNode) -> ResolvedNode? {
    registration(for: node).drawn(node)
  }

  /// The kinds that have a registration.
  static var kinds: Set<String> { Set(table.keys) }

  nonisolated(unsafe) private static let table: [String: NodeRegistration] =
    layouts().merging(scrollers()) { $1 }.merging(contents()) { $1 }.merging(inputs()) { $1 }

  nonisolated(unsafe) private static let custom: NodeRegistration = .of(
    ResolvedCustom.self, drawsOwnBox: true, children: { $0.fallback.map { [$0] } ?? [] },
    draw: { custom, placement in AnyView(CustomNodeView(node: custom, placement: placement)) })

  nonisolated(unsafe) private static let unsupported: NodeRegistration = {
    var registration = NodeRegistration()
    registration.isDrawn = false
    registration.isSupported = false
    registration.drawn = { _ in nil }
    return registration
  }()

  /// The primitives that lay out children.
  private static func layouts() -> [String: NodeRegistration] {
    var table: [String: NodeRegistration] = [:]
    table["column"] = .of(
      ResolvedColumn.self, isContainer: true, children: { $0.children },
      draw: { column, placement in
        AnyView(
          ColumnView(
            children: column.children, fields: LinearFields(column), placement: placement,
            key: column.key.value))
      })
    // The semantic form container (`docs/renderer-contract.md`, Inputs, `form`): a column whose inputs VoiceOver
    // reaches as one group.
    table["form"] = .of(
      ResolvedForm.self, isContainer: true, children: { $0.children },
      draw: { form, placement in
        AnyView(
          ColumnView(
            children: form.children, fields: LinearFields(form), placement: placement,
            key: form.key.value
          )
          .accessibilityElement(children: .contain))
      })
    table["row"] = .of(
      ResolvedRow.self, isContainer: true, children: { $0.children },
      draw: { row, placement in
        AnyView(RowView(row: row, placement: placement))
      })
    table["grid"] = .of(
      ResolvedGrid.self, children: { $0.children },
      draw: { grid, placement in
        AnyView(GridView(grid: grid, placement: placement))
      })
    table["stack"] = .of(
      ResolvedStack.self, isContainer: true,
      contentPosition: { ContentPosition($0.contentAlignment) },
      children: { $0.children },
      draw: { stack, placement in
        AnyView(StackView(stack: stack, placement: placement))
      })
    return table
  }

  /// The primitives that scroll their children: `list`, `carousel` and `pager`.
  private static func scrollers() -> [String: NodeRegistration] {
    var table: [String: NodeRegistration] = [:]
    table["list"] = .of(
      ResolvedList.self, isContainer: true, reportsFrame: true, children: { $0.children },
      draw: { list, placement in
        AnyView(ListView(list: list, placement: placement))
      })
    table["carousel"] = .of(
      ResolvedCarousel.self, reportsFrame: true, children: { $0.children },
      draw: { carousel, placement in
        AnyView(CarouselView(carousel: carousel, placement: placement))
      })
    table["pager"] = .of(
      ResolvedPager.self, reportsFrame: true, children: { $0.children },
      draw: { pager, placement in
        AnyView(PagerView(pager: pager, placement: placement))
      })
    return table
  }

  /// The primitives that draw their own content.
  private static func contents() -> [String: NodeRegistration] {
    var table: [String: NodeRegistration] = [:]
    table["text"] = .of(
      ResolvedText.self, contentPosition: { ContentPosition($0.paragraph.textAlign) },
      draw: { text, _ in
        AnyView(
          ParagraphView(
            paragraph: text.paragraph, isLabelled: text.semantics.label != nil,
            elapsed: text.events[elapsedEvent]))
      })
    table["image"] = .of(
      ResolvedImage.self,
      boxContent: { .image(aspectRatio: $0.aspectRatio.map { CGFloat($0.floatValue) }) },
      draw: { image, _ in
        AnyView(ImageView(image: image))
      })
    table["canvas"] = .of(
      ResolvedCanvasNode.self, draw: { node, _ in AnyView(CanvasView(canvas: node.canvas)) })
    table["icon"] = .of(ResolvedIconNode.self, draw: { icon, _ in AnyView(IconView(node: icon)) })
    table["progress"] = .of(
      ResolvedProgressNode.self,
      draw: { progress, _ in
        AnyView(
          ProgressIndicatorView(
            progress.progress, valueTransition: progress.layout.transition(of: "content.value")))
      })
    table["button"] = .of(
      ResolvedButton.self, drawsOwnBox: true, contentPosition: { _ in .center },
      draw: { button, placement in
        AnyView(ButtonView(button: button, placement: placement))
      })
    return table
  }

  /// The inputs (`docs/renderer-contract.md`, Inputs): each draws its box around its parts itself, and its control is
  /// the accessibility element.
  private static func inputs() -> [String: NodeRegistration] {
    var table: [String: NodeRegistration] = [:]
    table["text_field"] = .of(
      ResolvedTextField.self, drawsOwnBox: true,
      draw: { field, placement in
        AnyView(TextFieldView(field: field, placement: placement))
      })
    table["checkbox"] = .of(
      ResolvedCheckbox.self, drawsOwnBox: true,
      draw: { checkbox, placement in
        AnyView(CheckboxView(checkbox: checkbox, placement: placement))
      })
    table["switch"] = .of(
      ResolvedSwitch.self, drawsOwnBox: true,
      draw: { toggle, placement in
        AnyView(SwitchView(toggle: toggle, placement: placement))
      })
    table["radio_group"] = .of(
      ResolvedRadioGroup.self, drawsOwnBox: true,
      draw: { group, placement in
        AnyView(RadioGroupView(group: group, placement: placement))
      })
    table["select"] = .of(
      ResolvedSelect.self, drawsOwnBox: true,
      draw: { select, placement in
        AnyView(SelectView(select: select, placement: placement))
      })
    table["chip_group"] = .of(
      ResolvedChipGroup.self, drawsOwnBox: true,
      draw: { chips, placement in
        AnyView(ChipGroupView(group: chips, placement: placement))
      })
    table["checkbox_group"] = .of(
      ResolvedCheckboxGroup.self, drawsOwnBox: true,
      draw: { group, placement in
        AnyView(CheckboxGroupView(group: group, placement: placement))
      })
    table["range_slider"] = .of(
      ResolvedRangeSlider.self, drawsOwnBox: true,
      draw: { slider, placement in
        AnyView(RangeSliderView(slider: slider, placement: placement))
      })
    return table
  }
}

/// The node drawn in `node`'s place, or nil when nothing is: see ``NodeRenderers/drawnNode(_:)``.
func drawnNode(_ node: ResolvedNode) -> ResolvedNode? { NodeRenderers.drawnNode(node) }
