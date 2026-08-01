import Foundation

/// Visible build identifier for the premium redesign. Version + build number come from
/// the bundle (Info.plist) so they always match the installed binary; `commit` and
/// `builtAt` are stamped by CI (fork-testing-build.yml) at build time by replacing the
/// PLACEHOLDER tokens below. In a local/dev build the tokens remain, so they read as
/// "dev" / "—". Surfaced in Settings → About so an installed IPA can be verified against
/// the exact source it was built from.
enum BuildInfo {
    /// Replaced by CI with the short git SHA of the built commit.
    static let commitRaw = "COMMIT_PLACEHOLDER"
    /// Replaced by CI with the build timestamp (UTC).
    static let builtAtRaw = "BUILDDATE_PLACEHOLDER"

    /// Redesign milestone this build corresponds to (matches the HTML prototype).
    static let milestone = 4
    static let prototypeVersion = "0.3.0"

    static var version: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—" }
    static var build: String { (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—" }
    static var commit: String { commitRaw.hasPrefix("COMMIT_") ? "dev" : commitRaw }
    static var builtAt: String { builtAtRaw.hasPrefix("BUILDDATE_") ? "—" : builtAtRaw }
}
