//
//  DisplayContext.swift
//  matchday
//
//  Clock and formatting helpers shared by the derivations (`dayLabel`,
//  `timeLabel`, `countdown`, `minute`, `statusText`, `ordinal` in Panel.qml).
//

import Foundation

nonisolated struct DisplayContext: Sendable {
    let now: Date
    /// Calendar (and its time zone) that decides what "today" is.
    let calendar: Calendar
    let locale: Locale

    init(now: Date, calendar: Calendar = .current, locale: Locale = .current) {
        self.now = now
        self.calendar = calendar
        self.locale = locale
    }

    var today: Date { calendar.startOfDay(for: now) }

    /// Whole calendar days from today to `date` (negative in the past).
    func dayOffset(of date: Date) -> Int {
        calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
    }

    // MARK: Dates and times

    /// "Today", "Tomorrow", "Yesterday", else "Fri Oct 23".
    func dayLabel(_ date: Date) -> String {
        switch dayOffset(of: date) {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: shortDate(date)
        }
    }

    /// Day section header: "TODAY · WED OCT 21", "FRI OCT 23".
    func sectionLabel(_ date: Date) -> String {
        let label = dayLabel(date)
        let full = label.contains(" ") ? label : "\(label) · \(shortDate(date))"
        return full.uppercased(with: locale)
    }

    /// "Fri Oct 23".
    func shortDate(_ date: Date) -> String {
        let style = Date.VerbatimFormatStyle(
            format: "\(weekday: .abbreviated) \(month: .abbreviated) \(day: .defaultDigits)",
            locale: locale, timeZone: calendar.timeZone, calendar: calendar)
        return date.formatted(style)
    }

    /// Locale short time, e.g. "9:00 PM".
    func timeLabel(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar)
        style.timeZone = calendar.timeZone
        // ICU separates the AM/PM marker with a narrow no-break space; keep labels plain.
        return date.formatted(style)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// "in 3h 53m", "in 2d 3h", "kicking off".
    func countdown(to date: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now).rounded(.down))
        if seconds <= 0 { return "kicking off" }
        let days = seconds / 86_400, hours = seconds % 86_400 / 3600, minutes = seconds % 3600 / 60
        if days > 0 { return "in \(days)d \(hours)h" }
        if hours > 0 { return "in \(hours)h \(minutes < 10 ? "0" : "")\(minutes)m" }
        if minutes > 0 { return "in \(minutes)m" }
        return "in \(seconds)s"
    }

    // MARK: Match status

    /// Live minute: "HT", the clock ("67'"), else the status detail.
    func minute(_ match: Match) -> String {
        if match.isHalftime { return "HT" }
        if !match.displayClock.isEmpty { return match.displayClock }
        return match.shortDetail.isEmpty ? "LIVE" : match.shortDetail
    }

    /// Row status: live minute, "PPD", the final detail ("FT"), or the kickoff time.
    func statusText(_ match: Match) -> String {
        if match.isLive { return minute(match) }
        if match.isPostponed { return "PPD" }
        if match.state == .post { return match.shortDetail.isEmpty ? "FT" : match.shortDetail }
        return timeLabel(match.kickoff)
    }

    /// 1st, 2nd, 3rd, 4th, 11th, 21st…
    static func ordinal(_ number: Int) -> String {
        let lastTwo = abs(number) % 100
        let suffix: String
        if (11...13).contains(lastTwo) {
            suffix = "th"
        } else {
            switch lastTwo % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(number)\(suffix)"
    }
}

nonisolated extension KeyEvent {
    /// "Mbappé 10' (P)", "Hugo Duro 30' (OG)".
    var label: String {
        let base = "\(player) \(minute)"
        switch kind {
        case .penalty: return base + " (P)"
        case .ownGoal: return base + " (OG)"
        case .goal, .redCard: return base
        }
    }
}

nonisolated extension MatchSide {
    /// Score as shown, with a missing or empty score as "0".
    var displayScore: String {
        guard let score, !score.isEmpty else { return "0" }
        return score
    }
}

nonisolated extension Match {
    /// Score as "2–1" (missing scores count as 0).
    var scoreText: String {
        "\(home.displayScore)–\(away.displayScore)"
    }
}
