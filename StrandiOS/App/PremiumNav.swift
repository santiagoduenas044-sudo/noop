#if os(iOS)
import SwiftUI
import StrandDesign

/// iOS-only navigation targets for the Premium UI's deep screens (metric detail, energy, blood oxygen,
/// strain). Deliberately SEPARATE from the shared `TabRoute`/`MoreDestination` enums: those compile into
/// BOTH the macOS and iOS targets, so adding an iOS-only Premium screen there would break the macOS build
/// (the views are `#if os(iOS)`). This enum and its `.navigationDestination(for:)` registration live only
/// under `StrandiOS/`, so they exist for iPhone and never touch macOS.
///
/// Every Premium tab's `NavigationStack` registers this via `.premiumRouteDestinations()` (alongside the
/// shared `.tabRouteDestinations()`), and screens push a value with `NavigationLink(value:)` or by
/// appending to the tab's bound `NavigationPath` — so a tab re-tap can still pop these off (#135/#198).
enum PremiumRoute: Hashable {
    /// Any metric in the full `PremiumMetricCatalog`, rendered by the catalog-driven detail screen.
    /// This is what Home's customisable grid pushes, so every one of the ~24 catalog metrics has a
    /// real detail view (history, baseline, 7/30/90D change, distribution, weekday pattern, related
    /// metrics, explanation). Replaces an older 6-metric `PremiumMetricKind`/`PremiumMetricDetailView`
    /// path that was never actually pushed from anywhere — removed rather than kept as dead code.
    case catalogMetric(PremiumMetricID)
    case energy
    case bloodOxygen
    case strain
    /// One journal factor's WITH vs WITHOUT breakdown. Carries the CANONICAL key (never the
    /// display name) so a renamed factor still resolves to the same history.
    case journalFactor(String)
    /// The shared `HydrationView` — a complete, Android-parity logging screen that iOS could not
    /// reach. Settings has always offered the "Hydration tracker" opt-in toggle, but the only route
    /// to the screen itself was the macOS `TabRoute.hydration`, so turning the feature on left
    /// nowhere to log a drink. Same shape as the nap bug: working capability, no iOS entry point.
    case hydration
}

extension View {
    /// Registers the Premium deep-screen destinations on the enclosing `NavigationStack`. Mirrors the shared
    /// `.tabRouteDestinations()` but for the iOS-only `PremiumRoute` values. Applied once per tab stack in
    /// `RootTabView` (double registration double-pushes, #38).
    func premiumRouteDestinations() -> some View {
        navigationDestination(for: PremiumRoute.self) { route in
            Group {
                switch route {
                // SpO₂ has a purpose-built screen (real overnight samples, spot-check timeline,
                // gap reporting) that the generic catalog detail can't express, because the catalog
                // only sees ONE stored value per night. Route it there from EVERY entry point —
                // Home already pushed `.bloodOxygen` directly, but Sleep's overnight-vitals row
                // pushed `.catalogMetric(.spo2)`, so the same tile led to two different screens.
                case .catalogMetric(.spo2): PremiumBloodOxygenView()
                case .catalogMetric(let id): PremiumCatalogDetailView(metric: id)
                case .energy:             PremiumEnergyView()
                case .bloodOxygen:        PremiumBloodOxygenView()
                case .strain:             PremiumStrainView()
                case .journalFactor(let canonical): PremiumFactorDetailView(factorCanonical: canonical)
                case .hydration:          HydrationView()
                }
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}
#endif
