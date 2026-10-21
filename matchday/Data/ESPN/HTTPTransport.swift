//
//  HTTPTransport.swift
//  matchday
//

import Foundation

/// Minimal HTTP seam so the ESPN client can be tested without the network.
nonisolated protocol HTTPTransport: Sendable {
    func get(_ request: URLRequest) async throws -> (Data, URLResponse)
}

/// Production transport backed by `URLSession` (which also handles gzip).
nonisolated struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    init(session: URLSession = URLSessionTransport.makeSession()) {
        self.session = session
    }

    func get(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    /// Ephemeral session: Matchday keeps its own disk cache with its own TTLs.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = ESPNClient.timeout
        configuration.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: configuration)
    }
}
