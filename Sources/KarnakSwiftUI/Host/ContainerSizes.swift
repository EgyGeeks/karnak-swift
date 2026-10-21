import KarnakCore
import SwiftUI
import UIKit

/// The device's screen dimensions in points, which decide what size classes a Karnak container
/// can reach (`docs/protocol.md`, Client obligations): a phone (smallest dimension under 600)
/// stays `compact`, also in landscape.
struct DeviceSizes: Equatable {
  /// The larger screen dimension, the widest a container can be.
  let largest: Double
  /// The smaller screen dimension.
  let smallest: Double

  /// The screen of the first window scene, or a phone's when there is none (unit tests inject
  /// sizes through ``EnvironmentValues/karnakDeviceSizes``).
  @MainActor static var current: DeviceSizes {
    // The app's own foreground scene, not an external display's.
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .filter { $0.session.role == .windowApplication }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let size = scene?.screen.bounds.size ?? CGSize(width: 390, height: 844)
    return DeviceSizes(
      largest: Double(max(size.width, size.height)), smallest: Double(min(size.width, size.height)))
  }

  var sizing: ContainerSizing {
    ContainerSizing(largestWidthDp: largest, smallestWidthDp: smallest)
  }

  /// The environment of a container `width` points wide on this device, with the host's color
  /// scheme and layout direction: the one place hosts build theirs.
  func environment(
    colorScheme: ColorScheme, layoutDirection: LayoutDirection, width: Double
  ) -> ScreenEnvironment {
    let base = ScreenEnvironment.make(
      colorMode: colorScheme == .dark ? .dark : .light,
      layoutDirection: layoutDirection == .rightToLeft ? .rtl : .ltr)
    return sizing.environment(environment: base, containerWidthDp: width)
  }
}

extension EnvironmentValues {
  /// Replaces the device's screen dimensions when deciding reachable size classes; for tests
  /// and previews of another device.
  @Entry var karnakDeviceSizes: DeviceSizes?
  /// Forces the container width, in points, instead of measuring it.
  @Entry var karnakContainerWidth: Double?
}

extension View {
  /// Treats every Karnak screen and section below as `width` points wide instead of measuring its
  /// container, for previews and tests of `adaptive` layouts. The class still can't exceed what
  /// the device allows: a phone stays `compact`.
  public func karnakContainerWidth(_ width: Double) -> some View {
    environment(\.karnakContainerWidth, width)
  }
}

private struct ContainerWidthKey: PreferenceKey {
  static let defaultValue: CGFloat? = nil
  static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
    value = nextValue() ?? value
  }
}

extension View {
  /// Reports the width this view is offered, through a zero-height, full-width probe above it.
  func measuringContainerWidth(_ width: Binding<CGFloat?>) -> some View {
    // Leading, so a content-sized section keeps its start edge; full width, because the probe
    // needs the width the host is offered.
    VStack(alignment: .leading, spacing: 0) {
      Color.clear.frame(height: 0).frame(maxWidth: .infinity)
        .background(
          GeometryReader { proxy in
            Color.clear.preference(key: ContainerWidthKey.self, value: proxy.size.width)
          }
        )
      // A host nested in this one (in a loading or error view) must not report for it.
      self.transformPreference(ContainerWidthKey.self) { $0 = nil }
    }
    .onPreferenceChange(ContainerWidthKey.self) { measured in
      if let measured, width.wrappedValue != measured { width.wrappedValue = measured }
    }
  }
}
