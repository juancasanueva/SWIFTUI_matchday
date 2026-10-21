//
//  PanelView.swift
//  matchday
//

import SwiftUI

/// Placeholder content of the menu bar panel. Tabs and data arrive in later tasks.
struct PanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Matchday")
                .font(.title2.bold())
            Text("Following, matches and tables will appear here.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider()
            Button("Quit Matchday") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
    }
}

#Preview {
    PanelView()
}
