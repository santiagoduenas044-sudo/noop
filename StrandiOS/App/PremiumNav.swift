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
    case metric(PremiumMetricKind)
    case energy
    case bloodOxygen
    case strain
}

extension View {
    /// Registers the Premium deep-screen destinations on the enclosing `NavigationStack`. Mirrors the shared
    /// `.tabRouteDestinations()` but for the iOS-only `PremiumRoute` values. Applied once per tab stack in
    /// `RootTabView` (double registration double-pushes, #38).
    func premiumRouteDestinations() -> some View {
        navigationDestination(for: PremiumRoute.self) { route in
            Group {
                switch route {
                case .metric(let kind): PremiumMetricDetailView(kind: kind)
                case .energy:           PremiumEnergyView()
                case .bloodOxygen:      PremiumBloodOxygenView()
                case .strain:           PremiumStrainView()
                }
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}
#endif
