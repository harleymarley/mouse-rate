// AppConfig.swift
// build.sh rewrites the values below at build time. The defaults are used for local builds.

enum AppConfig {
    static let version = "1.0.0"
    static let repoURL = "https://github.com/harleymarley/mouse-rate"
    static let siteURL = "https://mouse.almostperfecttech.com"
    /// Where "Copy and paste in the YouTube comments" sends people. Swap in the mouse video's link once it's live.
    static let videoURL = "https://www.youtube.com/@AlmostPerfectReviews"
    /// The tip jar (a Buy Me a Coffee page) shown under the report.
    static let coffeeURL = "https://buymeacoffee.com/almostperfecttech"
    /// When this copy was built. Shown in the header so it's obvious which build is open.
    static let built = "dev build"
}
