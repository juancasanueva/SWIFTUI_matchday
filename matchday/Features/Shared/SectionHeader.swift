//
//  SectionHeader.swift
//  matchday
//
//  Small uppercase kicker used for section titles (`PanelSectionHeader`).
//

import SwiftUI

struct SectionHeader<Trailing: View>: View {
    let title: Text
    var color: Color = Theme.foreground
    @ViewBuilder var trailing: Trailing

    /// A literal title, looked up in the string catalog.
    init(title: LocalizedStringKey, color: Color = Theme.foreground, @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(title)
        self.color = color
        self.trailing = trailing()
    }

    /// Text drawn as is: an already localized day label, or a group name from ESPN.
    init(verbatim title: String, color: Color = Theme.foreground, @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(verbatim: title)
        self.color = color
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            title
                .font(Theme.font(.caption, weight: .bold))
                .tracking(1)
                .foregroundStyle(color)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey, color: Color = Theme.foreground) {
        self.init(title: title, color: color) { EmptyView() }
    }

    init(verbatim title: String, color: Color = Theme.foreground) {
        self.init(verbatim: title, color: color) { EmptyView() }
    }
}

/// Fades a view in and out while `isActive` (live markers); still under Reduce Motion.
struct Pulse: ViewModifier {
    let isActive: Bool
    var minimum: Double = 0.45

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isActive && !reduceMotion {
            content.phaseAnimator([false, true]) { view, dimmed in
                view.opacity(dimmed ? minimum : 1)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
        } else {
            content
        }
    }
}

extension View {
    func pulsing(_ isActive: Bool, minimum: Double = 0.45) -> some View {
        modifier(Pulse(isActive: isActive, minimum: minimum))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "LIVE ELSEWHERE", color: Theme.urgent)
        SectionHeader(verbatim: "TODAY · WED, OCT 21") {
            Text("● 2 LIVE").font(Theme.font(.caption, weight: .bold)).foregroundStyle(Theme.urgent).pulsing(true)
        }
    }
    .padding()
    .frame(width: 400)
    .background(Theme.background)
}
