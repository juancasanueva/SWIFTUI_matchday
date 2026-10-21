//
//  FormBoxes.swift
//  matchday
//
//  W/D/L result boxes (`FormDots` in Panel.qml).
//

import SwiftUI

struct FormBox: View {
    let result: FormResult
    var size: CGFloat = 16

    var body: some View {
        Text(result.outcome.rawValue)
            .font(.system(size: size * 0.58, weight: .bold, design: .monospaced))
            .foregroundStyle(result.outcome == .draw ? Theme.foreground : .white)
            .frame(width: size, height: size)
            .background(color, in: .rect(cornerRadius: size / 4))
            .help("\(result.isHome ? "vs" : "at") \(result.opponent)  \(result.score)")
            .accessibilityLabel("\(outcomeName) \(result.summary)")
    }

    private var color: Color {
        switch result.outcome {
        case .win: Theme.win
        case .loss: Theme.urgent
        case .draw: Theme.foreground.opacity(0.25)
        }
    }

    private var outcomeName: String {
        switch result.outcome {
        case .win: "Win"
        case .draw: "Draw"
        case .loss: "Loss"
        }
    }
}

/// The last results, oldest first.
struct FormBoxes: View {
    let form: [FormResult]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(form, id: \.matchID) { FormBox(result: $0) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent form")
    }
}

#if DEBUG
#Preview {
    FormBoxes(form: PreviewData.realMadridCard.form)
        .padding()
        .background(Theme.background)
}
#endif
