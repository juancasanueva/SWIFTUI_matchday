//
//  Fixtures.swift
//  matchdayTests
//

import Foundation

/// Anchor class used to locate the test bundle (Swift Testing has no XCTestCase).
final class BundleToken {}

enum Fixture {
    enum LoadError: Error { case missing(String) }

    /// Loads `matchdayTests/Fixtures/<name>.json` from the test bundle.
    ///
    /// The tests run hosted in the sandboxed app, so fixtures are read from the
    /// bundle instead of the source tree.
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        guard let url else { throw LoadError.missing(name) }
        return try Data(contentsOf: url)
    }
}
