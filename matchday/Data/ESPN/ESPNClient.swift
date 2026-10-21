//
//  ESPNClient.swift
//  matchday
//

import Foundation

nonisolated enum ESPNError: Error, Equatable, LocalizedError {
    /// ESPN answered with its `{code, message}` error body.
    case api(String)
    case http(Int)
    case tooLarge
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .api(let message): "ESPN: \(message)"
        case .http(let code): "HTTP Error \(code)"
        case .tooLarge: "response too large"
        case .invalidResponse: "invalid response"
        }
    }
}

/// ESPN adapter for the `SoccerDataSource` port (`http_get` / `http_json` in the original).
nonisolated struct ESPNClient: SoccerDataSource {
    static let userAgent = "grivera-matchday/1.0"
    static let timeout: TimeInterval = 12
    /// ESPN scoreboards run ~1 MB; anything far bigger is not a real response.
    static let maxBodySize = 16 * 1024 * 1024

    let transport: any HTTPTransport
    /// Calendar used to turn dates into scoreboard days.
    let calendar: Calendar

    init(transport: any HTTPTransport = URLSessionTransport(), calendar: Calendar = .current) {
        self.transport = transport
        self.calendar = calendar
    }

    // MARK: Raw access (used by the cached repository)

    func request(for endpoint: ESPNEndpoint) -> URLRequest {
        var request = URLRequest(url: endpoint.url, timeoutInterval: Self.timeout)
        request.httpMethod = "GET"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Fetches the raw JSON body for `endpoint`, rejecting HTTP and ESPN errors.
    func data(for endpoint: ESPNEndpoint) async throws -> Data {
        let (data, response) = try await transport.get(request(for: endpoint))
        guard let http = response as? HTTPURLResponse else { throw ESPNError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ESPNError.http(http.statusCode) }
        guard data.count <= Self.maxBodySize else { throw ESPNError.tooLarge }
        if let message = Self.errorMessage(in: data) { throw ESPNError.api(message) }
        return data
    }

    /// ESPN reports some failures as a 200 with a tiny `{code, message}` object.
    static func errorMessage(in data: Data) -> String? {
        guard data.count < 4096,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object.count <= 3,
              let message = object["message"] as? String, !message.isEmpty,
              let code = object["code"], !(code is NSNull)
        else { return nil }
        if let string = code as? String, string.isEmpty { return nil }
        if let number = code as? NSNumber, number == 0 { return nil }
        return message
    }

    // MARK: SoccerDataSource

    func scoreboard(league: String, date: Date) async throws -> [Match] {
        let day = ESPNEndpoint.dayStamp(date, calendar: calendar)
        return try ESPNMapper.matches(from: await data(for: .scoreboard(league: league, day: day)), leagueID: league)
    }

    func standings(league: String) async throws -> [StandingGroup] {
        try ESPNMapper.standings(from: await data(for: .standings(league: league)), leagueID: league)
    }

    func teams(league: String) async throws -> [Team] {
        try ESPNMapper.teams(from: await data(for: .teams(league: league)), leagueID: league)
    }

    func schedule(league: String, teamID: String, fixture: Bool) async throws -> [Match] {
        let endpoint = ESPNEndpoint.schedule(league: league, teamID: teamID, fixture: fixture)
        return try ESPNMapper.matches(from: await data(for: endpoint), leagueID: league)
    }
}
