//
//  PreviewData.swift
//  matchday
//
//  Sample fixtures for SwiftUI previews. The display values come from the
//  real derivations, so previews show what the app would.
//

#if DEBUG
import Foundation

nonisolated enum PreviewData {
    // MARK: Clock

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }()

    /// Wed Oct 21 2026, 17:07 in Madrid.
    static let now = date(day: 21, hour: 17, minute: 7)
    static let display = DisplayContext(now: now, calendar: calendar, locale: Locale(identifier: "en_US"))

    static func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    // MARK: Teams

    static let realMadrid = Team(id: "86", leagueID: "uefa.champions", name: "Real Madrid", shortName: "Real Madrid",
                                 abbreviation: "RMA", colorHex: "#d4af37")
    static let leipzig = Team(id: "11420", leagueID: "uefa.champions", name: "RB Leipzig", shortName: "RB Leipzig",
                              abbreviation: "RBL", colorHex: "#dd0741")
    static let atletico = Team(id: "1068", leagueID: "esp.1", name: "Atlético Madrid", shortName: "Atlético",
                               abbreviation: "ATM", colorHex: "#cb3524")
    static let deportivo = Team(id: "96", leagueID: "esp.1", name: "Deportivo La Coruña", shortName: "Deportivo",
                                abbreviation: "DEP", colorHex: "#0057a8")
    static let barcelona = Team(id: "83", leagueID: "esp.1", name: "Barcelona", shortName: "Barcelona",
                                abbreviation: "BAR", colorHex: "#1d4f91")
    static let getafe = Team(id: "2922", leagueID: "esp.1", name: "Getafe", shortName: "Getafe",
                             abbreviation: "GET", colorHex: "#005999")
    static let sevilla = Team(id: "243", leagueID: "esp.1", name: "Sevilla", shortName: "Sevilla",
                              abbreviation: "SEV", colorHex: "#d6001c")
    static let arsenal = Team(id: "359", leagueID: "eng.1", name: "Arsenal", shortName: "Arsenal",
                              abbreviation: "ARS", colorHex: "#e20520")
    static let chelsea = Team(id: "363", leagueID: "eng.1", name: "Chelsea", shortName: "Chelsea",
                              abbreviation: "CHE", colorHex: "#034694")

    static let favorites = [realMadrid, atletico, barcelona]
    static let followedIDs = Set(favorites.map(\.id))

    // MARK: Matches

    static let upcoming = match("1", home: realMadrid, away: leipzig, at: date(day: 21, hour: 21),
                                venue: "Santiago Bernabéu", city: "Madrid")
    static let live = match("2", home: barcelona, away: getafe, at: date(day: 21, hour: 16), state: .in,
                            score: (2, 1), clock: "67'", events: [
                                KeyEvent(kind: .goal, minute: "12'", player: "L. Yamal", teamID: barcelona.id, side: .home),
                                KeyEvent(kind: .goal, minute: "40'", player: "B. Mayoral", teamID: getafe.id, side: .away),
                                KeyEvent(kind: .redCard, minute: "55'", player: "D. Duarte", teamID: getafe.id, side: .away),
                                KeyEvent(kind: .penalty, minute: "63'", player: "R. Lewandowski", teamID: barcelona.id,
                                         side: .home),
                            ])
    static let liveElsewhere = match("3", home: arsenal, away: chelsea, at: date(day: 21, hour: 16, minute: 30),
                                     state: .in, score: (0, 0), clock: "41'")
    static let finished = match("4", home: sevilla, away: barcelona, at: date(day: 18, hour: 21), state: .post,
                                score: (2, 3), detail: "FT", winner: .away, events: [
                                    KeyEvent(kind: .goal, minute: "30'", player: "I. Romero", teamID: sevilla.id, side: .home),
                                    KeyEvent(kind: .goal, minute: "37'", player: "Raphinha", teamID: barcelona.id, side: .away),
                                ])
    static let atleticoNext = match("5", home: atletico, away: deportivo, at: date(day: 24, hour: 21),
                                    venue: "Riyadh Air Metropolitano", city: "Madrid", tv: ["DAZN"])
    static let atleticoAfter = match("6", home: getafe, away: atletico, at: date(day: 31, hour: 18))
    static let atleticoLast = match("7", home: atletico, away: sevilla, at: date(day: 17, hour: 18), state: .post,
                                    score: (1, 0), detail: "FT", winner: .home)
    static let realMadridLast = match("8", home: realMadrid, away: sevilla, at: date(day: 18, hour: 16), state: .post,
                                      score: (4, 1), detail: "FT", winner: .home)

    static let matches = [atleticoLast, finished, realMadridLast, live, liveElsewhere, upcoming, atleticoNext,
                          atleticoAfter].sorted { $0.kickoff < $1.kickoff }

    // MARK: Watch

    static let services = [
        Broadcaster(id: "movistar", name: "Movistar Plus+", url: URL(string: "https://www.movistarplus.es"),
                    colorHex: "#019df4", kind: .stream, language: "es"),
        Broadcaster(id: "dazn", name: "DAZN", url: URL(string: "https://www.dazn.com"),
                    colorHex: "#f8fc00", kind: .stream, language: nil),
        Broadcaster(id: "rtve", name: "La 1", url: URL(string: "https://www.rtve.es"),
                    colorHex: "#e5002b", kind: .free, language: nil),
    ]

    static func watch(_ match: Match) -> WatchOptions {
        WatchOptions(source: .rights, verified: true, services: Array(services.prefix(match.leagueID == "esp.1" ? 2 : 1)))
    }

    // MARK: Derived

    static let settings: AppSettings = {
        var settings = AppSettings()
        favorites.forEach { settings.toggleFollow(FavoriteTeam(team: $0)) }
        return settings
    }()

    static let snapshot = MatchSnapshot(
        matches: matches,
        teams: Dictionary(grouping: [realMadrid, leipzig, atletico, deportivo, barcelona, getafe, sevilla, arsenal, chelsea],
                          by: \.leagueID),
        liveLeagueIDs: ["esp.1", "eng.1"],
        status: .ok
    )

    static let cards = Derivations.followingCards(snapshot: snapshot, settings: settings, display: display,
                                                  watch: watch)
    static var realMadridCard: FollowingCard { cards.first { $0.favorite.teamID == realMadrid.id }! }
    static var liveCard: FollowingCard { cards.first { $0.live != nil }! }

    static let rows = matches.map {
        Derivations.row(for: $0, settings: settings, filter: .all, display: display, watch: watch)
    }
    static let liveElsewhereRows = Derivations.liveElsewhere(snapshot: snapshot, settings: settings, display: display)
        .map { Derivations.row(for: $0, settings: settings, filter: .all, display: display, watch: watch) }

    // MARK: Builders

    enum Winner { case home, away }

    static func match(
        _ id: String, home: Team, away: Team, at kickoff: Date, state: MatchState = .pre,
        score: (Int, Int)? = nil, detail: String = "", clock: String = "", winner: Winner? = nil,
        events: [KeyEvent] = [], venue: String = "", city: String = "", tv: [String] = []
    ) -> Match {
        func side(_ team: Team, _ goals: Int?, wins: Bool) -> MatchSide {
            MatchSide(team: team, score: goals.map(String.init), winner: wins, form: "", record: "")
        }
        return Match(
            id: id, leagueID: home.leagueID, kickoff: kickoff, state: state,
            statusName: state == .in ? "STATUS_SECOND_HALF" : state == .post ? "STATUS_FULL_TIME" : "STATUS_SCHEDULED",
            shortDetail: detail, displayClock: clock, completed: state == .post,
            home: side(home, score?.0, wins: winner == .home), away: side(away, score?.1, wins: winner == .away),
            keyEvents: events, tvNames: tv,
            espnURL: URL(string: "https://www.espn.com/soccer/match/_/gameId/\(id)")!,
            venue: venue, city: city, week: nil)
    }
}
#endif
