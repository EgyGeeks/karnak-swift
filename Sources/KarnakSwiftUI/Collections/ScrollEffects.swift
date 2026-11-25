import KarnakCore
import Observation
import SwiftUI

/// One anchor row's progress through its list's top edge, 0 to 1 (ADR 0055, D1). Observable on its own, so a node
/// whose effect follows it redraws with this row alone, never with the other anchors of the screen.
@Observable @MainActor
final class AnchorProgress {
  private(set) var value: CGFloat = 0

  /// Sets the progress to `value`; the same value again redraws nothing.
  func update(_ value: CGFloat) {
    if self.value != value { self.value = value }
  }
}

/// The rows of a screen that scroll effects follow, by the key effects name them by (`docs/renderer-contract.md`,
/// Scroll effects, Anchors): a scrolling list writes each anchor row's progress as it is laid out, and a node anywhere
/// on the screen reads its own. A row no list has laid out reads 0, so its effects draw at their start.
@MainActor
final class ScrollAnchorProgress {
  private var progress: [String: AnchorProgress] = [:]

  /// The progress of the row keyed `key`, made the first time it is asked for.
  func of(_ key: String) -> AnchorProgress {
    if let found = progress[key] { return found }
    let made = AnchorProgress()
    progress[key] = made
    return made
  }
}

extension EnvironmentValues {
  /// The screen's anchor rows; `nil` outside a screen, where every effect draws at its start.
  @Entry var karnakScrollAnchors: ScrollAnchorProgress?
}

/// Where the anchor rows of one list sit in its stack, so a row the list has let go still follows the scroll: its
/// progress is worked out from its place in the stack and where the stack now is in the scroll view, whichever way it
/// left (ADR 0055, D1: a row not laid out is 1 above the visible rows and 0 below them). The list's stack reports its
/// place each frame; a row is written only while it is let go and only when its progress changes.
@MainActor
final class ListAnchorPlaces {
  /// The coordinate space of the list's stack, in which a row's place does not change as the list scrolls.
  nonisolated static let space = "karnak.list.anchors"

  private struct Place {
    let top: CGFloat
    let height: CGFloat
  }

  var anchors: ScrollAnchorProgress?
  private var stackTop: CGFloat = 0
  private var places: [String: Place] = [:]
  private var away: Set<String> = []

  /// The stack's top in the scroll view moved to `top`.
  func stackMoved(to top: CGFloat) {
    stackTop = top
    for key in away { write(key) }
  }

  /// The row `key` is laid out at `top` in the stack, `height` tall.
  func laidOut(_ key: String, top: CGFloat, height: CGFloat) {
    places[key] = Place(top: top, height: height)
  }

  /// The row `key` is built again; it reports its own progress.
  func built(_ key: String) { away.remove(key) }

  /// The list let the row `key` go; its progress now follows the stack.
  func letGo(_ key: String) {
    away.insert(key)
    write(key)
  }

  private func write(_ key: String) {
    guard let place = places[key], let progress = anchors?.of(key) else { return }
    progress.update(
      CGFloat(
        ResolvedScrollEffectKt.anchorProgress(
          top: Float(place.top + stackTop), height: Float(place.height), edge: 0)))
  }
}

extension EnvironmentValues {
  /// The anchor places of the list a row is in; `nil` in a list no effect follows.
  @Entry var karnakListAnchorPlaces: ListAnchorPlaces?
}

/// Writes the progress of the anchor row keyed `key` through the top edge of the scroll view around it. The progress
/// is worked out in the geometry callback with the row's place in its list's stack, neither of which changes while the
/// row is below the edge or above it, so a scroll then writes nothing. A row the list lets go follows its stack
/// (``ListAnchorPlaces``).
struct ScrollAnchorReport: ViewModifier {
  let key: String
  @Environment(\.karnakScrollAnchors) private var anchors
  @Environment(\.karnakListAnchorPlaces) private var places

  private struct Report: Equatable {
    let progress: CGFloat
    let top: CGFloat
    let height: CGFloat
  }

  func body(content: Content) -> some View {
    content
      .onGeometryChange(for: Report.self) { proxy in
        let frame = proxy.frame(in: .scrollView)
        return Report(
          progress: CGFloat(
            ResolvedScrollEffectKt.anchorProgress(
              top: Float(frame.minY), height: Float(frame.height), edge: 0)),
          top: proxy.frame(in: .named(ListAnchorPlaces.space)).minY, height: frame.height)
      } action: { report in
        places?.laidOut(key, top: report.top, height: report.height)
        anchors?.of(key).update(report.progress)
      }
      .onAppear { places?.built(key) }
      .onDisappear { places?.letGo(key) }
  }
}

extension View {
  /// Gives the rows of a list `places` and reports the list's stack to it, when effects follow a row of the list. The
  /// modifiers are the same either way, so a new tree that adds or removes the list's only anchor keeps the stack's
  /// identity and its rows' state; a list no effect follows reports a constant, which never calls the action.
  func anchorPlaces(_ places: ListAnchorPlaces?) -> some View {
    let follows = places != nil
    return
      coordinateSpace(.named(ListAnchorPlaces.space))
      .onGeometryChange(for: CGFloat.self) {
        follows ? $0.frame(in: .scrollView).minY : 0
      } action: {
        places?.stackMoved(to: $0)
      }
      .environment(\.karnakListAnchorPlaces, places)
  }
}

extension View {
  /// Reports this row's progress when scroll effects follow it (`layout.scrollAnchor`); else the row as it is.
  @ViewBuilder
  func scrollAnchor(_ key: NodeKey?) -> some View {
    if let key {
      modifier(ScrollAnchorReport(key: key.value))
    } else {
      self
    }
  }
}

/// A node whose look follows a row's scroll (`layout.scrollEffect`): its opacity, vertical shift and scale at the
/// effect's fraction of its anchor's progress, drawn only, so its box and its siblings never move. Read in this
/// modifier's own body, so a scroll redraws the effect without running the node's body again. Under Reduce Motion the
/// shift and the scale hold their start; the opacity still follows.
struct ScrollEffectDrawing: ViewModifier {
  let effect: ResolvedScrollEffect
  @Environment(\.karnakScrollAnchors) private var anchors
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    let progress = anchors?.of(effect.anchor.value).value ?? 0
    let fraction = effect.fraction(progress: Float(progress))
    let moved: Float = reduceMotion ? 0 : fraction
    content
      .opacity(Double(effect.alpha?.at(fraction: fraction) ?? 1))
      .scaleEffect(CGFloat(effect.scale?.at(fraction: moved) ?? 1), anchor: origin)
      .offset(y: CGFloat(effect.translateY?.at(fraction: moved) ?? 0))
  }

  /// The point of the box the scale keeps in place, centred across.
  private var origin: UnitPoint {
    switch effect.origin {
    case .top: .top
    case .bottom: .bottom
    default: .center
    }
  }
}

extension View {
  /// Draws `effect` over this node's look; the node as it is when it has none.
  @ViewBuilder
  func scrollEffect(_ effect: ResolvedScrollEffect?) -> some View {
    if let effect {
      modifier(ScrollEffectDrawing(effect: effect))
    } else {
      self
    }
  }
}
