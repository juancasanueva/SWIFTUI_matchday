//
//  MatchRepository.swift
//  matchday
//
//  Combines the ESPN client, the disk cache and the refresh policy
//  (the original plugin's `Engine.jobs`, `run_jobs`, `all_events`, `tables`, `teams`).
//

import Foundation

/// Everything the UI needs from the network layer at one point in time.
nonisolated struct MatchSnapshot: Sendable {
    /// Every known match: followed teams' schedules overlaid with the day scoreboards,
    /// sorted by kickoff, league, then home team.
    var matches: [Match] = []
    var tables: [String: [StandingGroup]] = [:]
    var teams: [String: [Team]] = [:]
    /// Leagues with a match in play right now.
    var liveLeagueIDs: Set<String> = []
    var status: DataStatus = .loading
    /// Latest request error, shown only when offline or stale.
    var lastError: String?
    var lastSuccess: Date?
}

actor MatchRepository {
    private let client: ESPNClient
    private let cache: HTTPCache
    private let calendar: Calendar
    private let maxConcurrentRequests: Int

    /// Decoded cache entries, tagged with the fetch time they were decoded from.
    private var decoded: [String: (fetchedAt: Date, value: Decoded)] = [:]
    /// Last failure time per cache key, for the one-minute back-off.
    private var failures: [String: Date] = [:]
    /// Latest failure message per cache key, pruned to the endpoints still polled.
    private var errors: [String: (message: String, at: Date)] = [:]
    private var lastSuccess: Date?
    /// The fetch pass currently running; overlapping refreshes wait for it instead of duplicating it.
    private var inFlight: Task<Void, Never>?

    private enum Decoded {
        case matches([Match])
        case standings([StandingGroup])
        case teams([Team])
    }

    init(client: ESPNClient, cache: HTTPCache, calendar: Calendar = .current, maxConcurrentRequests: Int = 8) {
        self.client = client
        self.cache = cache
        self.calendar = calendar
        self.maxConcurrentRequests = max(1, maxConcurrentRequests)
    }

    // MARK: Public API

    /// Fetches whatever is due for `leagues` and `favorites`, then returns a snapshot.
    ///
    /// A call made while another is still fetching joins that pass rather than
    /// starting its own, so overlapping refreshes never fetch an endpoint twice.
    /// Anything the joined pass did not cover is picked up by the next refresh.
    func refreshDue(now: Date, leagues: [String], favorites: [FavoriteTeam]) async -> MatchSnapshot {
        if let inFlight {
            await inFlight.value
        } else {
            let pass = Task { await self.fetchDue(now: now, leagues: leagues, favorites: favorites) }
            inFlight = pass
            await pass.value
            inFlight = nil
        }
        pruneErrors(keeping: relevantKeys(now: now, leagues: Self.enabledLeagues(leagues), favorites: favorites))
        return await snapshot(now: now, leagues: leagues, favorites: favorites)
    }

    private func fetchDue(now: Date, leagues: [String], favorites: [FavoriteTeam]) async {
        let enabled = Self.enabledLeagues(leagues)
        let jobs = await dueJobs(now: now, leagues: enabled, favorites: favorites)
        if !jobs.isEmpty {
            await run(jobs, now: now)
            let window = Set(League.all.flatMap { league in
                windowDays(now: now).map { ESPNEndpoint.scoreboard(league: league.id, day: $0.day).cacheKey }
            })
            await cache.prune(keepingScoreboards: window)
            for key in decoded.keys where key.hasPrefix("sb:") && !window.contains(key) {
                decoded[key] = nil
            }
        }
    }

    /// Marks every cached response expired (the Refresh command). Cached data stays visible.
    func forceRefresh(now: Date) async {
        await cache.invalidateAll(now: now)
        failures.removeAll()
    }

    /// The current data without fetching anything.
    func snapshot(now: Date, leagues: [String], favorites: [FavoriteTeam]) async -> MatchSnapshot {
        let enabled = Self.enabledLeagues(leagues)
        var byID: [String: Match] = [:]

        for favorite in favorites {
            for fixture in [false, true] {
                let key = ESPNEndpoint.schedule(league: favorite.leagueID, teamID: favorite.teamID, fixture: fixture)
                for match in await matches(for: key.cacheKey) {
                    byID[match.id] = match
                }
            }
        }
        for league in enabled {
            for (_, day) in windowDays(now: now) {
                for var match in await matches(for: ESPNEndpoint.scoreboard(league: league, day: day).cacheKey) {
                    // Scoreboards win, but keep TV names a schedule already knew.
                    if match.tvNames.isEmpty, let old = byID[match.id] {
                        match.tvNames = old.tvNames
                    }
                    byID[match.id] = match
                }
            }
        }
        let matches = byID.values.sorted { lhs, rhs in
            if lhs.kickoff != rhs.kickoff { return lhs.kickoff < rhs.kickoff }
            if lhs.leagueID != rhs.leagueID { return lhs.leagueID < rhs.leagueID }
            return lhs.home.team.shortName < rhs.home.team.shortName
        }

        var tables: [String: [StandingGroup]] = [:]
        var teams: [String: [Team]] = [:]
        for league in League.all {
            if case .standings(let groups)? = await value(for: ESPNEndpoint.standings(league: league.id).cacheKey) {
                tables[league.id] = groups
            }
            if case .teams(let list)? = await value(for: ESPNEndpoint.teams(league: league.id).cacheKey) {
                teams[league.id] = list
            }
        }

        let status = DataStatus.derive(hasMatches: !matches.isEmpty, hasErrors: !errors.isEmpty,
                                       lastSuccess: lastSuccess, now: now)
        return MatchSnapshot(
            matches: matches,
            tables: tables,
            teams: teams,
            liveLeagueIDs: Set(matches.filter(\.isLive).map(\.leagueID)),
            status: status,
            lastError: errors.values.max { $0.at < $1.at }?.message,
            lastSuccess: lastSuccess
        )
    }

    // MARK: Scheduling

    /// Endpoints whose cached copy is older than its tier allows (`Engine.jobs`).
    func dueJobs(now: Date, leagues: [String], favorites: [FavoriteTeam]) async -> [ESPNEndpoint] {
        var jobs: [ESPNEndpoint] = []
        for league in leagues {
            var leagueIsLive = false
            for (offset, day) in windowDays(now: now) {
                let endpoint = ESPNEndpoint.scoreboard(league: league, day: day)
                var hot = false
                if abs(offset) <= 1 {
                    hot = RefreshPolicy.isHot(await matches(for: endpoint.cacheKey), now: now)
                    leagueIsLive = leagueIsLive || hot
                }
                if await isDue(endpoint, ttl: RefreshPolicy.scoreboardTTL(dayOffset: offset, hot: hot), now: now) {
                    jobs.append(endpoint)
                }
            }
            let table = ESPNEndpoint.standings(league: league)
            if await isDue(table, ttl: RefreshPolicy.standingsTTL(leagueIsLive: leagueIsLive), now: now) {
                jobs.append(table)
            }
            let teams = ESPNEndpoint.teams(league: league)
            if await isDue(teams, ttl: RefreshPolicy.teamsTTL, now: now) {
                jobs.append(teams)
            }
        }
        for favorite in favorites {
            for fixture in [false, true] {
                let endpoint = ESPNEndpoint.schedule(league: favorite.leagueID, teamID: favorite.teamID, fixture: fixture)
                if await isDue(endpoint, ttl: RefreshPolicy.scheduleTTL, now: now) {
                    jobs.append(endpoint)
                }
            }
        }
        return jobs
    }

    private func isDue(_ endpoint: ESPNEndpoint, ttl: TimeInterval, now: Date) async -> Bool {
        let key = endpoint.cacheKey
        if let failed = failures[key], now.timeIntervalSince(failed) < RefreshPolicy.failureBackoff {
            return false
        }
        return await cache.age(of: key, now: now) >= ttl
    }

    /// Local days of the polling window with their offset from today.
    private func windowDays(now: Date) -> [(offset: Int, day: String)] {
        let today = calendar.startOfDay(for: now)
        return RefreshPolicy.dayOffsets.compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
                .map { (offset, ESPNEndpoint.dayStamp($0, calendar: calendar)) }
        }
    }

    static func enabledLeagues(_ ids: [String]) -> [String] {
        let known = ids.filter { League.with(id: $0) != nil }
        return known.isEmpty ? League.all.map(\.id) : known
    }

    // MARK: Fetching

    private func run(_ jobs: [ESPNEndpoint], now: Date) async {
        let client = client
        let limit = maxConcurrentRequests
        let results = await withTaskGroup(of: (ESPNEndpoint, Result<Data, Error>).self) { group in
            var pending = jobs.makeIterator()
            var collected: [(ESPNEndpoint, Result<Data, Error>)] = []
            func launch(_ endpoint: ESPNEndpoint) {
                group.addTask {
                    do { return (endpoint, .success(try await client.data(for: endpoint))) }
                    catch { return (endpoint, .failure(error)) }
                }
            }
            for _ in 0..<limit {
                guard let next = pending.next() else { break }
                launch(next)
            }
            while let result = await group.next() {
                collected.append(result)
                if let next = pending.next() { launch(next) }
            }
            return collected
        }

        for (endpoint, result) in results {
            let key = endpoint.cacheKey
            switch result {
            case .success(let data):
                do {
                    let value = try Self.decode(data, for: endpoint)
                    await cache.store(data, for: key, at: now)
                    decoded[key] = (now, value)
                    failures[key] = nil
                    errors[key] = nil
                    lastSuccess = now
                } catch {
                    recordFailure(key: key, error: error, now: now)
                }
            case .failure(let error):
                recordFailure(key: key, error: error, now: now)
            }
        }
    }

    private func recordFailure(key: String, error: Error, now: Date) {
        failures[key] = now
        errors[key] = (error.localizedDescription, now)
    }

    /// Cache keys of every endpoint polled for these leagues and favorites.
    private func relevantKeys(now: Date, leagues: [String], favorites: [FavoriteTeam]) -> Set<String> {
        var keys: Set<String> = []
        for league in leagues {
            for (_, day) in windowDays(now: now) {
                keys.insert(ESPNEndpoint.scoreboard(league: league, day: day).cacheKey)
            }
            keys.insert(ESPNEndpoint.standings(league: league).cacheKey)
            keys.insert(ESPNEndpoint.teams(league: league).cacheKey)
        }
        for favorite in favorites {
            for fixture in [false, true] {
                keys.insert(ESPNEndpoint.schedule(league: favorite.leagueID, teamID: favorite.teamID,
                                                  fixture: fixture).cacheKey)
            }
        }
        return keys
    }

    /// Drops errors of endpoints no longer polled (unfollowed teams, disabled
    /// leagues, days that left the window) so they stop marking data offline.
    private func pruneErrors(keeping keys: Set<String>) {
        errors = errors.filter { keys.contains($0.key) }
    }

    // MARK: Decoding

    private static func decode(_ data: Data, for endpoint: ESPNEndpoint) throws -> Decoded {
        switch endpoint {
        case .scoreboard, .schedule:
            .matches(try ESPNMapper.matches(from: data, leagueID: endpoint.leagueID))
        case .standings:
            .standings(try ESPNMapper.standings(from: data, leagueID: endpoint.leagueID))
        case .teams:
            .teams(try ESPNMapper.teams(from: data, leagueID: endpoint.leagueID))
        }
    }

    /// Decoded value for a cache key, decoding the cached bytes on demand.
    private func value(for key: String) async -> Decoded? {
        guard let entry = await cache.entry(for: key) else { return nil }
        if let hit = decoded[key], hit.fetchedAt == entry.fetchedAt { return hit.value }
        guard let endpoint = Self.endpoint(forKey: key),
              let value = try? Self.decode(entry.data, for: endpoint) else { return nil }
        decoded[key] = (entry.fetchedAt, value)
        return value
    }

    private func matches(for key: String) async -> [Match] {
        if case .matches(let list)? = await value(for: key) { return list }
        return []
    }

    /// Rebuilds the endpoint a cache key came from (only its kind and league matter for decoding).
    static func endpoint(forKey key: String) -> ESPNEndpoint? {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }
        switch (parts[0], parts.count) {
        case ("sb", 3): return .scoreboard(league: parts[1], day: parts[2])
        case ("table", 2): return .standings(league: parts[1])
        case ("teams", 2): return .teams(league: parts[1])
        case ("sched", 3): return .schedule(league: parts[1], teamID: parts[2], fixture: false)
        case ("fix", 3): return .schedule(league: parts[1], teamID: parts[2], fixture: true)
        default: return nil
        }
    }
}
