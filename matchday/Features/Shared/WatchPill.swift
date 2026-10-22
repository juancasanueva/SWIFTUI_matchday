//
//  WatchPill.swift
//  matchday
//
//  Broadcaster pills; clicking one opens the service (`WatchChips` in Panel.qml).
//

import SwiftUI

struct WatchPill: View {
    let service: Broadcaster

    @Environment(\.openURL) private var openURL
    @State private var isHovered = false

    var body: some View {
        Button {
            if let url = service.url { openURL(url) }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text(service.name)
                    .font(Theme.font(.small, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                if let language = service.language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.dim)
                }
                if service.kind == .free {
                    Text("FREE")
                        .font(Theme.font(.caption, weight: .bold))
                        .foregroundStyle(Theme.win)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Theme.foreground.opacity(isHovered ? 0.14 : 0.06), in: .capsule)
            .overlay {
                Capsule().strokeBorder(isHovered ? tint : Theme.faint, lineWidth: 1)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(service.url == nil)
        .onHover { isHovered = $0 && service.url != nil }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(service.url == nil ? Text(verbatim: service.name) : Text("Open \(service.name)"))
    }

    private var tint: Color {
        Color(hex: service.colorHex) ?? Theme.accent
    }
}

/// Wrapping row of pills.
struct WatchPills: View {
    let services: [Broadcaster]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(services) { WatchPill(service: $0) }
        }
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

#if DEBUG
#Preview {
    WatchPills(services: PreviewData.services)
        .frame(width: 300)
        .padding()
        .background(Theme.background)
}
#endif
