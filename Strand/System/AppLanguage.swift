import Foundation
import SwiftUI

/// AppLanguage — the user's manual language override.
///
/// NOOP ships full String Catalogs (English source + German, Spanish, French), and by default iOS
/// picks whichever of those matches the device language. That is the right behaviour for almost
/// everyone, so `.system` stays the default. This adds an explicit override for the cases the system
/// setting can't express: a bilingual user who keeps their phone in one language but wants the app
/// in another, or someone checking a translation.
///
/// **Mechanism.** The override writes the standard `AppleLanguages` UserDefaults key, which is the
/// documented way to pin an app's bundle language. iOS resolves `String(localized:)` lookups against
/// that list at launch, so a change needs a relaunch to fully apply — the settings UI says so
/// rather than pretending otherwise. `SwiftUI`'s `.environment(\.locale)` is applied at the same
/// time so views that re-render pick up the new locale immediately for anything formatted through
/// the environment (dates, numbers), which covers most of what a user sees before they relaunch.
///
/// Adding a language later means adding its code here and translating the catalogs — no view code
/// changes, because nothing in the UI hardcodes a translation.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    /// Follow the device's language (the default).
    case system
    case english = "en"
    case spanish = "es"

    var id: String { rawValue }

    /// The name shown in the picker. Each language is written in ITS OWN language ("Español", not
    /// "Spanish") — the convention every OS language picker uses, because someone looking for their
    /// own language shouldn't have to read a language they don't speak to find it.
    var label: String {
        switch self {
        case .system:  return String(localized: "System Default")
        case .english: return "English"
        case .spanish: return "Español"
        }
    }

    var symbol: String {
        switch self {
        case .system:  return "iphone"
        case .english: return "textformat"
        case .spanish: return "textformat"
        }
    }

    /// The `AppleLanguages` array this override implies, or nil for `.system` (which removes the
    /// key entirely and lets iOS choose).
    var appleLanguagesValue: [String]? {
        switch self {
        case .system:  return nil
        case .english: return ["en"]
        case .spanish: return ["es"]
        }
    }

    /// The `Locale` to push into the SwiftUI environment so formatting follows the override even
    /// before a relaunch. `.system` yields the device locale unchanged.
    var locale: Locale {
        switch self {
        case .system:  return Locale.autoupdatingCurrent
        case .english: return Locale(identifier: "en")
        case .spanish: return Locale(identifier: "es")
        }
    }
}

/// Stores and applies the language override. Mirrors the `ProfileStore` / `BehaviorStore` idiom:
/// a `@Published` value backed by `UserDefaults`, single-user, entirely on-device.
@MainActor
final class AppLanguageStore: ObservableObject {

    private enum K {
        static let selection = "app.languageOverride"
        /// Apple's own key. Writing it is what actually pins the bundle language.
        static let appleLanguages = "AppleLanguages"
    }

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: K.selection)
            apply()
        }
    }

    /// True once the user has changed the override this launch, so the UI can surface the
    /// "relaunch to fully apply" note only when it is actually relevant.
    @Published private(set) var needsRelaunch = false

    init() {
        let raw = UserDefaults.standard.string(forKey: K.selection) ?? AppLanguage.system.rawValue
        self.language = AppLanguage(rawValue: raw) ?? .system
        // Re-assert on launch: `AppleLanguages` can be reset by the system, and re-applying makes
        // the stored preference authoritative without the user re-picking it.
        applyWithoutFlaggingRelaunch()
    }

    /// The locale to inject into the SwiftUI environment.
    var locale: Locale { language.locale }

    private func apply() {
        applyWithoutFlaggingRelaunch()
        needsRelaunch = true
    }

    private func applyWithoutFlaggingRelaunch() {
        let defaults = UserDefaults.standard
        if let value = language.appleLanguagesValue {
            defaults.set(value, forKey: K.appleLanguages)
        } else {
            defaults.removeObject(forKey: K.appleLanguages)
        }
    }

    /// Which language is actually in effect right now, resolving `.system` against the device's
    /// preferred languages. Used by the settings row's subtitle so "System Default" still tells the
    /// user what they're going to get.
    var effectiveLanguage: AppLanguage {
        if language != .system { return language }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("es") { return .spanish }
        return .english
    }
}
