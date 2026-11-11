import KarnakCore
import SwiftUI

/// What one transition of a floating view moves (ADR 0038, D9), after reduced motion: a pure value, so the rule is
/// tested without a view.
struct FloatingMotionPlan: Equatable {
  /// Whether it travels from its edge (or toward its anchor).
  var slides: Bool
  /// Whether it grows from a smaller size.
  var scales: Bool
  /// Whether its opacity moves.
  var fades: Bool
  /// How long it takes, in milliseconds.
  var millis: Int

  /// The longest a fade runs under reduced motion.
  static let reducedFadeMillis = 150

  /// The plan of `motion` over `millis`. Reduced motion (ADR 0037, D11): slides and scales apply at once, fades stay,
  /// capped at 150 ms, so `slideFade` becomes a 150 ms fade.
  static func of(_ motion: FloatingMotion, millis: Int, reduceMotion: Bool) -> FloatingMotionPlan {
    var plan = FloatingMotionPlan(
      slides: motion == .slide || motion == .slidefade,
      scales: motion == .scale || motion == .scalefade,
      fades: motion == .fade || motion == .slidefade || motion == .scalefade, millis: millis)
    if reduceMotion {
      plan.slides = false
      plan.scales = false
      plan.millis = min(millis, reducedFadeMillis)
    }
    return plan
  }

  /// Whether nothing moves.
  var isInstant: Bool { !slides && !scales && !fades }
}

/// The transition a floating view enters and leaves with.
struct FloatingTransitions {
  let view: ResolvedFloating
  let reduceMotion: Bool

  /// The transition for the view being inserted and removed.
  var transition: AnyTransition {
    .asymmetric(
      insertion: transition(
        plan(view.transition.enter, view.transition.enterMillis),
        easing: view.transition.enterEasing),
      removal: transition(
        plan(view.transition.exit, view.transition.exitMillis), easing: view.transition.exitEasing))
  }

  private func plan(_ motion: FloatingMotion, _ millis: Int32) -> FloatingMotionPlan {
    .of(motion, millis: Int(millis), reduceMotion: reduceMotion)
  }

  private func transition(_ plan: FloatingMotionPlan, easing: ResolvedEasing) -> AnyTransition {
    guard !plan.isInstant else { return .identity }
    var result = AnyTransition.identity
    if plan.slides { result = result.combined(with: .move(edge: slideEdge)) }
    if plan.scales { result = result.combined(with: .scale(scale: 0.8, anchor: scaleAnchor)) }
    if plan.fades { result = result.combined(with: .opacity) }
    let animation = Animation.timingCurve(
      easing.x1, easing.y1, easing.x2, easing.y2, duration: Double(plan.millis) / 1000)
    return result.animation(animation)
  }

  /// The edge a slide comes from: the view's own edge, or the anchor's side for an anchored view.
  private var slideEdge: Edge {
    if let anchored = view.anchored {
      return switch anchored.side {
      case .above: .bottom
      case .below: .top
      case .left: .trailing
      case .right: .leading
      default: .bottom
      }
    }
    return view.edge?.top == true ? .top : .bottom
  }

  /// Where a scale grows from: the anchor's side, else the center.
  private var scaleAnchor: UnitPoint {
    guard let anchored = view.anchored else { return .center }
    return switch anchored.side {
    case .above: .bottom
    case .below: .top
    case .left: .trailing
    case .right: .leading
    default: .center
    }
  }
}

/// Gives a floating view its enter and exit, as the outermost view the layer inserts and removes: SwiftUI keeps it drawn
/// until its exit ends, after the tree without it has arrived (ADR 0038, D9).
private struct FloatingTransitionModifier: ViewModifier {
  let view: ResolvedFloating
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.transition(FloatingTransitions(view: view, reduceMotion: reduceMotion).transition)
  }
}

extension View {
  /// The enter and exit `view` declared, after reduced motion.
  func floatingTransition(_ view: ResolvedFloating) -> some View {
    modifier(FloatingTransitionModifier(view: view))
  }
}
