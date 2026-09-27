import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Model.js" as Model

// The Mosaic engine. The shell creates exactly one while the plugin is
// enabled and destroys it on disable and on every plugin reload; the bar
// widget reaches it with `bar.shell.serviceFor("pym.mosaic")`. It keeps the
// v1 tile list current from Hyprland and tiles.json and the v1 web app list
// current from the desktop entries, and it focuses, removes, closes, and
// contains tiles. Adding tiles still goes through the mosaic CLI.
Scope {
  id: root

  // `mosaic list --json`, version 1, rebuilt whenever Hyprland or the store
  // changes.
  property var list: ({ version: Model.LIST_VERSION, sessions: [] })
  property var records: []
  // `mosaic webapps --json`, version 1, rebuilt whenever the installed
  // applications change.
  property var webapps: ({ version: Model.WEBAPPS_VERSION, webapps: [] })

  // One action runs at a time; `busyLabel` describes it while it runs.
  property bool busy: false
  property string busyLabel: ""
  property var pendingPlan: null
  property var pendingExpressions: []
  property string pendingMessage: ""
  property bool stepStarted: false

  // Emitted when an action ends. `error` is "" on success, and `message`
  // then says what was done, like the CLI's output.
  signal actionFinished(string label, string error, string message)

  readonly property string storePath: {
    var state = Quickshell.env("XDG_STATE_HOME") || ""
    var home = Quickshell.env("HOME") || ""
    return (state.indexOf("/") === 0 ? state : home + "/.local/state") + "/mosaic/tiles.json"
  }

  // Asks Hyprland for fresh client data and rereads the store. Tag changes
  // emit no Hyprland event, so callers refresh after anything that may have
  // tagged a window.
  function refresh() {
    refreshTimer.restart()
  }

  function rebuild() {
    var toplevels = Hyprland.toplevels.values
    var clients = []
    for (var i = 0; i < toplevels.length; i++) {
      var client = Model.clientFromIpc(toplevels[i].lastIpcObject)
      if (client) clients.push(client)
    }
    var monitors = []
    var outputs = Hyprland.monitors.values
    for (var m = 0; m < outputs.length; m++) monitors.push({ id: outputs[m].id, name: outputs[m].name })
    var next = Model.buildList(clients, monitors, records)
    if (JSON.stringify(next) !== JSON.stringify(list)) list = next
  }

  // `mosaic focus TILE`: a tile's number in the list, or its address.
  // `label`, optional, describes the action while it runs.
  function focus(target, label) {
    return startAction(label || "Focusing tile " + target, function(list) { return Model.planFocus(list, target) })
  }

  // `mosaic remove TILE...`.
  function remove(targets, label) {
    return startAction(label || "Removing " + Model.stringList(targets).join(", "), function(list) { return Model.planRemove(list, targets) })
  }

  // `mosaic close [--session NAME]`; "" closes every tile.
  function close(session, label) {
    return startAction(label || (session ? "Closing " + session : "Closing every tile"), function(list) { return Model.planClose(list, session) })
  }

  // `mosaic contain [--session NAME]`; "" contains every session's tiles.
  function contain(session, label) {
    return startAction(label || "Containing fullscreen", function(list) { return Model.planContain(list, session) })
  }

  // Starts an action and returns "", or an error when another one is still
  // running. The action reads fresh clients, because containment can change
  // without any Hyprland event, lets `planner(list)` choose the dispatches,
  // then runs them in order and stops at the first one Hyprland rejects.
  function startAction(label, planner) {
    if (busy) return "Still busy: " + busyLabel
    busy = true
    busyLabel = label
    pendingPlan = planner
    pendingExpressions = []
    pendingMessage = ""
    actionTimeout.restart()
    runStep(["hyprctl", "-j", "clients"])
    return ""
  }

  function runStep(command) {
    stepStarted = false
    stepProcess.command = command
    stepProcess.running = true
  }

  function stepFinished(exitCode, output, errors) {
    if (!busy) return
    if (exitCode !== 0) {
      finishAction(String(errors).trim() || "hyprctl failed")
    } else if (pendingPlan) {
      var clients = Model.parseClients(output)
      if (clients === null) return finishAction("Unexpected hyprctl clients output")
      var monitors = []
      var outputs = Hyprland.monitors.values
      for (var m = 0; m < outputs.length; m++) monitors.push({ id: outputs[m].id, name: outputs[m].name })
      var result = pendingPlan(Model.buildList(clients, monitors, records))
      pendingPlan = null
      if (result.error) return finishAction(result.error)
      pendingExpressions = result.expressions
      pendingMessage = result.message
      dispatchNext()
    } else if (String(output).trim() !== "ok") {
      finishAction("Hyprland rejected " + stepProcess.command[2] + ": " + String(output).trim())
    } else {
      dispatchNext()
    }
  }

  function dispatchNext() {
    if (pendingExpressions.length === 0) return finishAction("")
    var next = pendingExpressions[0]
    pendingExpressions = pendingExpressions.slice(1)
    actionTimeout.restart()
    runStep(["hyprctl", "dispatch", next])
  }

  function finishAction(error) {
    var label = busyLabel
    actionTimeout.stop()
    busy = false
    busyLabel = ""
    pendingPlan = null
    pendingExpressions = []
    refresh()
    actionFinished(label, error, error ? "" : pendingMessage)
  }

  function rebuildWebapps() {
    var values = DesktopEntries.applications.values
    var entries = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      entries.push({ id: entry.id, name: entry.name, icon: entry.icon, noDisplay: entry.noDisplay, command: entry.command })
    }
    var next = Model.buildWebapps(entries)
    if (JSON.stringify(next) !== JSON.stringify(webapps)) webapps = next
  }

  Component.onCompleted: {
    refresh()
    rebuildWebapps()
  }

  // Coalesces the burst of events one window change produces.
  Timer {
    id: refreshTimer
    interval: 150
    onTriggered: {
      Hyprland.refreshToplevels()
      Hyprland.refreshMonitors()
      store.reload()
    }
  }

  Timer {
    id: rebuildTimer
    interval: 50
    onTriggered: root.rebuild()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event.name
      if (name === "openwindow" || name === "closewindow" || name === "movewindowv2"
          || name === "changefloatingmode" || name === "fullscreen" || name === "windowtitlev2"
          || name === "moveworkspacev2" || name === "monitoraddedv2" || name === "monitorremovedv2")
        root.refresh()
    }
  }

  // lastIpcObject only changes on refreshToplevels(), which answers
  // asynchronously, so rebuild whenever any client's data lands.
  Instantiator {
    model: Hyprland.toplevels
    delegate: Connections {
      required property var modelData
      target: modelData
      function onLastIpcObjectChanged() { rebuildTimer.restart() }
    }
    onObjectAdded: rebuildTimer.restart()
    onObjectRemoved: rebuildTimer.restart()
  }

  Process {
    id: stepProcess
    running: false
    stdout: StdioCollector { id: stepStdout; waitForEnd: true }
    stderr: StdioCollector { id: stepStderr; waitForEnd: true }
    onStarted: root.stepStarted = true
    // Quickshell never emits `exited` for a command that cannot start.
    onRunningChanged: if (!running && !root.stepStarted && root.busy) root.finishAction("Cannot run hyprctl")
    onExited: function(exitCode) { root.stepFinished(exitCode, stepStdout.text, stepStderr.text) }
  }

  // Every step of an action must answer within this time.
  Timer {
    id: actionTimeout
    interval: 5000
    onTriggered: {
      root.finishAction("Hyprland did not answer in time")
      stepProcess.running = false
    }
  }

  // DesktopEntries scans the application directories asynchronously and
  // reports every entry it adds, so wait for the burst to settle.
  Timer {
    id: webappsTimer
    interval: 250
    onTriggered: root.rebuildWebapps()
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { webappsTimer.restart() }
  }

  FileView {
    id: store
    path: root.storePath
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
    onLoaded: {
      root.records = Model.parseStore(text())
      rebuildTimer.restart()
    }
    onLoadFailed: {
      root.records = []
      rebuildTimer.restart()
    }
  }
}
