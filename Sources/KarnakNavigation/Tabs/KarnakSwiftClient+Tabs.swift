import KarnakCore
import KarnakSwiftUI

extension KarnakSwiftClient {
  /// The tab list this client's bar shows (ADR 0047; `docs/integration.md`, Tabs from the server): the server's tab
  /// list when the project released one this device holds and can show, else `fallback`, the app's own tabs. It is
  /// picked once per process, at the first call, from what is on the device: it reads the disk, never the network.
  /// Call it before the bar is drawn and give the result to ``KarnakTabStore/init(list:)``:
  ///
  /// ```swift
  /// let list = await karnak.tabs(
  ///   fallback: KarnakTabList(tabs: [KarnakTab(id: "home"), KarnakTab(id: "cart")]))
  /// let tabs = KarnakTabStore(list: list)
  /// ```
  ///
  /// A list released while the app runs is used from the next cold start. One this SDK cannot show is `fallback`,
  /// whole. Without ``KarnakFlows`` in ``KarnakConfiguration/modules``, it is `fallback`.
  @MainActor
  public func tabs(fallback: KarnakTabList) async -> KarnakTabList {
    guard let module = flowModule else { return fallback }
    // Reading the navigator builds the client's graph, which attaches the module to the client's services.
    _ = navigator
    return (try? await module.tabs(fallback: fallback)) ?? fallback
  }
}
