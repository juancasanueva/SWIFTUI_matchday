//
//  FakeTransport.swift
//  matchdayTests
//

import Foundation
@testable import matchday

/// In-memory `HTTPTransport`: routes each request through a handler and records it.
actor FakeTransport: HTTPTransport {
    enum Reply: Sendable {
        case json(String)
        case data(Data)
        case status(Int, String)
        case failure
    }

    struct TransportFailure: Error {}

    private var handler: @Sendable (URL) -> Reply
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping @Sendable (URL) -> Reply) {
        self.handler = handler
    }

    func setHandler(_ handler: @escaping @Sendable (URL) -> Reply) {
        self.handler = handler
    }

    func resetRequests() {
        requests = []
    }

    var requestedURLs: [String] { requests.compactMap { $0.url?.absoluteString } }

    func get(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let url = request.url!
        func response(_ code: Int) -> URLResponse {
            HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)!
        }
        switch handler(url) {
        case .json(let body): return (Data(body.utf8), response(200))
        case .data(let data): return (data, response(200))
        case .status(let code, let body): return (Data(body.utf8), response(code))
        case .failure: throw TransportFailure()
        }
    }
}

/// Calendar pinned to UTC so day boundaries are deterministic.
func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    utcCalendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// A fresh, unique directory under the (sandboxed) temporary directory.
func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "matchday-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
}
