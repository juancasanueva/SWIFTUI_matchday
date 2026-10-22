//
//  Chip.swift
//  matchday
//
//  Rounded, bordered toggle used by the tab bar and the filters (`ButtonGroup`).
//

import SwiftUI

struct Chip: View {
    let title: Text
    var systemImage: String?
    let isSelected: Bool
    var size: Theme.Size = .body
    let action: () -> Void

    @State private var isHovered = false

    /// A literal title, looked up in the string catalog.
    init(title: LocalizedStringKey, systemImage: String? = nil, isSelected: Bool, size: Theme.Size = .body,
         action: @escaping () -> Void) {
        self.init(text: Text(title), systemImage: systemImage, isSelected: isSelected, size: size, action: action)
    }

    /// Data drawn as is, never translated: league short names.
    init(verbatim title: String, systemImage: String? = nil, isSelected: Bool, size: Theme.Size = .body,
         action: @escaping () -> Void) {
        self.init(text: Text(verbatim: title), systemImage: systemImage, isSelected: isSelected, size: size,
                  action: action)
    }

    private init(text: Text, systemImage: String?, isSelected: Bool, size: Theme.Size, action: @escaping () -> Void) {
        title = text
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                }
                title
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
