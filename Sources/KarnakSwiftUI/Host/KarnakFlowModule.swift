import KarnakCore

/// A ``KarnakClientModule`` that runs flows (`KarnakFlows` of the `KarnakNavigation` product): the
/// client finds the Kotlin module it installed through it, so ``KarnakFlow`` and the saved state of
/// a joined flow reach the same instance. Implement it only to wrap `karnak-navigation` yourself.
public protocol KarnakFlowModule: KarnakClientModule {
  /// The Kotlin navigation module that ``KarnakClientModule/install(into:)`` installs.
  var navigationModule: KarnakNavigationModule { get }
}
