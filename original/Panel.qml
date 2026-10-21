import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Matchday panel. Polling, broadcaster lookup and notifications live in the
// daemon behind Service.qml; this widget renders its state.
Panel {
  id: root
  moduleName: "grivera.matchday"
  ipcTarget: "grivera.matchday"
  manageIpc: false

  // Panel commands plus status(), which voice assistants (Jarvis) and scripts
  // read: `omarchy-shell grivera.matchday status`.
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function status(): string { return JSON.stringify(root.statusSummary()) }
  }

  function statusTime(ts) { return ts ? Qt.formatDateTime(new Date(ts * 1000), "ddd MMM d, h:mm AP") : "" }

  // Favorites first (live, next, last, form, table), then today's and live games.
  function statusSummary() {
    var s = svc ? svc.state : null
    // Report loading until the teams' own fixtures are in, so an assistant asking
    // right after the plugin starts waits instead of answering from nothing.
    if (!s || !s.favorites || s.status === "loading" || s.status === "starting"
        || (s.favorites.length && s.favorites.every(function(f) { return !f.next && !f.last && !f.live })))
      return { error: "Matchday is still loading" }
    var leagueName = {}
    ;(s.leagues || []).forEach(function(l) { leagueName[l.id] = l.name })
    function match(e) {
      if (!e) return null
      var o = { league: leagueName[e.league] || e.league, home: e.home.name, away: e.away.name,
                state: e.state === "pre" ? "scheduled" : e.state === "in" ? "live" : "finished",
                kickoff: root.statusTime(e.ts) }
      if (e.state !== "pre") o.score = e.home.name + " " + e.home.score + ", " + e.away.name + " " + e.away.score
      if (e.state === "in") o.clock = e.clock
      if (e.state === "post") o.result = e.detail
      if (e.venue) o.venue = e.venue + (e.city ? ", " + e.city : "")
      var goals = (e.plays || []).filter(function(p) { return p.goal }).map(function(p) {
        return p.player + " " + p.minute + (p.og ? " (own goal)" : "") + (p.pen ? " (penalty)" : "")
      })
      if (goals.length) o.goals = goals
      var reds = (e.plays || []).filter(function(p) { return p.red }).map(function(p) { return p.player + " " + p.minute })
      if (reds.length) o.redCards = reds
      var tv = ((e.watch || {}).services || []).map(function(w) { return w.name })
      if (tv.length) o.whereToWatch = tv
      return o
    }
    var now = Date.now() / 1000
    var today = new Date(); today.setHours(0, 0, 0, 0)
    var start = today.getTime() / 1000, end = start + 86400
    return {
      now: root.statusTime(now),
      favorites: s.favorites.map(function(f) {
        var o = { team: f.team.name, league: leagueName[f.league] || f.league }
        if (f.live) o.liveNow = match(f.live)
        if (f.next) o.nextMatch = match(f.next)
        if (f.after) o.matchAfterThat = match(f.after)
        if (f.last) o.lastMatch = match(f.last)
        if (f.form && f.form.length) o.recentForm = f.form.map(function(r) { return r.r + " " + r.score + (r.home ? " vs " : " at ") + r.vs })
        if (f.standing) o.table = { position: f.standing.rank, played: f.standing.played, won: f.standing.w, drawn: f.standing.d,
                                    lost: f.standing.l, goalDifference: f.standing.gd, points: f.standing.pts,
                                    zone: f.standing.note ? f.standing.note.text : "" }
        return o
      }),
      liveNow: (s.events || []).filter(function(e) { return e.state === "in" }).map(match),
      today: (s.events || []).filter(function(e) { return e.ts >= start && e.ts < end && e.state !== "in" }).slice(0, 20).map(match),
      leagues: (s.leagues || []).filter(function(l) { return l.enabled }).map(function(l) { return l.name }),
      // Full standings of the followed leagues, one compact line per team:
      // "rank team played won-drawn-lost goal-difference points".
      standings: (s.leagues || []).filter(function(l) { return l.enabled && (s.tables || {})[l.id] }).map(function(l) {
        return { league: l.name, groups: s.tables[l.id].map(function(g) {
          return { group: g.name || "", rows: (g.rows || []).map(function(r) {
            return r.rank + " " + r.name + " " + r.played + "P " + r.w + "-" + r.d + "-" + r.l + " " + r.gd + " " + r.pts + "pts"
          }) }
        }) }
      })
    }
  }


  readonly property var svc: root.bar && root.bar.shell ? root.bar.shell.serviceFor("grivera.matchday") : null
  readonly property var st: svc ? svc.state : ({})
  readonly property var config: svc ? svc.config : ({})
  readonly property var favorites: svc ? svc.favorites : []
  readonly property var events: svc ? svc.events : []
  readonly property var leagues: svc ? svc.leagues : []

  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.10)
  readonly property color urgent: root.bar ? root.bar.urgent : Color.urgent
  readonly property color win: "#3fb950"
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property bool lightSurface: luminance(Color.popups.background) >= 0.5

  readonly property string ball: String.fromCodePoint(0xF04B8)
  readonly property string pitch: String.fromCodePoint(0xF0834)
  readonly property string tv: String.fromCodePoint(0xF0502)
  readonly property string pin: String.fromCodePoint(0xF034E)
  readonly property string star: String.fromCodePoint(0xF04CE)

  property string tab: "following"
  property string matchFilter: "all"
  property string tableLeague: favorites.length ? favorites[0].league : "esp.1"
  property string teamsLeague: "esp.1"

  // Favorites' live matches drive the bar text and the pulse.
  readonly property var liveFavs: favorites.filter(function(f) { return !!f.live })
  readonly property bool anyLive: liveFavs.length > 0
  readonly property var todayFav: {
    var now = nowMs / 1000
    var best = null
    favorites.forEach(function(f) {
      if (f.next && f.next.ts - now < 12 * 3600 && (!best || f.next.ts < best.ts)) best = f.next
    })
    return best
  }

  property double nowMs: Date.now()
  Timer {
    interval: root.opened ? 1000 : 30000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  property real pulse: 1
  SequentialAnimation on pulse {
    running: root.anyLive || (root.opened && root.st.liveCount > 0)
    loops: Animation.Infinite
    alwaysRunToEnd: true
    NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
  }

  implicitWidth: liveButton.visible ? liveButton.implicitWidth : button.implicitWidth
  implicitHeight: liveButton.visible ? liveButton.implicitHeight : button.implicitHeight

  // ---- helpers ----

  function luminance(c) {
    function ch(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
  }

  function league(id) {
    for (var i = 0; i < leagues.length; i++) if (leagues[i].id === id) return leagues[i]
    return { id: id, name: id, short: id, color: Color.accent }
  }

  function logo(item) {
    if (!item || !svc || !svc.logoDir) return ""
    var name = root.lightSurface ? item.logo : (item.logoDark || item.logo)
    return name ? "file://" + svc.logoDir + "/" + name : ""
  }

  // A team colour that still reads on the panel; ESPN often says white or black.
  function teamColor(t) {
    return t && t.color ? readable(t.color, Color.accent) : Color.accent
  }

  function readable(color, fallback) {
    if (!color) return fallback
    var c = Qt.color(color)
    return Math.abs(luminance(c) - luminance(Color.popups.background)) < 0.12 ? fallback : c
  }

  function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
  }

  function dayLabel(ts) {
    var d = new Date(ts * 1000), now = new Date(nowMs)
    var tom = new Date(nowMs + 86400000), yest = new Date(nowMs - 86400000)
    if (sameDay(d, now)) return "Today"
    if (sameDay(d, tom)) return "Tomorrow"
    if (sameDay(d, yest)) return "Yesterday"
    return Qt.formatDate(d, "ddd MMM d")
  }

  function timeLabel(ts) {
    return new Date(ts * 1000).toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
  }

  function countdown(ts) {
    var s = Math.floor(ts - nowMs / 1000)
    if (s <= 0) return "kicking off"
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
    if (d > 0) return "in " + d + "d " + h + "h"
    if (h > 0) return "in " + h + "h " + ("0" + m).slice(-2) + "m"
    if (m > 0) return "in " + m + "m"
    return "in " + s + "s"
  }

  function minute(ev) {
    if (!ev) return ""
    if (ev.status === "STATUS_HALFTIME") return "HT"
    return ev.clock || ev.detail || "LIVE"
  }

  function statusText(ev) {
    if (ev.state === "in") return minute(ev)
    if (ev.state === "post") return ev.detail || "FT"
    if (ev.status === "STATUS_POSTPONED") return "PPD"
    return timeLabel(ev.ts)
  }

  function ordinal(n) {
    n = Number(n)
    var s = ["th", "st", "nd", "rd"], v = n % 100
    return n + (s[(v - 20) % 10] || s[v] || s[0])
  }

  function opponent(ev, teamId) { return ev.home.id === teamId ? ev.away : ev.home }

  function summary() {
    if (!svc) return "SERVICE NOT LOADED"
    if (svc.lastError) return svc.lastError.toUpperCase()
    if (!svc.running) return "BACKEND STOPPED"
    if (st.status === "starting" || st.status === "loading") return "LOADING FIXTURES…"
    if (st.status === "offline") return "OFFLINE · " + (st.error || "can't reach ESPN").toUpperCase()
    var bits = []
    if (anyLive) bits.push(liveFavs.length + " LIVE")
    else if (st.liveCount) bits.push(st.liveCount + " LIVE NOW")
    var next = null
    favorites.forEach(function(f) { if (f.next && (!next || f.next.ts < next.ts)) next = f.next })
    if (next) bits.push("NEXT " + next.home.abbr + " v " + next.away.abbr + " · " + dayLabel(next.ts).toUpperCase() + " " + timeLabel(next.ts))
    if (!bits.length) bits.push(events.length + " MATCHES THIS WEEK")
    if (st.status === "stale") bits.push("STALE")
    return bits.join("  ·  ")
  }

  function barLiveText() {
    if (!anyLive) return ""
    var ev = liveFavs[0].live
    return ev.home.abbr + " " + (ev.home.score || 0) + "–" + (ev.away.score || 0) + " " + ev.away.abbr + "  " + minute(ev)
  }

  function tooltip() {
    var lines = []
    favorites.forEach(function(f) {
      var ev = f.live || f.next
      if (!ev) return
      if (f.live) lines.push("● " + ev.home.short + " " + ev.home.score + "–" + ev.away.score + " " + ev.away.short + "  " + minute(ev))
      else {
        var w = (ev.watch && ev.watch.services || []).slice(0, 2).map(function(s) { return s.name }).join(", ")
        lines.push(ev.home.short + " v " + ev.away.short + " — " + dayLabel(ev.ts) + " " + timeLabel(ev.ts) + (w ? "  ·  " + w : ""))
      }
    })
    return lines.length ? lines.join("\n") : "Matchday — follow some teams"
  }

  function filteredEvents() {
    var f = matchFilter
    return events.filter(function(e) {
      return f === "all" || (f === "mine" ? e.fav : e.league === f)
    })
  }

  // [{ label, live, past, items }] — today and later first, then results newest first.
  function daySections() {
    var groups = [], byKey = {}
    var today = new Date(nowMs); today.setHours(0, 0, 0, 0)
    filteredEvents().forEach(function(e) {
      var d = new Date(e.ts * 1000); d.setHours(0, 0, 0, 0)
      var key = d.getTime()
      if (!byKey[key]) { byKey[key] = { key: key, ts: e.ts, past: key < today.getTime(), items: [] }; groups.push(byKey[key]) }
      byKey[key].items.push(e)
    })
    var upcoming = groups.filter(function(g) { return !g.past }).sort(function(a, b) { return a.key - b.key })
    var past = groups.filter(function(g) { return g.past }).sort(function(a, b) { return b.key - a.key })
    return upcoming.concat(past).map(function(g, i) {
      var live = g.items.filter(function(e) { return e.state === "in" }).length
      return {
        label: (dayLabel(g.ts) + (dayLabel(g.ts).indexOf(" ") < 0 ? " · " + Qt.formatDate(new Date(g.ts * 1000), "ddd MMM d") : "")).toUpperCase(),
        live: live, past: g.past, firstPast: g.past && (i === upcoming.length), items: g.items
      }
    })
  }

  readonly property var tabs: [
    { value: "following", label: "Following" },
    { value: "matches", label: "Matches" },
    { value: "tables", label: "Tables" },
    { value: "teams", label: "Teams" }
  ]
  readonly property var leagueOptions: leagues.map(function(l) { return { value: l.id, label: l.short } })
  readonly property var matchOptions: [{ value: "all", label: "All" }, { value: "mine", label: "★ Mine" }].concat(leagueOptions)

  function cycle(options, value, dx) {
    var i = 0
    for (var k = 0; k < options.length; k++) if (options[k].value === value) i = k
    return options[(i + dx + options.length) % options.length].value
  }

  function moveFilter(dx) {
    if (tab === "matches") matchFilter = cycle(matchOptions, matchFilter, dx)
    else if (tab === "tables") tableLeague = cycle(leagueOptions, tableLeague, dx)
    else if (tab === "teams") teamsLeague = cycle(leagueOptions, teamsLeague, dx)
  }

  function openMatch(ev) { if (svc && ev) svc.openUrl(ev.url) }

  // ---- bar ----

  BarIconButton {
    id: button
    anchors.fill: parent
    visible: !liveButton.visible
    bar: root.bar
    text: root.ball
    active: root.anyLive
    opacity: root.favorites.length ? 1 : 0.6
    tooltipText: root.tooltip()
    onPressed: function(b) {
      if (b === Qt.MiddleButton && root.svc) root.svc.send("refresh")
      else root.toggle()
    }
  }

  WidgetButton {
    id: liveButton
    anchors.fill: parent
    visible: root.anyLive && root.config.barScore !== false && !(root.bar && root.bar.vertical)
    bar: root.bar
    text: root.ball + "  " + root.barLiveText()
    tooltipText: root.tooltip()
    onPressed: function(b) {
      if (b === Qt.RightButton) root.openMatch(root.liveFavs[0].live)
      else if (b === Qt.MiddleButton && root.svc) root.svc.send("refresh")
      else root.toggle()
    }
  }

  // Matchday dot: accent when one of your teams plays within 12 h, red and
  // breathing while one is live.
  Rectangle {
    visible: !liveButton.visible && (root.anyLive || !!root.todayFav)
    z: 2
    width: Math.max(5, Math.round(Style.bar.iconFont * 0.42))
    height: width
    radius: width / 2
    color: root.anyLive ? root.urgent : Color.accent
    opacity: root.anyLive ? root.pulse : 1
    anchors.right: button.right
    anchors.top: button.top
    anchors.rightMargin: Math.max(0, (button.width - Style.bar.iconCanvas) / 2 - width / 3)
    anchors.topMargin: Math.max(1, (button.height - Style.bar.iconCanvas) / 2)
  }

  // ---- panel ----

  KeyboardPanel {
    id: panel
    anchorItem: liveButton.visible ? liveButton : button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(470))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(780))

    onOpenChanged: if (open && root.svc) root.svc.send("refresh")

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx) root.moveFilter(dx)
        if (dy) flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy * Style.space(80)))
      }
      onTextKey: function(t) {
        if (/^[1-4]$/.test(t)) { root.tab = root.tabs[Number(t) - 1].value; flick.contentY = 0 }
        else if (t === "r" && root.svc) root.svc.send("refresh")
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: flick.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff; width: Style.space(4) }

        Column {
          id: column
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Matchday"
            meta: root.summary()
            detail: root.st.countryName ? root.pin + "  Watching from " + (root.config.country === "auto" && root.st.city ? root.st.city + ", " : "") + root.st.countryName : ""
            foreground: root.fg
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: root.ball
                color: root.anyLive ? root.urgent : Color.accent
                opacity: root.anyLive ? 0.55 + 0.45 * root.pulse : 1
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          ButtonGroup {
            options: root.tabs
            value: root.tab
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            focusable: false
            onChanged: function(v) { root.tab = v; flick.contentY = 0 }
          }

          Loader {
            width: parent.width
            sourceComponent: root.tab === "following" ? followingTab
              : root.tab === "matches" ? matchesTab
              : root.tab === "tables" ? tablesTab : teamsTab
          }

          Item { width: parent.width; height: Style.space(2) }
        }
      }
    }
  }

  // ================================================================ tabs

  Component {
    id: followingTab
    Column {
      width: parent ? parent.width : 0
      spacing: Style.space(10)

      // Empty state
      Rectangle {
        visible: root.favorites.length === 0
        width: parent.width
        height: emptyCol.implicitHeight + Style.space(36)
        radius: Style.cornerRadius
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
        border.width: 1
        border.color: root.faint

        Column {
          id: emptyCol
          anchors.centerIn: parent
          width: parent.width - Style.space(40)
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.pitch
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge * 1.4
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Follow your teams"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "Pick the clubs and national teams you care about. Matchday tracks their games, tells you which channel has them where you are, and nudges you before kickoff."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Choose teams"
            iconText: root.star
            bordered: true
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.tab = "teams"
          }
        }
      }

      Repeater {
        model: root.favorites
        FavoriteCard {
          required property var modelData
          width: parent.width
          fav: modelData
        }
      }

      // Live elsewhere: other games in progress right now.
      Column {
        readonly property var others: root.events.filter(function(e) { return e.state === "in" && !e.fav })
        visible: others.length > 0 && root.favorites.length > 0
        width: parent.width
        spacing: Style.space(4)

        PanelSectionHeader {
          text: "LIVE ELSEWHERE"
          foreground: root.urgent
          fontFamily: root.fontFamily
        }
        Repeater {
          model: parent.others
          MatchRow { required property var modelData; width: parent.width; ev: modelData }
        }
      }
    }
  }

  Component {
    id: matchesTab
    Column {
      width: parent ? parent.width : 0
      spacing: Style.space(8)

      ButtonGroup {
        options: root.matchOptions
        value: root.matchFilter
        foreground: root.fg
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        focusable: false
        onChanged: function(v) { root.matchFilter = v }
      }

      Text {
        textFormat: Text.PlainText
        readonly property var sections: root.daySections()
        visible: sections.length === 0
        width: parent.width
        topPadding: Style.space(16)
        bottomPadding: Style.space(16)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.matchFilter === "mine" && !root.favorites.length ? "You're not following anyone yet — pick teams in the Teams tab."
          : root.st.status === "loading" || root.st.status === "starting" ? "Loading fixtures…"
          : "No matches in the next " + 10 + " days. International break?"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Repeater {
        model: root.daySections()
        Column {
          required property var modelData
          width: parent.width
          spacing: Style.space(2)

          Item {
            visible: modelData.firstPast
            width: parent.width
            height: Style.space(10)
          }
          Row {
            visible: modelData.firstPast
            spacing: Style.space(8)
            Text {
              textFormat: Text.PlainText
              text: "RESULTS"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.5
            }
          }

          Item {
            width: parent.width
            height: dayHeader.implicitHeight + Style.space(6)
            Text {
              id: dayHeader
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(2)
              text: modelData.label
              color: modelData.past ? root.dim : root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1
            }
            Text {
              textFormat: Text.PlainText
              visible: modelData.live > 0
              anchors.right: parent.right
              anchors.baseline: dayHeader.baseline
              text: "● " + modelData.live + " LIVE"
              color: root.urgent
              opacity: 0.5 + 0.5 * root.pulse
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 1
              color: root.faint
            }
          }

          Repeater {
            model: modelData.items
            MatchRow { required property var modelData; width: parent.width; ev: modelData; showLeague: root.matchFilter === "all" || root.matchFilter === "mine" }
          }
        }
      }

      WatchFootnote { width: parent.width }
    }
  }

  Component {
    id: tablesTab
    Column {
      id: tableCol
      width: parent ? parent.width : 0
      spacing: Style.space(6)
      readonly property var groups: (root.svc && root.svc.tables[root.tableLeague]) || []
      readonly property real numW: Style.space(26)

      ButtonGroup {
        options: root.leagueOptions
        value: root.tableLeague
        foreground: root.fg
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        focusable: false
        onChanged: function(v) { root.tableLeague = v }
      }

      Text {
        textFormat: Text.PlainText
        visible: tableCol.groups.length === 0
        width: parent.width
        topPadding: Style.space(16)
        horizontalAlignment: Text.AlignHCenter
        text: "Loading table…"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Repeater {
        model: tableCol.groups
        Column {
          required property var modelData
          width: tableCol.width
          spacing: 0

          PanelSectionHeader {
            visible: modelData.name !== ""
            text: modelData.name.toUpperCase()
            foreground: root.fg
            fontFamily: root.fontFamily
            bottomPadding: Style.space(4)
            topPadding: Style.space(6)
          }

          // Header
          Item {
            width: parent.width
            height: Style.space(20)
            Text { textFormat: Text.PlainText; x: Style.space(8); anchors.verticalCenter: parent.verticalCenter; text: "#"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Text { textFormat: Text.PlainText; x: Style.space(56); anchors.verticalCenter: parent.verticalCenter; text: root.league(root.tableLeague).national ? "TEAM" : "CLUB"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.letterSpacing: 1 }
            Row {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              Repeater {
                model: ["P", "W", "D", "L", "GD", "PTS"]
                Text {
                  required property var modelData
                  textFormat: Text.PlainText
                  width: modelData === "PTS" ? tableCol.numW + Style.space(6) : tableCol.numW
                  horizontalAlignment: Text.AlignRight
                  text: modelData
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          Repeater {
            model: modelData.rows
            Item {
              id: trow
              required property var modelData
              required property int index
              width: tableCol.width
              height: Style.space(26)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: trow.modelData.fav ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
                  : trow.index % 2 ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03) : "transparent"
              }
              Rectangle {
                visible: !!(trow.modelData.note && trow.modelData.note.color)
                x: 0
                width: Style.space(3)
                height: parent.height - Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                radius: width / 2
                color: trow.modelData.note ? root.readable(trow.modelData.note.color, root.dim) : "transparent"
              }
              Text {
                textFormat: Text.PlainText
                x: Style.space(8)
                width: Style.space(18)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: trow.modelData.rank
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Crest {
                id: tcrest
                x: Style.space(32)
                anchors.verticalCenter: parent.verticalCenter
                team: trow.modelData
                size: Style.space(18)
              }
              Text {
                textFormat: Text.PlainText
                anchors.left: tcrest.right
                anchors.leftMargin: Style.space(8)
                anchors.right: nums.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: trow.modelData.short + (trow.modelData.fav ? "  ★" : "")
                color: root.fg
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: trow.modelData.fav
              }
              Row {
                id: nums
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                  model: [trow.modelData.played, trow.modelData.w, trow.modelData.d, trow.modelData.l, trow.modelData.gd, trow.modelData.pts]
                  Text {
                    required property var modelData
                    required property int index
                    textFormat: Text.PlainText
                    width: index === 5 ? tableCol.numW + Style.space(6) : tableCol.numW
                    horizontalAlignment: Text.AlignRight
                    text: modelData
                    color: index === 5 ? root.fg : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: index === 5 ? Style.font.body : Style.font.bodySmall
                    font.bold: index === 5
                  }
                }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.svc) root.svc.follow(root.tableLeague, trow.modelData.id, !trow.modelData.fav)
              }
            }
          }
        }
      }

      // Zone legend
      Flow {
        readonly property var zones: {
          var seen = {}, out = []
          tableCol.groups.forEach(function(g) { g.rows.forEach(function(r) {
            if (r.note && r.note.text && !seen[r.note.text]) { seen[r.note.text] = 1; out.push(r.note) }
          }) })
          return out
        }
        visible: zones.length > 0
        width: parent.width
        topPadding: Style.space(6)
        spacing: Style.space(12)
        Repeater {
          model: parent.zones
          Row {
            required property var modelData
            spacing: Style.space(5)
            Rectangle { width: Style.space(8); height: width; radius: width / 2; color: root.readable(modelData.color, root.dim); anchors.verticalCenter: parent.verticalCenter }
            Text { textFormat: Text.PlainText; text: modelData.text; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        topPadding: Style.space(2)
        text: "Click a " + (root.league(root.tableLeague).national ? "team" : "club") + " to follow or unfollow it."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.italic: true
      }
    }
  }

  Component {
    id: teamsTab
    Column {
      id: teamsCol
      width: parent ? parent.width : 0
      spacing: Style.space(10)
      readonly property var teams: (root.svc && root.svc.teams[root.teamsLeague]) || []
      readonly property int cols: 4
      readonly property real tileW: (width - (cols - 1) * Style.space(6)) / cols

      ButtonGroup {
        options: root.leagueOptions
        value: root.teamsLeague
        foreground: root.fg
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        focusable: false
        onChanged: function(v) { root.teamsLeague = v }
      }

      Text {
        textFormat: Text.PlainText
        visible: teamsCol.teams.length === 0
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.league(root.teamsLeague).national ? "Loading teams…" : "Loading clubs…"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Grid {
        columns: teamsCol.cols
        spacing: Style.space(6)

        Repeater {
          model: teamsCol.teams
          Item {
            id: tile
            required property var modelData
            readonly property bool on: modelData.fav
            width: teamsCol.tileW
            height: Style.space(74)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: tile.on ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
                : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, tileMouse.containsMouse ? 0.08 : 0.03)
              border.width: tile.on ? 2 : 1
              border.color: tile.on ? Color.accent : root.faint
              Behavior on color { ColorAnimation { duration: 120 } }
            }

            Crest {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: Style.space(10)
              team: tile.modelData
              size: Style.space(32)
              scale: tileMouse.containsMouse ? 1.08 : 1
              Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }

            Text {
              textFormat: Text.PlainText
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(8)
              anchors.horizontalCenter: parent.horizontalCenter
              width: parent.width - Style.space(8)
              horizontalAlignment: Text.AlignHCenter
              text: tile.modelData.short
              elide: Text.ElideRight
              color: tile.on ? root.fg : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: tile.on
            }

            Text {
              textFormat: Text.PlainText
              visible: tile.on
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: Style.space(5)
              text: "★"
              color: Color.accent
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: tileMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.svc) root.svc.follow(root.teamsLeague, tile.modelData.id, !tile.on)
            }
          }
        }
      }

      // ---------- Settings ----------
      PanelSeparator { foreground: root.fg }
      PanelSectionHeader { text: "SETTINGS"; foreground: root.fg; fontFamily: root.fontFamily }

      Dropdown {
        width: parent.width
        label: "Watching from"
        value: root.config.country || "auto"
        options: root.st.countries || []
        foreground: root.fg
        fontFamily: root.fontFamily
        onChanged: function(v) { if (root.svc) root.svc.setConfig("country", v) }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.st.countryKnown === false
        width: parent.width
        wrapMode: Text.WordWrap
        text: "No rights data for " + root.st.countryName + " yet — MLS falls back to Apple TV. Add your broadcasters in ~/.config/grivera-matchday/broadcasters.json."
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      SettingToggle { key: "spanish"; label: "Spanish-language channels"; description: "Telemundo, Universo, ESPN Deportes, FOX Deportes and friends." }
      SettingToggle { key: "notifyKickoff"; label: "Kickoff reminders"; description: (root.config.kickoffLead || 15) + " minutes before your teams play, with where to watch." }
      SettingToggle { key: "notifyGoals"; label: "Goal alerts"; description: "Every goal in your teams' matches, with the scorer." }
      SettingToggle { key: "notifyFinal"; label: "Full-time results" }
      SettingToggle { key: "barScore"; label: "Live score in the bar"; description: "Shows the score next to the ball while one of your teams is playing." }

      Row {
        spacing: Style.space(8)
        Button {
          text: "Test notification"
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          bordered: true
          onClicked: if (root.svc) root.svc.send("test")
        }
        Button {
          text: "Refresh"
          tooltipText: "Refetch everything now (r)"
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          bordered: true
          onClicked: if (root.svc) root.svc.send("refresh")
        }
      }
    }
  }

  // ================================================================ pieces

  component SettingToggle: Toggle {
    property string key: ""
    width: parent ? parent.width : 0
    foreground: root.fg
    fontFamily: root.fontFamily
    checked: root.config[key] !== false
    onClicked: if (root.svc) root.svc.setConfig(key, !checked)
  }

  // Team crest from the daemon's cache, or a coloured monogram until it lands.
  component Crest: Item {
    id: crest
    property var team: ({})
    property real size: Style.space(20)
    width: size
    height: size

    Image {
      id: crestImg
      anchors.fill: parent
      source: root.logo(crest.team)
      sourceSize.width: Math.ceil(crest.size * 2)
      sourceSize.height: Math.ceil(crest.size * 2)
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
      asynchronous: true
      visible: status === Image.Ready
    }
    Rectangle {
      visible: crestImg.status !== Image.Ready
      anchors.fill: parent
      radius: width / 2
      color: root.teamColor(crest.team)
      opacity: 0.85
      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: (crest.team.abbr || crest.team.short || "?").slice(0, 3)
        color: Color.popups.background
        font.family: root.fontFamily
        font.pixelSize: Math.max(6, crest.size * 0.32)
        font.bold: true
      }
    }
  }

  component LeagueTag: Row {
    property string leagueId: ""
    readonly property var lg: root.league(leagueId)
    spacing: Style.space(4)
    Rectangle {
      width: Style.space(6); height: width; radius: width / 2
      color: parent.lg.color
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      textFormat: Text.PlainText
      text: parent.lg.short
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component FormDots: Row {
    property var form: []
    spacing: Style.space(3)
    Repeater {
      model: parent.form
      Rectangle {
        required property var modelData
        width: Style.space(16)
        height: Style.space(16)
        radius: Style.space(4)
        color: modelData.r === "W" ? root.win : modelData.r === "L" ? root.urgent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: modelData.r
          color: modelData.r === "D" ? root.fg : "#ffffff"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption * 0.9
          font.bold: true
        }
        HoverHandler { id: dotHover }
        PanelToolTip {
          visible: dotHover.hovered
          text: (modelData.home ? "vs " : "at ") + modelData.vs + "  " + modelData.score
          delay: 300
        }
      }
    }
  }

  // Broadcaster pills. Click one to open the service.
  component WatchChips: Flow {
    id: chips
    property var watch: ({ services: [] })
    property bool compact: false
    spacing: Style.space(compact ? 4 : 6)

    Repeater {
      model: (chips.watch && chips.watch.services) || []
      Rectangle {
        id: chip
        required property var modelData
        readonly property bool hot: chipMouse.containsMouse
        height: chipRow.implicitHeight + Style.space(chips.compact ? 4 : 8)
        width: chipRow.implicitWidth + Style.space(chips.compact ? 12 : 18)
        radius: height / 2
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, hot ? 0.14 : 0.06)
        border.width: 1
        border.color: hot ? (modelData.color || Color.accent) : root.faint
        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
          id: chipRow
          anchors.centerIn: parent
          spacing: Style.space(5)
          Rectangle {
            width: Style.space(chips.compact ? 5 : 7); height: width; radius: width / 2
            color: chip.modelData.color || Color.accent
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            textFormat: Text.PlainText
            text: chip.modelData.name
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: chips.compact ? Style.font.caption : Style.font.bodySmall
            font.bold: !chips.compact
          }
          Text {
            textFormat: Text.PlainText
            visible: !!chip.modelData.lang && !chips.compact
            text: (chip.modelData.lang || "").toUpperCase()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption * 0.85
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            textFormat: Text.PlainText
            visible: chip.modelData.kind === "free" && !chips.compact
            text: "FREE"
            color: root.win
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption * 0.85
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
        }
        MouseArea {
          id: chipMouse
          anchors.fill: parent
          hoverEnabled: true
          enabled: !!chip.modelData.url
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root.svc) root.svc.openUrl(chip.modelData.url)
        }
      }
    }
  }

  component WatchFootnote: Text {
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    topPadding: Style.space(6)
    text: root.st.country === "US"
      ? "Channels marked per match come from ESPN's US listings; the rest show the " + (root.st.season || "") + " league rights holders until the channel is posted."
      : "Where to watch shows " + (root.st.season || "") + " rights holders for " + (root.st.countryName || "your country") + "."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.italic: true
  }

  // home  [crest] score/vs [crest]  away, centred on the middle column.
  component Matchup: Item {
    id: mu
    property var ev: ({ home: {}, away: {} })
    property bool big: false
    readonly property bool showScore: ev.state === "in" || ev.state === "post"
    readonly property real crestSize: big ? Style.space(30) : Style.space(18)
    implicitHeight: Math.max(crestSize, centerText.implicitHeight) + (big ? Style.space(4) : 0)

    Text {
      id: centerText
      anchors.centerIn: parent
      width: mu.big ? Style.space(84) : Style.space(46)
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: mu.showScore ? (mu.ev.home.score || 0) + (mu.big ? " – " : "–") + (mu.ev.away.score || 0) : "vs"
      color: mu.ev.state === "in" ? root.urgent : mu.showScore ? root.fg : root.dim
      font.family: root.fontFamily
      font.pixelSize: mu.big ? (mu.showScore ? Style.font.displayLarge : Style.font.title) : (mu.showScore ? Style.font.title : Style.font.caption)
      font.bold: mu.showScore
    }

    Crest {
      id: homeCrest
      anchors.right: centerText.left
      anchors.rightMargin: Style.space(mu.big ? 8 : 6)
      anchors.verticalCenter: parent.verticalCenter
      team: mu.ev.home
      size: mu.crestSize
    }
    Text {
      anchors.right: homeCrest.left
      anchors.rightMargin: Style.space(mu.big ? 10 : 6)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: mu.ev.home.short || ""
      elide: Text.ElideRight
      color: mu.ev.state === "post" && mu.ev.away.winner ? root.dim : root.fg
      font.family: root.fontFamily
      font.pixelSize: mu.big ? Style.font.title : Style.font.body
      font.bold: mu.big || mu.ev.home.winner || (mu.ev.fav && mu.ev.favSide === "home")
    }

    Crest {
      id: awayCrest
      anchors.left: centerText.right
      anchors.leftMargin: Style.space(mu.big ? 8 : 6)
      anchors.verticalCenter: parent.verticalCenter
      team: mu.ev.away
      size: mu.crestSize
    }
    Text {
      anchors.left: awayCrest.right
      anchors.leftMargin: Style.space(mu.big ? 10 : 6)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: mu.ev.away.short || ""
      elide: Text.ElideRight
      color: mu.ev.state === "post" && mu.ev.home.winner ? root.dim : root.fg
      font.family: root.fontFamily
      font.pixelSize: mu.big ? Style.font.title : Style.font.body
      font.bold: mu.big || mu.ev.away.winner || (mu.ev.fav && mu.ev.favSide === "away")
    }
  }

  component MatchRow: Item {
    id: mrow
    property var ev: ({ home: {}, away: {}, watch: { services: [] } })
    property bool showLeague: true
    readonly property bool live: ev.state === "in"
    implicitHeight: rowCol.implicitHeight + Style.space(10)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: mrow.ev.fav ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, rowMouse.containsMouse ? 0.20 : 0.11)
        : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, rowMouse.containsMouse ? 0.07 : 0)
      Behavior on color { ColorAnimation { duration: 120 } }
    }
    Rectangle {
      visible: mrow.ev.fav
      width: Style.space(3)
      height: parent.height - Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      radius: width / 2
      color: Color.accent
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openMatch(mrow.ev)
    }

    Column {
      id: rowCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Item {
        width: parent.width
        implicitHeight: mu.implicitHeight

        Text {
          id: timeText
          width: Style.space(62)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: (mrow.live ? "● " : "") + root.statusText(mrow.ev)
          color: mrow.live ? root.urgent : mrow.ev.state === "post" ? root.dim : root.fg
          opacity: mrow.live ? 0.6 + 0.4 * root.pulse : 1
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: mrow.live
        }

        Matchup {
          id: mu
          anchors.left: timeText.right
          anchors.right: lgDot.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          ev: mrow.ev
        }

        Rectangle {
          id: lgDot
          width: mrow.showLeague ? Style.space(7) : 0
          height: width
          radius: width / 2
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          color: root.league(mrow.ev.league).color
          HoverHandler { id: lgHover }
          PanelToolTip {
            visible: lgHover.hovered && mrow.showLeague
            text: root.league(mrow.ev.league).name
          }
        }
      }

      // Scorers while live/finished for your matches; channels before kickoff.
      Text {
        visible: text !== ""
        width: parent.width
        leftPadding: timeText.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: {
          if (mrow.ev.state === "pre") {
            var s = (mrow.ev.watch && mrow.ev.watch.services || []).slice(0, 3).map(function(x) { return x.name })
            return s.length ? root.tv + "  " + s.join(" · ") : ""
          }
          if (!mrow.ev.fav && !mrow.live) return ""
          return (mrow.ev.plays || []).filter(function(p) { return p.goal }).map(function(p) {
            return p.player + " " + p.minute + (p.pen ? " (P)" : "") + (p.og ? " (OG)" : "")
          }).join(" · ")
        }
        color: root.dim
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  component FavoriteCard: Item {
    id: card
    property var fav: ({ team: {}, form: [] })
    readonly property var ev: fav.live || fav.next
    readonly property bool live: !!fav.live
    readonly property color tint: root.teamColor(fav.team)
    implicitHeight: cardCol.implicitHeight + Style.space(28)

    Rectangle {
      id: cardBg
      anchors.fill: parent
      radius: Math.max(Style.cornerRadius, Style.space(4))
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.035)
      border.width: 1
      border.color: card.live ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.4 + 0.4 * root.pulse) : root.faint
      clip: true

      // Team-colour wash across the top of the card.
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Style.space(64)
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0.20) }
          GradientStop { position: 1; color: Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0) }
        }
      }
      Rectangle {
        width: Style.space(3)
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: card.tint
      }
    }

    Column {
      id: cardCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(14)
      spacing: Style.space(10)

      // Header: crest, name, league position, form.
      Item {
        width: parent.width
        implicitHeight: Math.max(bigCrest.height, headCol.implicitHeight)

        Crest {
          id: bigCrest
          team: card.fav.team
          size: Style.space(38)
          anchors.verticalCenter: parent.verticalCenter
        }
        Column {
          id: headCol
          anchors.left: bigCrest.right
          anchors.leftMargin: Style.space(10)
          anchors.right: formDots.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: card.fav.team.name || ""
            elide: Text.ElideRight
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }
          Row {
            spacing: Style.space(8)
            LeagueTag { leagueId: card.fav.league }
            Text {
              textFormat: Text.PlainText
              visible: !!card.fav.standing
              text: card.fav.standing ? root.ordinal(card.fav.standing.rank) + (card.fav.standing.group ? " in " + card.fav.standing.group.replace(/ Conference$/, "") : "") + "  ·  " + card.fav.standing.pts + " pts  ·  " + card.fav.standing.played + " played" : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
        FormDots {
          id: formDots
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          form: card.fav.form || []
        }
      }

      // Kicker: LIVE 67'  or  NEXT · SAT OCT 10 · 7:30 AM      in 4d 21h
      Item {
        visible: !!card.ev
        width: parent.width
        implicitHeight: kicker.implicitHeight
        Text {
          id: kicker
          anchors.left: parent.left
          textFormat: Text.PlainText
          text: !card.ev ? "" : card.live ? "●  LIVE  " + root.minute(card.ev)
            : "NEXT  ·  " + root.dayLabel(card.ev.ts).toUpperCase() + "  ·  " + root.timeLabel(card.ev.ts)
          color: card.live ? root.urgent : root.dim
          opacity: card.live ? 0.55 + 0.45 * root.pulse : 1
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1
        }
        Text {
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.baseline: kicker.baseline
          visible: !!card.ev && !card.live
          text: card.ev ? root.countdown(card.ev.ts) : ""
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Matchup {
        visible: !!card.ev
        width: parent.width
        ev: card.ev || ({ home: {}, away: {} })
        big: true
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openMatch(card.ev)
        }
      }

      // Goals and red cards while live.
      Column {
        visible: card.live && card.ev && card.ev.plays && card.ev.plays.length > 0
        width: parent.width
        spacing: Style.space(2)
        Repeater {
          model: card.live && card.ev ? card.ev.plays : []
          Text {
            required property var modelData
            readonly property bool home: card.ev && modelData.team === card.ev.home.id
            width: parent.width
            horizontalAlignment: home ? Text.AlignLeft : Text.AlignRight
            textFormat: Text.PlainText
            text: (modelData.red ? "▮ " : root.ball + " ") + modelData.player + "  " + modelData.minute + (modelData.pen ? " (P)" : "") + (modelData.og ? " (OG)" : "")
            color: modelData.red ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Text {
        visible: !!card.ev && !card.live && !!card.ev.venue
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: card.ev ? root.pin + " " + card.ev.venue + (card.ev.city ? ", " + card.ev.city : "") : ""
        elide: Text.ElideRight
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      // Where to watch
      Column {
        visible: !!card.ev && card.ev.watch && card.ev.watch.services.length > 0
        width: parent.width
        spacing: Style.space(6)

        Item {
          width: parent.width
          implicitHeight: watchLabel.implicitHeight
          Text {
            id: watchLabel
            textFormat: Text.PlainText
            text: "WHERE TO WATCH"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1
          }
          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.baseline: watchLabel.baseline
            text: !card.ev || !card.ev.watch ? ""
              : card.ev.watch.source === "espn" ? "✓ confirmed for this match"
              : card.ev.watch.verified === false ? "league rights · unconfirmed"
              : "league rights · channel TBA"
            color: card.ev && card.ev.watch && card.ev.watch.source === "espn" ? root.win : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        WatchChips {
          width: parent.width
          watch: card.ev ? card.ev.watch : ({ services: [] })
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: !card.ev
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "No upcoming fixtures scheduled"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      // Footer: last result, and the one after next.
      Rectangle { width: parent.width; height: 1; color: root.faint; visible: !!card.fav.last || !!card.fav.after }
      Item {
        visible: !!card.fav.last || !!card.fav.after
        width: parent.width
        implicitHeight: Math.max(lastRow.implicitHeight, afterText.implicitHeight)

        Row {
          id: lastRow
          visible: !!card.fav.last
          spacing: Style.space(6)
          readonly property var r: card.fav.form && card.fav.form.length ? card.fav.form[card.fav.form.length - 1] : null
          Text {
            textFormat: Text.PlainText
            text: "LAST"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            anchors.verticalCenter: parent.verticalCenter
          }
          Rectangle {
            visible: !!lastRow.r
            width: Style.space(14); height: width; radius: Style.space(3)
            anchors.verticalCenter: parent.verticalCenter
            color: !lastRow.r ? "transparent" : lastRow.r.r === "W" ? root.win : lastRow.r.r === "L" ? root.urgent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)
            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: lastRow.r ? lastRow.r.r : ""
              color: lastRow.r && lastRow.r.r === "D" ? root.fg : "#ffffff"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption * 0.85
              font.bold: true
            }
          }
          Text {
            textFormat: Text.PlainText
            text: lastRow.r ? lastRow.r.score + (lastRow.r.home ? " vs " : " at ") + lastRow.r.vs : ""
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }
        MouseArea {
          anchors.fill: lastRow
          visible: lastRow.visible
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openMatch(card.fav.last)
        }

        Text {
          id: afterText
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: !!card.fav.after
          text: card.fav.after ? "THEN  " + (card.fav.after.home.id === card.fav.team.id ? "vs " : "at ") + root.opponent(card.fav.after, card.fav.team.id).short + " · " + root.dayLabel(card.fav.after.ts) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
