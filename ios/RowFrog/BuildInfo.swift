import Foundation

/// The app's version, build number and commit, as Settings > About shows them:
/// "0.1.0 (723) · 22a69ce" (decision NNNN-build-numbers).
/// The build number is the commit count of main up to the built commit and the commit
/// its sha7; scripts/build_number.sh stamps both (ios/BuildNumber.xcconfig), a build
/// that was never stamped says "(1) · dev". The website copies this line (version.json).
enum BuildInfo {
    static let commitKey = "RWCommit"

    static var version: String { value("CFBundleShortVersionString") ?? "–" }
    static var build: String { value("CFBundleVersion") ?? "–" }
    static var commit: String { value(commitKey) ?? "dev" }

    /// "0.1.0 (723) · 22a69ce".
    static var summary: String { summary(version: version, build: build, commit: commit) }

    static func summary(version: String, build: String, commit: String) -> String {
        "\(version) (\(build)) · \(commit)"
    }

    private static func value(_ key: String, in bundle: Bundle = .main) -> String? {
        guard let text = bundle.object(forInfoDictionaryKey: key) as? String, !text.isEmpty,
              // An unset build setting would leave "$(RW_COMMIT)" behind.
              !text.hasPrefix("$(") else { return nil }
        return text
    }
}
