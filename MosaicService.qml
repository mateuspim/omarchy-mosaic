import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Model.js" as Model

// The Mosaic engine. The shell creates exactly one while the plugin is
// enabled and destroys it on disable and on every plugin reload; the bar
// widget reaches it with `bar.shell.serviceFor("pym.mosaic")`. It keeps the
// v1 tile list current from Hyprland and tiles.json and the v1 web app list
// current from the desktop entries, and it adds, replaces, focuses,
// removes, closes, and contains tiles. It also owns the plugin's IPC target,
// `pym.mosaic`, so `omarchy-shell pym.mosaic …` works without the widget.
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
  // What the running action is waiting for: "plan", "dispatch", or one of
  // add's steps ("add-clients", "add-monitors", "add-browser",
  // "add-browser-mime", "add-wait", "add-save").
  property string phase: ""
  property var pendingPlan: null
  // Dispatches still to run, and what to do once they have.
  property var pendingQueue: []
  property var afterQueue: null
  property string pendingMessage: ""
  property bool stepStarted: false
  property var addState: null
  // Where the cursor was while add or replace waited for the new window;
  // see Model.cursorMoveExpression.
  property var cursorBefore: null
  // The bar widget, which sets this when it finds the service; it resets to
  // null when the widget is destroyed. IPC calls that need the panel use it.
  property QtObject panel: null
  // Fullscreen state dispatches waiting to run after tiles moved.
  property var restoreQueue: []

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

  // `mosaic add [--session NAME] [--monitor NAME] [--browser CMD] TARGET...`.
  // `options` may hold `session` (default "default"), `monitor`, and
  // `browser`, a Chromium-family command used instead of the default
  // browser. Targets are resolved before anything opens, so a typo opens
  // nothing; then each one is launched, found by its openwindow event,
  // tagged, recorded in tiles.json, tiled, and contained, in that order.
  function add(targets, options, label) {
    if (busy) return "Still busy: " + busyLabel
    var given = options || {}
    var session = given.session ? String(given.session) : Model.DEFAULT_SESSION
    if (Model.sessionName(session) !== session)
      return "Invalid session name " + JSON.stringify(session) + ": use up to 32 lowercase letters, digits, - or _"
    var resolved = Model.resolveAddTargets(targets, Model.shapeWebapps(webapps).apps)
    if (resolved.error) return resolved.error
    addState = {
      session: session,
      monitor: given.monitor ? String(given.monitor) : "",
      browser: given.browser ? String(given.browser) : "",
      urls: resolved.urls,
      next: 0,
      clients: [],
      seen: [],
      workspace: 0,
      program: "",
      address: ""
    }
    begin(label || "Adding " + Model.stringList(targets).join(", ") + " to " + session)
    phase = "add-clients"
    runStep(["hyprctl", "-j", "clients"])
    return ""
  }

  // `mosaic replace TILE TARGET`: opens TARGET (a URL or web app) in the
  // tile's place. The new window joins the old tile's session and
  // workspace, takes its store position, and is swapped into its slot
  // before the old window closes, so the layout doesn't shift. `options`
  // may hold `browser`, as for add.
  function replace(tile, target, options, label) {
    if (busy) return "Still busy: " + busyLabel
    var resolved = Model.resolveAddTargets([target], Model.shapeWebapps(webapps).apps)
    if (resolved.error) return resolved.error
    var given = options || {}
    addState = {
      replacing: String(tile),
      old: null,
      session: "",
      monitor: "",
      browser: given.browser ? String(given.browser) : "",
      urls: resolved.urls,
      next: 0,
      clients: [],
      seen: [],
      workspace: 0,
      program: "",
      address: ""
    }
    begin(label || "Replacing tile " + tile + " with " + target)
    phase = "add-clients"
    runStep(["hyprctl", "-j", "clients"])
    return ""
  }

  // Starts an action and returns "", or an error when another one is still
  // running. The action reads fresh clients, because containment can change
  // without any Hyprland event, lets `planner(list)` choose the dispatches,
  // then runs them in order and stops at the first one Hyprland rejects.
  function startAction(label, planner) {
    if (busy) return "Still busy: " + busyLabel
    begin(label)
    pendingPlan = planner
    phase = "plan"
    runStep(["hyprctl", "-j", "clients"])
    return ""
  }

  function begin(label) {
    busy = true
    busyLabel = label
    pendingQueue = []
    afterQueue = null
    pendingMessage = ""
  }

  // Runs one command of the current action, with a time limit.
  function runStep(command, environment) {
    stepStarted = false
    stepProcess.environment = environment || ({})
    stepProcess.command = command
    actionTimeout.restart()
    stepProcess.running = true
  }

  // Quickshell never emits `exited` for a command that cannot start.
  function stepFailedToStart() {
    if (!busy) return
    var program = stepProcess.command[0]
    // Without xdg-settings, try xdg-mime, as the CLI does.
    if (phase === "add-browser") return queryBrowser("add-browser-mime")
    if (phase === "add-browser-mime") return finishAction("Cannot determine the default browser; set the widget's browser setting")
    finishAction("Cannot run " + program)
  }

  function stepFinished(exitCode, output, errors) {
    if (!busy) return
    actionTimeout.stop()
    var text = String(output)
    if (phase === "add-browser" || phase === "add-browser-mime")
      return browserFound(exitCode === 0 ? Model.desktopId(text) : "")
    if (exitCode !== 0) return finishAction(String(errors).trim() || stepProcess.command[0] + " failed")
    if (phase === "plan") {
      var clients = Model.parseClients(text)
      if (clients === null) return finishAction("Unexpected hyprctl clients output")
      var result = pendingPlan(Model.buildList(clients, knownMonitors(), records))
      pendingPlan = null
      if (result.error) return finishAction(result.error)
      pendingMessage = result.message
      return runQueue(result.expressions, function() { root.finishAction("") })
    }
    if (phase === "add-clients") {
      var current = Model.parseClients(text)
      if (current === null) return finishAction("Unexpected hyprctl clients output")
      addState.clients = current
      addState.seen = current.map(function(client) { return client.address })
      if (addState.replacing !== undefined) {
        records = Model.pruneRecords(records, current)
        var planned = Model.planReplace(Model.buildList(current, knownMonitors(), records), addState.replacing)
        if (planned.error) return finishAction(planned.error)
        addState.old = planned.tile
        addState.session = planned.tile.session
        addState.workspace = planned.tile.workspace
        return chooseBrowser()
      }
      phase = "add-monitors"
      return runStep(["hyprctl", "-j", "monitors"])
    }
    if (phase === "add-monitors") {
      var monitors = Model.parseMonitors(text)
      if (monitors === null) return finishAction("Unexpected hyprctl monitors output")
      records = Model.pruneRecords(records, addState.clients)
      var chosen = Model.chooseWorkspace(Model.buildList(addState.clients, monitors, records), monitors,
        addState.session, addState.monitor)
      if (chosen.error) return finishAction(chosen.error)
      addState.workspace = chosen.workspace
      return chooseBrowser()
    }
    // A dispatch.
    if (text.trim() !== "ok") return finishAction("Hyprland rejected " + stepProcess.command[2] + ": " + text.trim())
    runQueue(pendingQueue, afterQueue)
  }

  function chooseBrowser() {
    if (addState.browser === "") return queryBrowser("add-browser")
    addState.program = addState.browser
    launchNext()
  }

  // Asks for the desktop's default browser. BROWSER is cleared, because
  // xdg-settings would otherwise answer with it instead of the desktop's.
  function queryBrowser(nextPhase) {
    phase = nextPhase
    if (nextPhase === "add-browser") runStep(["xdg-settings", "get", "default-web-browser"], { BROWSER: null })
    else runStep(["xdg-mime", "query", "default", "x-scheme-handler/https"], { BROWSER: null })
  }

  function browserFound(id) {
    if (id === "" && phase === "add-browser") return queryBrowser("add-browser-mime")
    if (id === "") return finishAction("Cannot determine the default browser; set the widget's browser setting")
    if (!Model.isChromiumFamily(id))
      return finishAction("The default browser (" + id + ") is not Chromium-based. Set the widget's browser setting to a Chromium-family browser such as brave.")
    var entry = DesktopEntries.byId(id)
    var command = entry ? Model.stringList(entry.command) : []
    if (command.length === 0 || command[0] === "") return finishAction("Cannot find an Exec line for " + id)
    addState.program = command[0]
    launchNext()
  }

  // Opens the next URL as an app window and waits for Hyprland to announce
  // it. `uwsm-app` starts it in its own scope, as Omarchy's launchers do,
  // and the argv list means a URL can never reach a shell.
  function launchNext() {
    if (addState.next >= addState.urls.length) {
      pendingMessage = addState.old
        ? "Replaced tile " + addState.old.index + " with " + addState.urls[0] + "."
        : "Session " + addState.session + ": " + addState.urls.length + " tile(s) added on workspace "
          + addState.workspace + " with " + addState.program + "."
      return finishAction("")
    }
    phase = "add-wait"
    addState.address = ""
    cursorBefore = null
    sampleCursor()
    Quickshell.execDetached(["uwsm-app", "--", addState.program, "--app=" + addState.urls[addState.next]])
    windowTimeout.restart()
  }

  // An openwindow event: during add-wait, the first new app window is the
  // tile. Mirrors `open_tile` in the CLI.
  function windowOpened(data) {
    if (!busy || phase !== "add-wait") return
    var opened = Model.parseOpenWindow(data)
    if (!opened || addState.seen.indexOf(opened.address) !== -1 || !Model.isAppWindow(opened.windowClass)) return
    windowTimeout.stop()
    addState.seen.push(opened.address)
    addState.address = opened.address
    var steps = Model.tileDispatches(opened.address, addState.session, addState.workspace, addState.old)
    if (steps.error) return finishAction(steps.error)
    // Undo the cursor warp to the new window. Hyprland warps a moment after
    // the window maps, so this runs last, once the tile is in place.
    var cursorBack = Model.cursorMoveExpression(cursorBefore)
    if (cursorBack !== "") steps.place = steps.place.concat([cursorBack])
    // Record the tile as soon as it is tagged, so a later failure still
    // leaves it listed with its URL.
    runQueue(steps.tags, function() {
      root.saveRecord(function() {
        root.runQueue(steps.place, function() {
          root.addState.next++
          root.launchNext()
        })
      })
    })
  }

  function saveRecord(then) {
    phase = "add-save"
    var record = { address: addState.address, session: addState.session, url: addState.urls[addState.next] }
    records = addState.old ? Model.replaceRecord(records, addState.old.address, record) : records.concat([record])
    afterQueue = then
    actionTimeout.restart()
    store.setText(Model.serializeStore(records))
  }

  function sampleCursor() {
    if (!cursorProcess.running) cursorProcess.running = true
  }

  // Runs Hyprland dispatches in order, then `then()`.
  function runQueue(expressions, then) {
    if (expressions.length === 0) return then()
    pendingQueue = expressions.slice(1)
    afterQueue = then
    phase = "dispatch"
    runStep(["hyprctl", "dispatch", expressions[0]])
  }

  function knownMonitors() {
    var monitors = []
    var outputs = Hyprland.monitors.values
    for (var m = 0; m < outputs.length; m++) monitors.push({ id: outputs[m].id, name: outputs[m].name })
    return monitors
  }

  function finishAction(error) {
    var label = busyLabel
    actionTimeout.stop()
    windowTimeout.stop()
    busy = false
    busyLabel = ""
    phase = ""
    pendingPlan = null
    pendingQueue = []
    afterQueue = null
    refresh()
    actionFinished(label, error, error ? "" : pendingMessage)
  }

  // Queues re-applying a moved tile's fullscreen state, since a move leaves
  // Hyprland's record of it stale (see Model.restoreAfterMove).
  function restoreMoved(eventData) {
    // The window add or replace is placing gets its containment from them.
    if (busy && addState && addState.address !== "" && String(eventData).split(",")[0] === addState.address.slice(2)) return
    var expression = Model.restoreAfterMove(list, eventData)
    if (expression === "") return
    restoreQueue = restoreQueue.concat([expression])
    restoreNext()
  }

  function restoreNext() {
    if (restoreProcess.running) return
    if (restoreQueue.length === 0) return refresh()
    restoreProcess.command = ["hyprctl", "dispatch", restoreQueue[0]]
    restoreQueue = restoreQueue.slice(1)
    restoreProcess.running = true
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

  // The address of the focused window when it is a tile, or "".
  function focusedTile() {
    var toplevel = Hyprland.activeToplevel
    var address = toplevel && toplevel.lastIpcObject ? String(toplevel.lastIpcObject.address || "") : ""
    if (address === "" && toplevel) address = "0x" + toplevel.address
    return Model.findTile(Model.listTiles(list), address) ? address : ""
  }

  Component.onCompleted: {
    refresh()
    rebuildWebapps()
  }

  // `omarchy-shell pym.mosaic <function>`. Each returns what it did, or why
  // it could not.
  IpcHandler {
    target: "pym.mosaic"

    // Opens the panel in swap mode for the focused tile, so a key bound to
    // `omarchy-shell pym.mosaic swap` changes the tile you are looking at.
    function swap(): string {
      var address = root.focusedTile()
      if (address === "") return "The focused window is not a mosaic tile"
      if (!root.panel) return "Add the Mosaic widget to the bar to swap tiles"
      root.panel.startSwapFor(address)
      return "Pick what replaces this tile in the Mosaic panel"
    }
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
      // Checked against the list from before the move, so this runs first.
      if (name === "movewindowv2") root.restoreMoved(event.data)
      if (name === "openwindow") root.windowOpened(event.data)
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
    onRunningChanged: if (!running && !root.stepStarted) root.stepFailedToStart()
    onExited: function(exitCode) { root.stepFinished(exitCode, stepStdout.text, stepStderr.text) }
  }

  // Fire-and-forget: a tile that is gone by now just fails its dispatch.
  // The queue moves on whenever the process stops, whether it exited, was
  // killed by the timeout, or never started.
  Process {
    id: restoreProcess
    running: false
    onRunningChanged: {
      if (running) {
        restoreTimeout.restart()
      } else {
        restoreTimeout.stop()
        Qt.callLater(root.restoreNext)
      }
    }
  }

  // Keeps `cursorBefore` current while a new window is awaited. A sample
  // that lands after the window opened may already be the warped position,
  // so only samples taken during add-wait count.
  Process {
    id: cursorProcess
    running: false
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector { id: cursorStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0 && root.busy && root.phase === "add-wait") {
        var position = Model.parseCursorPos(cursorStdout.text)
        if (position) root.cursorBefore = position
      }
    }
  }

  Timer {
    interval: 150
    repeat: true
    running: root.busy && root.phase === "add-wait"
    onTriggered: root.sampleCursor()
  }

  // A dispatch that never answers must not hold the queue forever.
  Timer {
    id: restoreTimeout
    interval: 5000
    onTriggered: restoreProcess.running = false
  }

  // Every step of an action must answer within this time.
  Timer {
    id: actionTimeout
    interval: 5000
    onTriggered: {
      var what = root.phase === "add-save" ? "Saving tiles.json took too long" : stepProcess.command[0] + " did not answer in time"
      root.finishAction(what)
      stepProcess.running = false
    }
  }

  // How long a launched browser has to open its app window.
  Timer {
    id: windowTimeout
    interval: Model.WINDOW_TIMEOUT_MS
    onTriggered: if (root.busy && root.phase === "add-wait")
      root.finishAction("No browser app window appeared for " + root.addState.urls[root.addState.next])
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
    onSaved: if (root.busy && root.phase === "add-save") {
      actionTimeout.stop()
      root.afterQueue()
    }
    onSaveFailed: function(error) {
      if (root.busy && root.phase === "add-save") root.finishAction("Cannot write " + root.storePath + ": " + error)
    }
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
