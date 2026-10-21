//
//  LeaguePicker.swift
//  matchday
//
//  One chip per enabled league, scrolling sideways (`ButtonGroup` over
//  `leagueOptions` on the Tables and Teams tabs).
//

import SwiftUI

struct LeaguePicker: View {
    @Binding var selection: String
    let leagues: [League]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(leagues) { league in
                    Chip(title: league.short, isSelected: selection == league.id, size: .small) {
                        selection = league.id
                    }
                    .help(league.name)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.never)
    }
}

#Preview {
    @Previewable @State var selection = League.laLiga.id
    LeaguePicker(selection: $selection, leagues: League.all)
        .padding()
        .frame(width: Theme.panelWidth)
        .background(Theme.background)
}
