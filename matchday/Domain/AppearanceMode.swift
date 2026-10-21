//
//  AppearanceMode.swift
//  matchday
//
//  Light or dark panel, or whatever the system uses.
//

import Foundation

nonisolated enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
