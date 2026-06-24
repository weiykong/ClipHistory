import Foundation
import Observation

/// Checks the GitHub Releases API for a newer version of ClipHistory.
/// The result is exposed as observable properties so the popup can show
/// a subtle banner when an update is available.
@Observable
final class UpdateChecker {

    /// Current app version — bump this when tagging a new release.
    static let currentVersion = "1.3.3"

    // MARK: - Observable state

    /// Non-nil when a newer release was found on GitHub.
    var latestVersion: String?
    /// Direct URL to the release page (for the user to open).
    var releaseURL: URL?

    var updateAvailable: Bool { latestVersion != nil }

    // MARK: - Check

    /// Fires a single request to the GitHub Releases API.
    /// Safe to call from any thread; updates are dispatched to main.
    func checkForUpdate() {
        let urlString = "https://api.github.com/repos/weiykong/ClipHistory/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Keep the request lightweight — no auth needed for public repos.
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data, error == nil else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String
            else { return }

            let remote = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            if Self.isNewer(remote: remote, current: Self.currentVersion) {
                DispatchQueue.main.async {
                    self?.latestVersion = remote
                    self?.releaseURL    = URL(string: htmlURL)
                }
            }
        }.resume()
    }

    // MARK: - Semver comparison

    /// Returns true when `remote` is strictly newer than `current`.
    private static func isNewer(remote: String, current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }
}
