//
//  SettingsSection.swift
//  matchday
//
//  SETTINGS below the Teams grid: watch country, toggles, kickoff lead time,
//  enabled leagues, launch at login, Test notification and Refresh. Every
//  change goes through the store, which persists it.
//

import SwiftUI

/// Container: turns store and login-item state into bindings and actions.
struct SettingsSection: View {
    @Environment(MatchdayStore.self) private var store
    @Environment(LaunchAtLogin.self) private var launchAtLogin

    var body: some View {
        let settings = store.settings
        SettingsForm(
            country: Binding(get: { store.selectedCountry },
                             set: { code in store.updateSettings { $0.country = code } }),
            countryOptions: store.countryOptions,
            spanish: setting(\.spanish),
            notifyKickoff: setting(\.notifyKickoff),
            kickoffLead: Binding(get: { store.settings.kickoffLead }, set: store.setKickoffLead),
            notifyGoals: setting(\.notifyGoals),
            notifyFinal: setting(\.notifyFinal),
            barScore: setting(\.barScore),
            leagues: League.all.map { league in
                LeagueSwitch(league: league, isOn: settings.isLeagueEnabled(league.id),
                             isLocked: !store.canDisableLeague(league.id))
            },
            onSetLeague: store.setLeague,
            launchAtLogin: Binding(get: { launchAtLogin.isEnabled }, set: launchAtLogin.setEnabled),
            launchNote: launchNote,
            onOpenLoginItems: { MainAppLoginItem.openSystemSettings() },
            onTestNotification: store.sendTestNotification,
            onRefresh: refresh
        )
        .onAppear { launchAtLogin.refreshStatus() }
    }

    private func setting(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { store.settings[keyPath: keyPath] },
                set: { value in store.updateSettings { $0[keyPath: keyPath] = value } })
    }

    /// Error or approval hint under the launch-at-login toggle.
    private var launchNote: String? {
        if let error = launchAtLogin.errorMessage { return error }
        return launchAtLogin.needsApproval ? "Allow Matchday in System Settings › Login Items." : nil
    }

    private func refresh() {
        Task { await store.refreshNow() }
    }
}

/// One row of the Leagues card.
struct LeagueSwitch: Identifiable, Hashable {
    let league: League
    let isOn: Bool
    /// The last enabled league cannot be turned off.
    let isLocked: Bool

    var id: String { league.id }
}

struct SettingsForm: View {
    @Binding var country: String
    let countryOptions: [CountryOption]
    @Binding var spanish: Bool
    @Binding var notifyKickoff: Bool
    @Binding var kickoffLead: Int
    @Binding var notifyGoals: Bool
    @Binding var notifyFinal: Bool
    @Binding var barScore: Bool
    let leagues: [LeagueSwitch]
    let onSetLeague: (String, Bool) -> Void
    @Binding var launchAtLogin: Bool
    let launchNote: String?
    let onOpenLoginItems: () -> Void
    let onTestNotification: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "SETTINGS")
            countryPicker
            SettingCard(title: "Spanish-language channels",
                        description: "Telemundo, Universo, ESPN Deportes, FOX Deportes and friends.",
                        isOn: $spanish)
            SettingCard(title: "Kickoff reminders",
                        description: "\(kickoffLead) minutes before your teams play, with where to watch.",
                        isOn: $notifyKickoff) {
                Stepper(value: $kickoffLead, in: AppSettings.kickoffLeadRange) {
                    Text("Remind me \(kickoffLead) min before kickoff")
                        .font(Theme.font(.small))
                        .foregroundStyle(notifyKickoff ? Theme.foreground : Theme.dim)
                }
                .disabled(!notifyKickoff)
            }
            SettingCard(title: "Goal alerts", description: "Every goal in your teams' matches, with the scorer.",
                        isOn: $notifyGoals)
            SettingCard(title: "Full-time results", isOn: $notifyFinal)
            SettingCard(title: "Live score in the bar",
                        description: "Shows the score next to the ball while one of your teams is playing.",
                        isOn: $barScore)
            leaguesCard
            SettingCard(title: "Launch at login", description: "Start Matchday when you log in to your Mac.",
                        isOn: $launchAtLogin) {
                if let launchNote {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(launchNote)
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.urgent)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button("Open Login Items", action: onOpenLoginItems)
                            .buttonStyle(OutlineButtonStyle())
                    }
                }
            }
            HStack(spacing: 8) {
                Button("Test notification", action: onTestNotification)
                Button("Refresh", action: onRefresh)
                    .help("Refetch everything now")
            }
            .buttonStyle(OutlineButtonStyle())
        }
    }

    private var countryPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Watching from")
                .font(Theme.font(.small, weight: .semibold))
                .foregroundStyle(Theme.dim)
            // A full-width dropdown (`Dropdown` in Panel.qml); a menu-style Picker
            // keeps its intrinsic width.
            Menu {
                Picker("Watching from", selection: $country) {
                    ForEach(countryOptions) { option in
                        Text(option.label).tag(option.code)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack {
                    Text(countryOptions.first { $0.code == country }?.label ?? country)
                        .font(Theme.font(.body))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .imageScale(.small)
                        .foregroundStyle(Theme.dim)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Theme.fill, in: .rect(cornerRadius: Theme.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .strokeBorder(Theme.foreground.opacity(0.3), lineWidth: 1)
                }
                .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Watching from")
            .accessibilityValue(countryOptions.first { $0.code == country }?.label ?? country)
            .help("Where to watch uses this country")
        }
    }

    private var leaguesCard: some View {
        SettingCardFrame {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Leagues")
                        .font(Theme.font(.body, weight: .semibold))
                    Text("Shown in Matches, Tables and Teams. At least one stays on.")
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(leagues) { item in
                    Toggle(isOn: Binding(get: { item.isOn }, set: { onSetLeague(item.league.id, $0) })) {
                        HStack(spacing: 8) {
                            LeagueDot(league: item.league)
                                .accessibilityHidden(true)
                            Text(item.league.name)
                                .font(Theme.font(.small))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(item.isOn && item.isLocked)
                }
            }
        }
    }
}

/// Bordered card with a title, an optional description, a switch, and optional extra controls.
struct SettingCard<Extra: View>: View {
    let title: String
    var description: String?
    @Binding var isOn: Bool
    @ViewBuilder var extra: Extra

    var body: some View {
        SettingCardFrame {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $isOn) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(Theme.font(.body, weight: .semibold))
                        if let description {
                            Text(description)
                                .font(Theme.font(.caption))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                extra
            }
        }
    }
}

extension SettingCard where Extra == EmptyView {
    init(title: String, description: String? = nil, isOn: Binding<Bool>) {
        self.init(title: title, description: description, isOn: isOn) { EmptyView() }
    }
}

struct SettingCardFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.fill, in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(Theme.faint, lineWidth: 1)
            }
    }
}

/// Small bordered capsule button ("Test notification", "Refresh").
struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(.caption))
            .foregroundStyle(isEnabled ? Theme.foreground : Theme.dim)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? Theme.hover : .clear, in: .rect(cornerRadius: Theme.cornerRadius + 2))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius + 2)
                    .strokeBorder(Theme.foreground.opacity(0.3), lineWidth: 1)
            }
            .contentShape(.rect)
    }
}

#if DEBUG
#Preview {
    @Previewable @State var country = AppSettings.automaticCountry
    @Previewable @State var flags = [true, true, true, true, true, false]
    @Previewable @State var lead = 15
    ScrollView {
        SettingsForm(
            country: $country,
            countryOptions: [CountryOption(code: "auto", label: "Automatic — Madrid, Spain"),
                             CountryOption(code: "ES", label: "Spain")],
            spanish: $flags[0], notifyKickoff: $flags[1], kickoffLead: $lead, notifyGoals: $flags[2],
            notifyFinal: $flags[3], barScore: $flags[4],
            leagues: League.all.map { LeagueSwitch(league: $0, isOn: true, isLocked: false) },
            onSetLeague: { _, _ in },
            launchAtLogin: $flags[5], launchNote: nil, onOpenLoginItems: {},
            onTestNotification: {}, onRefresh: {}
        )
        .padding(16)
    }
    .frame(width: Theme.panelWidth, height: Theme.panelHeight)
    .background(Theme.background)
}
#endif
