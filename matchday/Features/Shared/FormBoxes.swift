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

    @Environment(\.locale) private var locale

    var body: some View {
        letter
            .font(.system(size: size * 0.58, weight: .bold))
            .foregroundStyle(result.outcome == .draw ? Theme.foreground : .white)
            .frame(width: size, height: size)
            .background(color, in: .rect(cornerRadius: size / 4))
            .help(result.isHome ? "vs \(result.opponent)  \(result.score)" : "at \(result.opponent)  \(result.score)")
            .accessibilityLabel(accessibilityText)
    }

    /// W, D or L, the same keys as the standings columns.
    private var letter: Text {
        switch result.outcome {
        case .win: Text("W")
        case .draw: Text("D")
        case .loss: Text("L")
        }
    }

    private var color: Color {
        switch result.outcome {
        case .win: Theme.win
        case .loss: Theme.urgent
        case .draw: Theme.foreground.opacity(0.25)
        }
    }

    private var accessibilityText: Text {
        let summary = result.summary(locale: locale)
        return switch result.outcome {
        case .win: Text("Win \(summary)", comment: "VoiceOver: a recent win, then its score and opponent.")
        case .draw: Text("Draw \(summary)", comment: "VoiceOver: a recent draw, then its score and opponent.")
        case .loss: Text("Loss \(summary)", comment: "VoiceOver: a recent loss, then its score and opponent.")
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
