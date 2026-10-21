// AppConfig.swift
// build.sh rewrites the values below at build time. The defaults are used for local builds.

enum AppConfig {
    static let version = "1.0.3"
    static let repoURL = "https://github.com/harleymarley/mouse-rate"
    static let siteURL = "https://mouse.almostperfecttech.com"
    /// Where "Copy and paste in the YouTube comments" sends people: the Almost Perfect Mac mouse video.
    static let videoURL = "https://youtu.be/xiBbThhUgvY"
    /// The tip jar (a Buy Me a Coffee page) shown under the report.
    static let coffeeURL = "https://buymeacoffee.com/almostperfecttech"
    /// When this copy was built. Shown in the header so it's obvious which build is open.
    static let built = "dev build"
}
