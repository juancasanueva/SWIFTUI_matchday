//
//  GatedTransport.swift
//  matchdayTests
//

import Foundation
@testable import matchday

/// Holds every request until `open()` is called, then answers through `inner`.
///
/// Lets a test keep a fetch pass in flight for as long as it needs, without timing.
actor GatedTransport: HTTPTransport {
    let inner: FakeTransport
    private var isOpen = false
    private var arrived = 0
    private var held: [CheckedContinuation<Void, Never>] = []
    private var arrivalWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(inner: FakeTransport) {
        self.inner = inner
    }

    func get(_ request: URLRequest) async throws -> (Data, URLResponse) {
        arrived += 1
        let ready = arrivalWaiters.filter { $0.count <= arrived }
        arrivalWaiters.removeAll { $0.count <= arrived }
        ready.forEach { $0.continuation.resume() }
        if !isOpen {
            await withCheckedContinuation { held.append($0) }
        }
        return try await inner.get(request)
    }

    /// Releases the held requests and lets later ones through immediately.
    func open() {
        isOpen = true
        held.forEach { $0.resume() }
        held = []
    }

    /// Returns once at least `count` requests reached the transport.
    func waitForRequests(_ count: Int) async {
        guard arrived < count else { return }
        await withCheckedContinuation { arrivalWaiters.append((count, $0)) }
    }
}
