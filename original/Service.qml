import QtQuick
import Quickshell
import Quickshell.Io

// Owns the single `matchday daemon` process, which polls ESPN, works out where
// each match is on TV, and sends the notifications. Bar widgets on every
// monitor share this state.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string cli: String(Qt.resolvedUrl("bin/matchday")).replace(/^file:\/\//, "")

  property var state: ({ status: "starting" })
  property string lastError: ""
  property int serial: 0

  readonly property bool running: daemon.running
  readonly property var config: state.config || ({})
  readonly property var favorites: state.favorites || []
  readonly property var events: state.events || []
  readonly property var leagues: state.leagues || []
  readonly property var tables: state.tables || ({})
  readonly property var teams: state.teams || ({})
  readonly property string logoDir: state.logoDir || ""

  function send(cmd, args) {
    if (!daemon.running) return false
    daemon.write(JSON.stringify(Object.assign({ cmd: cmd, id: ++serial }, args || {})) + "\n")
    return true
  }

  function follow(league, team, on) { return send("follow", { league: league, team: team, on: on }) }
  function setConfig(key, value) { var a = {}; a[key] = value; return send("config", a) }
  function openUrl(url) { return url ? send("open", { url: url }) : false }

  function handleLine(line) {
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (msg.type === "state") {
      root.state = msg.state || {}
    } else if (msg.type === "result" && !msg.ok) {
      root.lastError = msg.error || "command failed"
      clearError.restart()
    } else if (msg.type === "log" && msg.error) {
      console.warn("grivera.matchday:", msg.error)
    }
  }

  Process {
    id: daemon
    command: [root.cli, "daemon"]
    running: true
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.handleLine(line) } }
    onRunningChanged: {
      if (running) return
      root.state = Object.assign({}, root.state, { status: "stopped" })
      restart.restart()
    }
  }

  Timer {
    id: restart
    interval: 10000
    onTriggered: daemon.running = true
  }

  Timer {
    id: clearError
    interval: 6000
    onTriggered: root.lastError = ""
  }
}
