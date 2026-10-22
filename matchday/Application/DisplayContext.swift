//
//  DisplayContext.swift
//  matchday
//
//  Clock, language and formatting helpers shared by the derivations (`dayLabel`,
//  `timeLabel`, `countdown`, `minute`, `statusText`, `ordinal` in Panel.qml).
//

import Foundation

nonisolated struct DisplayContext: Sendable {
    let now: Date
    /// Calendar (and its time zone) that decides what "today" is.
    let calendar: Calendar
    /// The app locale: dates, times and numbers are formatted in it.
    let locale: Locale
    /// The language bundle texts are looked up in.
    let bundle: Bundle

    /// - Parameter bundle: Defaults to the language bundle of `locale`'s app language.
    init(now: Date, calendar: Calendar = .current, locale: Locale = .current, bundle: Bundle? = nil) {
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.bundle = bundle ?? locale.appBundle
    }

    var today: Date { calendar.startOfDay(for: now) }

    /// Whole calendar days from today to `date` (negative in the past).
    func dayOffset(of date: Date) -> Int {
        calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// `value` in the app language, its arguments formatted in the app locale.
    func text(_ value: String.LocalizationValue, comment: StaticString? = nil) -> String {
        String(appLocalized: value, bundle: bundle, locale: locale, comment: comment)
    }

    // MARK: Dates and times

    /// "Today", "Tomorrow", "Yesterday", else "Fri, Oct 23".
    func dayLabel(_ date: Date) -> String {
        switch dayOffset(of: date) {
        case 0: text("Today", comment: "Relative day of a match.")
        case 1: text("Tomorrow", comment: "Relative day of a match.")
        case -1: text("Yesterday", comment: "Relative day of a match.")
        default: shortDate(date)
        }
    }

    /// Day section header: "TODAY · WED, OCT 21", "FRI, OCT 23".
    func sectionLabel(_ date: Date) -> String {
        let full = (-1...1).contains(dayOffset(of: date)) ? "\(dayLabel(date)) · \(shortDate(date))" : shortDate(date)
        return full.uppercased(with: locale)
    }

    /// Weekday, month and day in the locale's order: "Fri, Oct 23", "Fr. 23. Okt.".
    func shortDate(_ date: Date) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar).weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = calendar.timeZone
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
        if seconds <= 0 { return text("kicking off", comment: "Countdown when a match is about to start.") }
        let days = seconds / 86_400, hours = seconds % 86_400 / 3600, minutes = seconds % 3600 / 60
        if days > 0 {
            return text("in \(days)d \(hours)h", comment: "Countdown to kickoff: days and hours, abbreviated.")
        }
        if hours > 0 {
            let paddedMinutes = (minutes < 10 ? "0" : "") + minutes.formatted(.number.locale(locale))
            return text("in \(hours)h \(paddedMinutes)m",
                        comment: "Countdown to kickoff: hours, then minutes padded to two digits, abbreviated.")
        }
        if minutes > 0 { return text("in \(minutes)m", comment: "Countdown to kickoff: minutes, abbreviated.") }
        return text("in \(seconds)s", comment: "Countdown to kickoff: seconds, abbreviated.")
    }

    // MARK: Match status

    /// Live minute: "HT", the clock ("67'"), else the status detail.
    func minute(_ match: Match) -> String {
        if match.isHalftime { return text("HT", comment: "Match status: half-time. Keep it very short.") }
        if !match.displayClock.isEmpty { return match.displayClock }
        return match.shortDetail.isEmpty
            ? text("LIVE", comment: "Match status: the match is being played. Keep it short; shown in capitals.")
            : match.shortDetail
    }

    /// Row status: live minute, "PPD", the final detail ("FT"), or the kickoff time.
    func statusText(_ match: Match) -> String {
        if match.isLive { return minute(match) }
        if match.isPostponed { return text("PPD", comment: "Match status: postponed. Keep it very short.") }
        if match.state == .post {
            return match.shortDetail.isEmpty
                ? text("FT", comment: "Match status: full time, the match is over. Keep it very short.")
                : match.shortDetail
        }
        return timeLabel(match.kickoff)
    }

    /// The locale's ordinal: "1st", "21st" in English, "1er" in French, "1." in German.
    func ordinal(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = locale
        return formatter.string(from: number as NSNumber) ?? "\(number)"
    }
}

nonisolated extension KeyEvent {
    /// "Mbappé 10' (P)", "Hugo Duro 30' (OG)", in the app language.
    /// - Parameter bundle: Defaults to the language bundle of `locale`'s app language.
    func label(locale: Locale = AppLocalization.shared.locale, bundle: Bundle? = nil) -> String {
        let bundle = bundle ?? locale.appBundle
        switch kind {
        case .penalty:
            return String(appLocalized: "\(player) \(minute) (P)", bundle: bundle, locale: locale,
                          comment: "A goal from the penalty spot: player, minute, then (P) for penalty.")
        case .ownGoal:
            return String(appLocalized: "\(player) \(minute) (OG)", bundle: bundle, locale: locale,
                          comment: "An own goal: player, minute, then (OG) for own goal.")
        case .goal, .redCard:
            return "\(player) \(minute)"
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
