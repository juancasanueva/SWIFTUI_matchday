//
//  AboutView.swift
//  matchday
//
//  The About window content: icon, name and tagline, version, project rows
//  and a footer, on the panel's background and cards. Presentational: it
//  renders one `AboutInfo` and reads nothing else.
//

import AppKit
import SwiftUI

struct AboutView: View {
    let info: AboutInfo

    /// Fixed content width; the window is sized from it and is not resizable.
    static let width: CGFloat = 400

    /// The asset catalog icon. `NSApp.applicationIconImage` is only the
    /// fallback: it returns the generic icon when Launch Services has not
    /// registered the running process.
    static var icon: NSImage {
        NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
    }

    private static let iconSize: CGFloat = 72

    var body: some View {
        VStack(spacing: 14) {
            header
            AboutCard(rows: [AboutRow(label: "Version", value: info.versionText)])
            AboutCard(rows: info.rows)
            Text(info.footer)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(20)
        .frame(width: Self.width)
        .background(Theme.background)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: Self.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(info.appName)
                    .font(Theme.font(.heading, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                Text(info.tagline)
                    .font(Theme.font(.small))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Rows stacked on one bordered card with a hairline between each pair.
private struct AboutCard: View {
    let rows: [AboutRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                if row.id != rows.first?.id {
                    Rectangle()
                        .fill(Theme.faint)
                        .frame(height: 1)
                        .padding(.horizontal, 12)
                }
                AboutRowView(row: row)
            }
        }
        .background(Theme.fill, in: .rect(cornerRadius: Theme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(Theme.faint, lineWidth: 1)
        }
    }
}

/// A bold label on the left and the value, or a link, on the right.
private struct AboutRowView: View {
    let row: AboutRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(row.label)
                .font(Theme.font(.body, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .fixedSize()
            Spacer(minLength: 8)
            if let url = row.url {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text(row.value)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "arrow.up.forward.square")
                            .imageScale(.small)
                    }
                    .font(Theme.font(.small))
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help(url.absoluteString)
            } else {
                Text(row.value)
                    .font(Theme.font(.small))
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

/// Root the About window hosts.
struct AboutRootView: View {
    let info: AboutInfo

    var body: some View {
        AboutView(info: info)
    }
}

#if DEBUG
#Preview("About") {
    AboutRootView(info: AboutModel.info(bundleInfo: [
        "CFBundleShortVersionString": "1.0.0",
        "CFBundleVersion": "1",
    ]))
}
#endif
