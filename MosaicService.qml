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
  // What to do with the browser once it is known: function(program, id).
  property var browserChosen: null
  // restartBrowser's state: { browser, clientsText, program, name, pids }.
  property var restartState: null
  // Where the cursor was while add or replace waited for the new window;
  // see Model.cursorMoveExpression.
  property var cursorBefore: null
  // The bar widget, which sets this when it finds the service; it resets to
  // null when the widget is destroyed. The swap key is only bound while the
  // widget exists, since its settings choose the key.
  property QtObject panel: null
  // The swap key: what the widget's setting asks for, what is bound now,
  // and why the last attempt to bind it failed. The service binds it at
  // runtime with `hyprctl eval`, so it follows the setting, and binds it
  // again after a config reload, which drops runtime binds.
  property string swapKey: ""
  // The widget's Browser and Hidden web apps settings, for the swap card.
  property string browser: ""
  property string hiddenWebapps: ""
  property string boundSwapKey: ""
  property string swapKeyError: ""
  property var keyThen: null
  // The card the swap key opens over a tile.
  readonly property alias swapCard: swapCard

  onSwapKeyChanged: keySync.restart()
  onPanelChanged: keySync.restart()
  // Fullscreen state dispatches waiting to run after tiles moved.
  property var restoreQueue: []

  // Actions are numbered so IPC callers can ask how one ended: `job` is the
  // running or last action's number, and `results` maps recent numbers to
  // { error, message }.
  property int job: 0
  property var results: ({})
  // Enabled monitors (Model.parseMonitors), refreshed with the list.
  property var monitors: []

  // The browser extension (extension/). Each browser's copy talks to the
  // service through the native host, bin/mosaic-native-host, which connects
  // to `bridgePath`. `extensionSetup` is the host's `status` output (null
  // until it answers), `bridges` the connected extensions ({ browser,
  // extension, windows }), and `extensionCheck` the last verify: null, {
  // error }, or Model.matchTiles output.
  property var extensionSetup: null
  property string extensionError: ""
  property var bridges: []
  property var extensionCheck: null
  property bool verifying: false
  readonly property string extensionState: Model.extensionState(extensionSetup, bridges)
  readonly property string extensionDir: Qt.resolvedUrl("extension").toString().replace(/^file:\/\//, "")
  readonly property string hostProgram: Qt.resolvedUrl("bin/mosaic-native-host").toString().replace(/^file:\/\//, "")
  // The host uses the same override, so a test shell can have its own.
  readonly property string bridgePath: {
    var override = Quickshell.env("MOSAIC_BRIDGE_SOCKET") || ""
    if (override !== "") return override
    var runtime = Quickshell.env("XDG_RUNTIME_DIR") || ""
    return (runtime !== "" ? runtime : "/tmp") + "/pym-mosaic.sock"
  }
  // Open bridge connections, and the ones a verify still waits for.
  property var bridgeSockets: []
  property var pingWaiting: []
  property int pingId: 0
  property bool extensionStarted: false

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

  // Restarts the browser the tiles run in, so it loads the extension:
  // closes it with SIGTERM, which Chromium treats as a normal quit that
  // keeps the session, waits for it to exit, and starts it again. Its tiles
  // close with it. `options` may hold `browser`, as for add; without it,
  // the default browser is restarted, along with whichever browser the
  // tiles use.
  function restartBrowser(options, label) {
    if (busy) return "Still busy: " + busyLabel
    var given = options || {}
    restartState = { browser: given.browser ? String(given.browser) : "", clientsText: "", program: "", name: "", pids: [] }
    begin(label || "Restarting the browser")
    phase = "restart-clients"
    runStep(["hyprctl", "-j", "clients"])
    return ""
  }

  function restartWith(program, id) {
    restartState.program = program
    restartState.name = Model.browserLabel(id || program)
    var classes = [Model.browserClass(id), Model.browserClass(program)].filter(function(name) { return name !== "" })
    var pids = Model.browserPids(restartState.clientsText, classes)
    if (pids === null) return finishAction("Unexpected hyprctl clients output")
    restartState.pids = pids
    if (pids.length === 0) return relaunchBrowser()
    phase = "restart-kill"
    runStep(["kill", "-TERM"].concat(pids.map(String)))
  }

  // `tail --pid` returns once every process is gone; `timeout` bounds it.
  function waitForBrowserExit() {
    phase = "restart-wait"
    var watch = restartState.pids.map(function(pid) { return "--pid=" + pid })
    runStep(["timeout", "15", "tail", "-f", "/dev/null"].concat(watch), null, 17000)
  }

  function relaunchBrowser() {
    Quickshell.execDetached(["uwsm-app", "--", restartState.program])
    pendingMessage = (restartState.pids.length > 0 ? "Restarted " : "Started ") + restartState.name + "."
    finishAction("")
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
    job++
    busy = true
    busyLabel = label
    pendingQueue = []
    afterQueue = null
    pendingMessage = ""
  }

  // Runs one command of the current action, with a time limit.
  function runStep(command, environment, timeoutMs) {
    stepStarted = false
    stepProcess.environment = environment || ({})
    stepProcess.command = command
    actionTimeout.interval = timeoutMs || 5000
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
    // A process that is already gone makes kill fail, which is fine.
    if (phase === "restart-kill") return waitForBrowserExit()
    if (phase === "restart-wait") {
      if (exitCode !== 0) return finishAction(restartState.name + " is still closing; try again in a moment")
      return relaunchBrowser()
    }
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
    if (phase === "restart-clients") {
      restartState.clientsText = text
      browserChosen = function(program, id) { root.restartWith(program, id) }
      if (restartState.browser === "") return queryBrowser("add-browser")
      return browserChosen(restartState.browser, "")
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
    browserChosen = function(program, id) {
      root.addState.program = program
      root.launchNext()
    }
    if (addState.browser === "") return queryBrowser("add-browser")
    browserChosen(addState.browser, "")
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
    browserChosen(command[0], id)
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
    var kept = {}
    for (var n = job - 19; n < job; n++) if (results[n]) kept[n] = results[n]
    kept[job] = { error: error, message: error ? "" : pendingMessage }
    results = kept
    settleTimer.restart()
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

  // Makes the bound swap key match the setting. Without the widget, there
  // is no panel to swap in, so no key is bound.
  function syncSwapKey() {
    if (keyProcess.running) return keySync.restart()
    var parsed = panel ? Model.parseKeySpec(swapKey) : Model.parseKeySpec("")
    if (boundSwapKey !== "" && (!parsed || boundSwapKey !== parsed.spec)) {
      var old = boundSwapKey
      boundSwapKey = ""
      return runKeyStep(["hyprctl", "eval", Model.unbindLua(old)], function() { root.syncSwapKey() })
    }
    if (!parsed) {
      swapKeyError = JSON.stringify(swapKey) + " is not a key. Write it like SUPER + SHIFT + S."
      return
    }
    swapKeyError = ""
    if (parsed.spec === "" || boundSwapKey === parsed.spec) return
    runKeyStep(["hyprctl", "-j", "binds"], function(output) {
      var taken = Model.bindConflict(output, parsed)
      if (taken !== "") {
        root.swapKeyError = parsed.spec + " is already bound to " + taken + ". Pick another swap key in the widget settings."
        return
      }
      // A bind this service left behind, say before a shell restart, is
      // reused instead of doubled.
      if (root.ownBindOn(output, parsed)) {
        root.boundSwapKey = parsed.spec
        return
      }
      root.runKeyStep(["hyprctl", "eval", Model.swapBindLua(parsed.spec)], function(reply) {
        if (reply.trim() === "ok") root.boundSwapKey = parsed.spec
        else root.swapKeyError = "Cannot bind " + parsed.spec + ": " + reply.trim().replace(/^error:\s*/, "")
      })
    })
  }

  // Whether `hyprctl -j binds` output already has the service's bind on the
  // parsed key.
  function ownBindOn(bindsText, parsed) {
    try {
      var binds = JSON.parse(bindsText)
      return binds.some(function(bind) {
        return bind.description === Model.SWAP_BIND_DESCRIPTION && bind.submap === "" && bind.modmask === parsed.modmask
          && String(bind.key).toLowerCase() === parsed.key.toLowerCase()
      })
    } catch (error) {
      return false
    }
  }

  function runKeyStep(command, then) {
    keyThen = then
    keyProcess.command = command
    keyTimeout.restart()
    keyProcess.running = true
  }

  Component.onDestruction: {
    if (boundSwapKey !== "") Quickshell.execDetached(["hyprctl", "eval", Model.unbindLua(boundSwapKey)])
  }

  // The focused window's tile from the list, with its session, or null.
  function focusedTile() {
    var toplevel = Hyprland.activeToplevel
    var address = toplevel && toplevel.lastIpcObject ? String(toplevel.lastIpcObject.address || "") : ""
    if (address === "" && toplevel) address = "0x" + toplevel.address
    for (var s = 0; s < list.sessions.length; s++) {
      for (var t = 0; t < list.sessions[s].tiles.length; t++) {
        var tile = list.sessions[s].tiles[t]
        if (tile.address === address) return Object.assign({ session: list.sessions[s].name }, tile)
      }
    }
    return null
  }

  Component.onCompleted: {
    refresh()
    rebuildWebapps()
    refreshExtension()
  }

  // Rereads what is set up for the extension.
  function refreshExtension() {
    return runHost("status")
  }

  // Registers the native host with every browser profile found, and loads
  // the extension from each browser flags file, as Omarchy loads its own.
  // The browser picks it up on its next start.
  function enableExtension() {
    extensionCheck = null
    return runHost("setup")
  }

  // Undoes enableExtension.
  function disableExtension() {
    extensionCheck = null
    return runHost("remove")
  }

  function runHost(command) {
    if (extensionProcess.running) return "Still busy with the browser extension"
    extensionError = ""
    extensionStarted = false
    extensionProcess.command = [hostProgram, command, extensionDir]
    extensionTimeout.restart()
    extensionProcess.running = true
    return ""
  }

  function hostFinished(exitCode, output, errors) {
    extensionTimeout.stop()
    var parsed = null
    try {
      parsed = exitCode === 0 ? JSON.parse(output) : null
    } catch (error) {
      parsed = null
    }
    if (parsed && Array.isArray(parsed.browsers) && Array.isArray(parsed.flags)) extensionSetup = parsed
    else extensionError = String(errors).trim().replace(/^error:\s*/, "") || "The native host failed"
  }

  // Asks every connected extension for its windows and checks that each
  // tile is one of them. The outcome lands in extensionCheck.
  function verifyExtension() {
    if (verifying) return ""
    refreshExtension()
    var open = bridgeSockets.filter(function(socket) { return socket.info.hello })
    if (open.length === 0) {
      extensionCheck = { error: extensionState === "restart" ? "Not connected yet: restart the browser first" : "No browser extension is connected" }
      return ""
    }
    pingId++
    pingWaiting = open
    verifying = true
    verifyTimeout.restart()
    var line = JSON.stringify({ type: "ping", id: pingId }) + "\n"
    open.forEach(function(socket) {
      socket.write(line)
      socket.flush()
    })
    return ""
  }

  function finishVerify() {
    verifyTimeout.stop()
    var silent = pingWaiting.length
    verifying = false
    pingWaiting = []
    if (silent > 0 && silent === bridgeSockets.filter(function(socket) { return socket.info.hello }).length) {
      extensionCheck = { error: "The browser extension did not answer" }
      return
    }
    extensionCheck = Model.matchTiles(Model.shapeList(list).tiles, bridges)
  }

  function bridgeOpened(socket) {
    socket.info = { browser: "", extension: "", windows: [], hello: false }
    bridgeSockets = bridgeSockets.concat([socket])
  }

  // Quickshell never destroys a closed handler socket, and refuses to, so
  // the service just lets go of it.
  function bridgeClosed(socket) {
    bridgeSockets = bridgeSockets.filter(function(open) { return open !== socket })
    if (verifying) {
      pingWaiting = pingWaiting.filter(function(open) { return open !== socket })
      if (pingWaiting.length === 0) finishVerify()
    }
    updateBridges()
  }

  function bridgeRead(socket, line) {
    var message = Model.parseBridgeMessage(line)
    if (!message || bridgeSockets.indexOf(socket) === -1) return
    var info = socket.info
    if (message.type === "host") info.browser = String(message.browser || "")
    else if (message.type === "hello") {
      info.extension = String(message.extension || "")
      info.hello = true
    } else if (message.type === "windows") info.windows = Model.bridgeWindows(message.windows)
    else return
    updateBridges()
    if (verifying && message.type === "windows" && message.id === pingId) {
      pingWaiting = pingWaiting.filter(function(open) { return open !== socket })
      if (pingWaiting.length === 0) finishVerify()
    }
  }

  function updateBridges() {
    bridges = bridgeSockets.filter(function(socket) { return socket.info.hello }).map(function(socket) {
      return { browser: socket.info.browser, extension: socket.info.extension, windows: socket.info.windows }
    })
    autoCheck()
  }

  // Keeps extensionCheck current without a verify: the extension reports
  // its windows whenever they change, so matching again on every change of
  // them or of the tiles is enough. Without a connection there is nothing
  // to check.
  function autoCheck() {
    if (verifying) return
    extensionCheck = bridges.length > 0 ? Model.matchTiles(Model.shapeList(list).tiles, bridges) : null
  }

  onListChanged: autoCheck()

  // The extension's state for scripts: `omarchy-shell pym.mosaic extension`.
  function extensionStatus() {
    return JSON.stringify({
      state: extensionState,
      error: extensionError,
      setup: extensionSetup,
      bridges: bridges.map(function(bridge) {
        return { browser: Model.browserLabel(bridge.browser), extension: bridge.extension, windows: bridge.windows.length }
      }),
      check: extensionCheck
    })
  }

  // Starts an IPC action: "started N", where N is the job number that
  // `result` reports on, or why it did not start.
  function started(error) {
    return error ? "error: " + error : "started " + job
  }

  // `omarchy-shell pym.mosaic <function> [args]`, and the `bin/mosaic`
  // wrapper, which mirrors the CLI on top of it. Every argument must be
  // passed; "" means not given. Lists of targets are one per line. Actions
  // run in the background, since IPC calls must answer at once.
  IpcHandler {
    target: "pym.mosaic"

    // `mosaic list --json`, version 1.
    function list(): string { return JSON.stringify(root.list) }
    // `mosaic list`.
    function listText(): string { return Model.listText(root.list) }
    // `mosaic webapps --json`, version 1.
    function webapps(): string { return JSON.stringify(root.webapps) }
    // `mosaic webapps`.
    function webappsText(): string { return Model.webappsText(root.webapps) }
    // `mosaic monitors`.
    function monitors(): string { return Model.monitorsText(root.monitors) }
    // `mosaic --version`.
    function version(): string { return root.versionText }

    // `mosaic add [--session S] [--monitor M] [--browser B] TARGET...`.
    function add(targets: string, session: string, monitor: string, browser: string): string {
      return root.started(root.add(Model.splitLines(targets), { session: session, monitor: monitor, browser: browser || root.browser }))
    }
    // Opens TARGET in TILE's place (a list number or address).
    function replace(tile: string, target: string, browser: string): string {
      return root.started(root.replace(tile, target, { browser: browser || root.browser }))
    }
    // `mosaic remove TILE...`.
    function remove(tiles: string): string { return root.started(root.remove(Model.splitLines(tiles))) }
    // `mosaic focus TILE`.
    function focus(tile: string): string { return root.started(root.focus(tile)) }
    // `mosaic close [--session S]`.
    function close(session: string): string { return root.started(root.close(session)) }
    // `mosaic contain [--session S]`.
    function contain(session: string): string { return root.started(root.contain(session)) }

    // How action JOB went: "running", "done" or "error" on the first line,
    // then the CLI's message or the error; "unknown" for an old number.
    function result(job: int): string {
      // An action counts as running until the list has caught up with it,
      // so `mosaic add` followed by `mosaic list` shows the new tiles.
      if (job === root.job && (root.busy || settleTimer.running)) return "running"
      var outcome = root.results[job]
      if (!outcome) return "unknown"
      return outcome.error ? "error\n" + outcome.error : "done\n" + outcome.message
    }

    // Opens the swap card over the focused tile, so the swap key changes
    // the tile you are looking at.
    function swap(): string {
      var tile = root.focusedTile()
      if (!tile) return "The focused window is not a mosaic tile"
      if (root.busy) return "Still busy: " + root.busyLabel
      swapCard.openFor(tile)
      return "Pick what replaces this tile on the card over it"
    }

    // The browser extension's setup and connection, as JSON.
    function extension(): string { return root.extensionStatus() }
    // Checks that the extension answers and finds every tile; read the
    // outcome from `extension` a few seconds later.
    function extensionVerify(): string { return root.verifyExtension() || "started" }
    // Sets the extension up, or undoes that; see enableExtension.
    function extensionEnable(): string { return root.enableExtension() || "started" }
    function extensionDisable(): string { return root.disableExtension() || "started" }
    // Restarts the tiles' browser so it loads the extension; see
    // restartBrowser. Answers like add.
    function restartBrowser(browser: string): string {
      return root.started(root.restartBrowser({ browser: browser || root.browser }))
    }
  }

  // The native host connects here, one connection per browser.
  SocketServer {
    active: true
    path: root.bridgePath
    handler: Socket {
      id: bridgeSocket
      property var info: null
      onConnectedChanged: connected ? root.bridgeOpened(bridgeSocket) : root.bridgeClosed(bridgeSocket)
      parser: SplitParser {
        onRead: function(line) { root.bridgeRead(bridgeSocket, line) }
      }
    }
  }

  Process {
    id: extensionProcess
    running: false
    stdout: StdioCollector { id: extensionStdout; waitForEnd: true }
    stderr: StdioCollector { id: extensionStderr; waitForEnd: true }
    onStarted: root.extensionStarted = true
    onRunningChanged: if (!running && !root.extensionStarted) {
      extensionTimeout.stop()
      root.extensionError = "Cannot run " + root.hostProgram
    }
    onExited: function(exitCode) { root.hostFinished(exitCode, extensionStdout.text, extensionStderr.text) }
  }

  Timer {
    id: extensionTimeout
    interval: 5000
    onTriggered: {
      extensionProcess.running = false
      root.extensionError = "The native host did not answer in time"
    }
  }

  // How long a verify waits for every extension to answer.
  Timer {
    id: verifyTimeout
    interval: 3000
    onTriggered: root.finishVerify()
  }

  SwapCard {
    id: swapCard
    service: root
  }

  // Coalesces the burst of events one window change produces.
  Timer {
    id: refreshTimer
    interval: 150
    onTriggered: {
      Hyprland.refreshToplevels()
      Hyprland.refreshMonitors()
      store.reload()
      if (!monitorsQuery.running) monitorsQuery.running = true
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
      // A config reload drops runtime binds, the swap key among them.
      if (name === "configreloaded") {
        root.boundSwapKey = ""
        keySync.restart()
      }
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

  // Coalesces setting changes; it also lets a previous service's unbind,
  // sent as it was destroyed on a plugin reload, land first.
  Timer {
    id: keySync
    interval: 500
    onTriggered: root.syncSwapKey()
  }

  Process {
    id: keyProcess
    running: false
    stdout: StdioCollector { id: keyStdout; waitForEnd: true }
    onExited: function(exitCode) {
      keyTimeout.stop()
      var then = root.keyThen
      root.keyThen = null
      if (then) then(String(keyStdout.text))
    }
  }

  Timer {
    id: keyTimeout
    interval: 5000
    onTriggered: {
      root.keyThen = null
      keyProcess.running = false
      root.swapKeyError = "Hyprland did not answer while binding the swap key"
    }
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

  // The list refreshes 150 ms after an action ends and rebuilds when
  // Hyprland's answer lands; this covers both.
  Timer {
    id: settleTimer
    interval: 500
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

  Process {
    id: monitorsQuery
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector { id: monitorsOut; waitForEnd: true }
    onExited: function(exitCode) {
      var parsed = exitCode === 0 ? Model.parseMonitors(monitorsOut.text) : null
      if (parsed) root.monitors = parsed
    }
  }

  // "mosaic 0.1.0", from the manifest.
  readonly property string versionText: {
    var manifest = Model.parseManifest(manifestFile.text())
    return manifest ? "mosaic " + manifest.version : "mosaic"
  }

  FileView {
    id: manifestFile
    path: Qt.resolvedUrl("manifest.json").toString().replace(/^file:\/\//, "")
    printErrors: false
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
