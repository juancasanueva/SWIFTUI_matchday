//
//  LanguageCard.swift
//  matchday
//
//  The Language card in SETTINGS: one round flag per shipped language in a
//  3 x 3 grid, each named in its own language. Picking one switches the app at
//  once; until then the app follows the system language.
//

import SwiftUI

struct LanguageCard: View {
    let selection: AppLanguage
    let onSelect: (AppLanguage) -> Void

    var body: some View {
        SettingCardFrame {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Language")
                        .font(Theme.font(.body, weight: .semibold))
                    Text("Matchday follows your Mac's language until you pick one.")
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        LanguageFlag(language: language, isSelected: language == selection) {
                            onSelect(language)
                        }
                    }
                }
            }
        }
    }
}

/// One round flag with its native name; the selected one gets a ring and a checkmark.
private struct LanguageFlag: View {
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    /// Three across fit the fixed panel width with room to spare.
    private static let size: CGFloat = 40

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Image(language.flagAsset)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.size, height: Self.size)
                        .clipShape(.circle)
                        .overlay {
                            Circle().strokeBorder(isSelected ? Theme.foreground : Theme.faint,
                                                  lineWidth: isSelected ? 2 : 1)
                        }
                        // The unpicked flags step back without losing which country they are.
                        .opacity(isSelected ? 1 : 0.55)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.background, Theme.foreground)
                            .offset(x: 3, y: 3)
                    }
                }
                // Verbatim: a language names itself in every language.
                Text(verbatim: language.nativeName)
                    .font(Theme.font(.caption, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.foreground : Theme.dim)
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(isHovered && !isSelected ? Theme.hover : .clear, in: .rect(cornerRadius: Theme.cornerRadius))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: language.nativeName))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#if DEBUG
#Preview {
    @Previewable @State var language = AppLanguage.spanish
    LanguageCard(selection: language) { language = $0 }
        .padding(16)
        .frame(width: Theme.panelWidth)
        .background(Theme.background)
}
#endif
