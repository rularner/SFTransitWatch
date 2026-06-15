import Foundation

/// Caches the set of routes serving a stop, derived from `/StopTimetable`
/// (mostly-static scheduled data). Entries are valid for 7 days, after which
/// `routes(for:agency:)` returns nil so the caller refetches.
public final class StopRoutesCache {
    private struct CachedRoutes: Codable {
        let routes: [String]
        let fetchedAt: Date
    }

    private let defaults: UserDefaults
    private let storageKey = "StopRoutesCache"
    private let ttl: TimeInterval = 7 * 24 * 60 * 60

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Returns the cached routes for a stop if present and within the 7-day
    /// TTL, else nil. An empty array is a valid cached result (distinct from
    /// a cache miss).
    public func routes(for stopId: String, agency: String, now: Date = Date()) -> [String]? {
        guard let all = load(), let entry = all[key(stopId: stopId, agency: agency)] else {
            return nil
        }
        guard now.timeIntervalSince(entry.fetchedAt) <= ttl else { return nil }
        return entry.routes
    }

    /// Writes (or overwrites) the cached routes for a stop, including the
    /// empty-array case.
    public func setRoutes(_ routes: [String], for stopId: String, agency: String, now: Date = Date()) {
        var all = load() ?? [:]
        all[key(stopId: stopId, agency: agency)] = CachedRoutes(routes: routes, fetchedAt: now)
        save(all)
    }

    private func key(stopId: String, agency: String) -> String {
        "\(agency):\(stopId)"
    }

    private func load() -> [String: CachedRoutes]? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode([String: CachedRoutes].self, from: data)
    }

    private func save(_ all: [String: CachedRoutes]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
