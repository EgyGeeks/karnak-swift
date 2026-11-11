import KarnakCore
import SwiftUI

/// The floating layer of a screen (ADR 0038): above its content, inside the safe area (a `TabView`'s bar included) and
/// the keyboard, drawing the views the screen declares. Edge and center views are placed by ``FloatingEdgeLayout``;
/// anchored ones by ``FloatingAnchoredView`` on the bounds the nodes offered; modal ones over a scrim. The layer ends a
/// view only by telling the host why. It reads one value, the screen's `floating` list, and is split per key below it.
struct FloatingLayer: View {
  let items: [FloatingItem]
  let anchors: [String: Anchor<CGRect>]
  let reserve: FloatingReserve
  let host: FloatingHost
  /// Whether the keyboard is up, read by the screen's modifier outside this layer's own safe-area handling.
  let keyboardUp: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      let bounds = CGRect(origin: .zero, size: proxy.size)
      ZStack(alignment: .topLeading) {
        FloatingEdgeLayout {
          ForEach(inLayout) { item in
            FloatingEntryView(view: item.view, host: host)
              .modifier(ReservedHeight(view: item.view, reserve: reserve))
              .floatingTransition(item.view)
              .floatingSlot(FloatingSlot(item.view))
          }
        }
        ForEach(anchoredItems) { item in
          if let anchored = item.view.anchored {
            FloatingAnchoredView(
              view: item.view, anchored: anchored,
              anchor: anchors[anchored.anchor.value].map { proxy[$0] },
              bounds: bounds, host: host
            )
            .floatingTransition(item.view)
          }
        }
        ForEach(modalItems) { item in
          FloatingModalView(item: item, anchors: anchors, proxy: proxy, host: host)
            .floatingTransition(item.view)
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
    }
    .animation(reduceMotion ? nil : Self.moveAnimation, value: items.map(\.id))
    .ignoresSafeArea(.keyboard, edges: avoidsKeyboard ? [] : .bottom)
  }

  /// The stacking move: the theme's `medium` duration and `standard` easing (ADR 0038, D6).
  static let moveAnimation = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.25)

  /// The views the layer's own layout places, less those that hide the keyboard while it is up.
  private var inLayout: [FloatingItem] {
    items.filter { $0.view.isInLayout && !(keyboardUp && $0.view.behavior.hideKeyboard) }
  }

  private var anchoredItems: [FloatingItem] {
    items.filter { $0.view.anchored != nil && !$0.view.isModal }
  }

  private var modalItems: [FloatingItem] { items.filter { $0.view.isModal } }

  /// A layer whose views all ignore the keyboard doesn't rise with it.
  private var avoidsKeyboard: Bool {
    items.isEmpty || items.contains { $0.view.behavior.avoidKeyboard }
  }
}

/// Reports a reserving view's height and margin to the screen's lists (ADR 0038, D6).
private struct ReservedHeight: ViewModifier {
  let view: ResolvedFloating
  let reserve: FloatingReserve

  func body(content: Content) -> some View {
    if view.behavior.reserve, let edge = view.edge {
      content.onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: { height in
        reserve.measured(view.key, top: edge.top, height: height + points(dp: edge.margin))
      }
    } else {
      content
    }
  }
}

/// A modal view (ADR 0038, D10): a center view over a scrim, or an anchored one over a catcher, that moves focus into it
/// and hides what lies beneath from the screen reader, and ends on a tap outside when it asked.
struct FloatingModalView: View {
  let item: FloatingItem
  let anchors: [String: Anchor<CGRect>]
  let proxy: GeometryProxy
  let host: FloatingHost

  @AccessibilityFocusState private var focused: Bool

  var body: some View {
    let view = item.view
    ZStack {
      if view.anchored == nil {
        Color.black.opacity(0.32)
          .contentShape(Rectangle())
          .onTapGesture { if view.behavior.tapOutside { host.dismiss(view.key, .tapoutside) } }
          .accessibilityHidden(true)
      }
      if let anchored = view.anchored {
        FloatingAnchoredView(
          view: view, anchored: anchored, anchor: anchors[anchored.anchor.value].map { proxy[$0] },
          bounds: CGRect(origin: .zero, size: proxy.size), host: host)
      } else {
        FloatingEntryView(view: view, host: host).accessibilityFocused($focused)
      }
    }
    .accessibilityAddTraits(.isModal)
    .onAppear { focused = true }
  }
}

/// Hosts the floating layer over a screen's content (ADR 0038, D19): an `.overlay` on the screen root, which keeps the
/// safe area (a `TabView`'s bar, the keyboard) and reads the anchors the content offers with
/// `overlayPreferenceValue`. The content learns the reserve the layer asks for and, for the views that let a tap
/// through, ends them on a tap on the screen. Without a `dismiss` the screen draws no layer.
private struct FloatingLayerModifier: ViewModifier {
  let floating: [ResolvedFloating]
  let dismiss: ((String, FloatingDismissReason) -> Void)?
  @State private var reserve = FloatingReserve()
  @State private var keyboardUp = false
  @Environment(\.karnakDialogCovers) private var dialogCovers

  func body(content: Content) -> some View {
    if let dismiss {
      let items = floating.map(FloatingItem.init)
      let host = FloatingHost(dismiss: dismiss, dialogCovers: dialogCovers)
      let throughKeys = items.filter { $0.view.endsOnTapThrough }.map(\.id)
      content
        .readsKeyboard($keyboardUp, isEnabled: items.contains { $0.view.behavior.hideKeyboard })
        .environment(\.karnakFloatingReserve, reserve)
        .simultaneousGesture(
          SpatialTapGesture().onEnded { _ in
            for key in throughKeys { dismiss(key, .tapoutside) }
          },
          including: throughKeys.isEmpty ? .subviews : .all
        )
        .overlayPreferenceValue(FloatingAnchorKey.self) { anchors in
          FloatingLayer(
            items: items, anchors: anchors, reserve: reserve, host: host, keyboardUp: keyboardUp)
        }
    } else {
      content
    }
  }
}

extension EnvironmentValues {
  /// Whether a dialog the SDK shows covers the screen, which pauses the timers of its floating views (ADR 0038, D7).
  @Entry var karnakDialogCovers = false
}

extension View {
  /// Draws `floating` as the screen's floating layer over this view, when `dismiss` says where a view's end goes.
  func floatingLayer(
    _ floating: [ResolvedFloating], dismiss: ((String, FloatingDismissReason) -> Void)?
  ) -> some View {
    modifier(FloatingLayerModifier(floating: floating, dismiss: dismiss))
  }
}
