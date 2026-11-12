import Foundation

/// What the last update check in this session found. Sparkle keeps no result between launches, so a new launch starts
/// with none.
public enum UpdateCheckResult: Equatable, Sendable {
    case upToDate
    case found(version: String)
}

/// What Settings says about updates, in About's header and the sidebar's footer. It says "Up to date" only when a check
/// in this session found nothing, since otherwise a release may have come out since the last check.
public enum UpdateStatus: Equatable, Sendable {
    /// The build has no update feed, as ShotDev and local builds don't, so it never checks.
    case off
    /// A check found this version, and it isn't installed yet.
    case available(version: String)
    /// A check in this session found nothing newer.
    case upToDate
    /// No check has finished in this session; the last one, in an earlier session, was at this time.
    case lastChecked(Date)
    /// Shot has never checked.
    case notChecked

    /// - Parameters:
    ///   - hasFeed: Whether the build can update itself.
    ///   - pendingVersion: A version an automatic check found that the person hasn't looked at yet.
    ///   - lastResult: What the last check in this session found.
    ///   - lastCheck: When Shot last checked, in this session or an earlier one.
    public init(hasFeed: Bool, pendingVersion: String?, lastResult: UpdateCheckResult?, lastCheck: Date?) {
        guard hasFeed else {
            self = .off
            return
        }
        if let pendingVersion {
            self = .available(version: pendingVersion)
            return
        }
        switch lastResult {
        case .found(let version):
            self = .available(version: version)
        case .upToDate:
            self = .upToDate
        case nil:
            self = lastCheck.map { .lastChecked($0) } ?? .notChecked
        }
    }

    /// The version a check found, if one did.
    public var availableVersion: String? {
        if case .available(let version) = self {
            return version
        }
        return nil
    }
}
