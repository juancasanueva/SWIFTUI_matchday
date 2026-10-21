//
//  Chip.swift
//  matchday
//
//  Rounded, bordered toggle used by the tab bar and the filters (`ButtonGroup`).
//

import SwiftUI

struct Chip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    var size: Theme.Size = .body
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(Theme.font(size, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, size == .body ? 12 : 10)
            .padding(.vertical, size == .body ? 6 : 5)
            .background(background, in: .rect(cornerRadius: Theme.cornerRadius + 2))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius + 2)
                    .strokeBorder(isSelected ? Theme.foreground.opacity(0.3) : Theme.faint, lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected { return Theme.foreground.opacity(0.14) }
        return isHovered ? Theme.hover : .clear
    }
}

#Preview {
    HStack {
        Chip(title: "Following", isSelected: true) {}
        Chip(title: "Matches", isSelected: false) {}
        Chip(title: "Mine", systemImage: "star.fill", isSelected: false, size: .small) {}
    }
    .padding()
    .background(Theme.background)
}
