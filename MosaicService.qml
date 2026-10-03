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

  // Layouts (layouts.lua), set per workspace and saved in layouts.json
  // (Model.parseLayouts: { workspaces, custom, legacy }). Hyprland forgets
  // runtime layouts and rules on a config reload, so `layoutsApplied` says
  // whether the saved ones are in place; syncLayouts applies them.
  // `layoutError` is why the last attempt failed.
  property var layoutState: ({ workspaces: {}, custom: {}, legacy: {} })
  property bool layoutsRead: false
  property bool layoutsApplied: false
  // The Layouts tab's workspaces (Model.layoutWorkspaceRows).
  readonly property var layoutWorkspaces: {
    var values = Hyprland.workspaces.values
    var workspaces = []
    for (var i = 0; i < values.length; i++)
      workspaces.push({ id: values[i].id, monitor: values[i].monitor ? values[i].monitor.name : "", windows: workspaceWindows[values[i].id] || 0 })
    return Model.layoutWorkspaceRows(workspaces, layoutState)
  }
  // Windows per workspace ({ id: count }), kept by rebuild().
  property var workspaceWindows: ({})
  property string layoutError: ""
  property bool layoutSyncPending: false
  // The file's text as last read or written.
  property string layoutsText: ""
  // Tile states from just before a config reload ({ ADDRESS: state }). A
  // reload may reset contained tiles' records, so the next sync puts these
  // back instead of what the list reads by then.
  property var statesBeforeReload: null
  // What a running layout action saves once its steps succeed.
  property var pendingLayouts: null
  readonly property string layoutsPath: storePath.replace(/tiles\.json$/, "layouts.json")
  readonly property string layoutsLua: Model.layoutsLoadLua(Qt.resolvedUrl("layouts.lua").toString().replace(/^file:\/\//, ""))

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
  // Which tab each tile was matched to (Model.keepTabs), kept beside the
  // socket so a shell restart can tell apart tiles on one site.
  readonly property string tabsPath: bridgePath.replace(/\.sock$/, "") + "-tabs.json"
  property var savedTabs: ({})
  // The window Hyprland last focused, and a tile the extension could not
  // tell from another, focused, whose fresh report may pair it by focus.
  property string focusedWindow: ""
  property string focusProbe: ""
  property bool tabsLoaded: false
  // Open bridge connections, and the ones a verify still waits for.
  property var bridgeSockets: []
  property var pingWaiting: []
  property int pingId: 0
  property bool extensionStarted: false
  // Each found tile's audio (Model.tileAudio): { ADDRESS: { bridge, tab,
  // audible, muted } }.
  readonly property var tileAudio: Model.tileAudio(extensionCheck, bridges)
  // The volume the user set per tile (0 to 1, by address), shown until the
  // extension's report catches up; see keepVolumes.
  property var tileVolumes: ({})
  // When the user last set each tile's volume (ms), so a report sent
  // before that doesn't undo it.
  property var volumeSetAt: ({})
  // The widget's setting: mute every tile but the one last focused.
  property bool audioFollowsFocus: false
  // The tile focused last, tracked whether or not the mode is on, so
  // turning it on from the panel (which takes focus from no tile) keeps it.
  property string audioFocus: ""
  // The extension on disk: its version and worker script. A browser
  // running other code loads it on its next start; see extensionOutdated.
  readonly property var extensionOnDisk: Model.extensionFromManifest(extensionManifest.text())
  readonly property string extensionVersion: extensionOnDisk ? extensionOnDisk.version : ""
  readonly property bool extensionOutdated: extensionOnDisk !== null && bridges.some(function(bridge) {
    return bridge.script !== root.extensionOnDisk.script
  })

  onAudioFollowsFocusChanged: {
    if (audioFollowsFocus) {
      var focused = focusedTile()
      if (focused) audioFocus = focused.address
      applyAudioFocus()
    } else {
      // Leaving the mode unmutes every tile it muted.
      Object.keys(tileAudio).forEach(function(address) {
        if (root.tileAudio[address].muted) root.setTileMuted(address, false)
      })
    }
  }

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
    var counts = Model.windowCounts(clients)
    if (JSON.stringify(counts) !== JSON.stringify(workspaceWindows)) workspaceWindows = counts
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

  // `mosaic layout --workspace N NAME`: gives a workspace a layout (a
  // Model.layoutChoices entry, or a custom layout's name; "default" hands
  // it back), and saves the choice.
  function setWorkspaceLayout(workspace, name, label) {
    return startAction(label || "Setting the layout of workspace " + workspace, function(list) {
      return root.layoutPlan(Model.planWorkspaceLayout(list, root.layoutState, workspace, name,
        root.workspaceLayout(Number(workspace)), root.layoutsLua), false)
    })
  }

  // `mosaic layout --session NAME NAME`: the layout of the workspace the
  // session's tiles are on.
  function setSessionLayout(session, name, label) {
    return startAction(label || "Setting the layout of " + session, function(list) {
      var workspace = Model.sessionWorkspace(list, session)
      if (workspace === null) return { error: "Session " + session + " has no tiled tiles" }
      return root.layoutPlan(Model.planWorkspaceLayout(list, root.layoutState, workspace, name,
        root.workspaceLayout(workspace), root.layoutsLua), false)
    })
  }

  // Saves a custom layout (Model.normalizeCustom), new or replacing
  // `oldSlug`, and lays out again the workspaces that use it.
  function saveCustomLayout(oldSlug, def, label) {
    return startAction(label || "Saving layout " + (def && def.name ? def.name : ""), function(list) {
      return root.layoutPlan(Model.planSaveCustom(list, root.layoutState, oldSlug || "", def, root.layoutsLua), false)
    })
  }

  function deleteCustomLayout(slug, label) {
    return startAction(label || "Deleting layout " + slug, function(list) {
      return root.layoutPlan(Model.planDeleteCustom(list, root.layoutState, slug, root.layoutsLua), false)
    })
  }

  // Turns a layout plan into the action runner's plan; its state is kept
  // once the steps succeed (see finishLayouts).
  function layoutPlan(result, sync) {
    if (result.error) {
      if (sync) pendingLayouts = { state: layoutState, sync: true }
      return result
    }
    pendingLayouts = { state: result.state, sync: sync }
    return { error: "", expressions: result.expressions, message: result.message || "" }
  }

  // The layout choice of a workspace, or of the one a session is on.
  function workspaceChoice(workspace) {
    return Model.workspaceChoice(layoutState, workspace)
  }
  function sessionChoice(session) {
    var workspace = Model.sessionWorkspace(list, session)
    return workspace === null ? "default" : Model.workspaceChoice(layoutState, workspace)
  }

  // The tiled layout Hyprland reports for a workspace, or "".
  function workspaceLayout(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var ipc = values[i].lastIpcObject
      if (values[i].id === id && ipc) return String(ipc.tiledLayout || "")
    }
    return ""
  }

  // Applies every saved layout once the file is read: at start and after
  // a config reload. Version 1's session layouts wait for their tiles to
  // be listed, to learn their workspaces. Waits for a running action.
  function syncLayouts() {
    if (layoutsApplied || !layoutsRead) return
    if (Object.keys(layoutState.legacy).length > 0 && list.sessions.length === 0) return
    if (busy) {
      layoutSyncPending = true
      return
    }
    layoutSyncPending = false
    var states = statesBeforeReload
    statesBeforeReload = null
    startAction("Applying layouts", function(fresh) {
      return root.layoutPlan(Model.planSyncLayouts(fresh, root.layoutState, root.layoutsLua, states), true)
    })
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

  // `mosaic replace TILE TARGET`: puts TARGET (a URL or web app) in the
  // tile's place. When the browser extension has found the tile, its page
  // just changes in place (see navigateTile). Otherwise a new window opens,
  // joins the old tile's session and workspace, takes its store position,
  // and is swapped into its slot before the old window closes, so the
  // layout doesn't shift. `options` may hold `browser`, as for add.
  function replace(tile, target, options, label) {
    if (busy) return "Still busy: " + busyLabel
    var resolved = Model.resolveAddTargets([target], Model.shapeWebapps(webapps).apps)
    if (resolved.error) return resolved.error
    var planned = Model.planReplace(list, tile)
    if (!planned.error && canNavigate(planned.tile.address))
      return navigateTile(planned.tile, resolved.urls[0], label || "Replacing tile " + tile + " with " + target)
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

  // Whether a replace of this tile changes its page in place: the
  // extension has found its tab and can navigate it.
  function canNavigate(address) {
    var entry = tileAudio[address]
    var bridge = entry ? bridges[entry.bridge] : null
    return !!bridge && Model.bridgeHas(bridge, "navigate")
  }

  // A replace in place: the extension loads `url` in the tile's own tab,
  // so the window, its slot, containment, and volume all stay, and nothing
  // opens or moves. Only the store record's URL changes. The swap veil
  // covers the tile until the new page is in.
  function navigateTile(tile, url, label) {
    var error = tileCommand(tile.address, "navigate", { url: url })
    if (error) return error
    swapVeil.show(tile, url)
    begin(label)
    pendingMessage = "Replaced tile " + tile.index + " with " + url + "."
    records = Model.replaceRecord(records, tile.address, { address: tile.address, session: tile.session, url: url })
    rebuild()
    phase = "add-save"
    afterQueue = function() { root.finishAction("") }
    actionTimeout.interval = 5000
    actionTimeout.restart()
    store.setText(Model.serializeStore(records))
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
    // Loading the layouts may complain about names an older load
    // registered, and hyprctl then exits non-zero; see Model.layoutsLoaded.
    if (phase === "dispatch" && stepProcess.command[1] === "eval" && stepProcess.command[2] === layoutsLua) {
      if (!Model.layoutsLoaded(text + "\n" + String(errors)))
        return finishAction("Cannot load the layouts: " + (text + " " + String(errors)).trim())
      return runQueue(pendingQueue, afterQueue)
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

  // Runs Hyprland dispatches in order, then `then()`. A step is a dispatch
  // expression, or { eval } for Lua that is not a dispatcher, such as a
  // workspace rule.
  function runQueue(expressions, then) {
    if (expressions.length === 0) return then()
    pendingQueue = expressions.slice(1)
    afterQueue = then
    phase = "dispatch"
    var step = expressions[0]
    runStep(typeof step === "string" ? ["hyprctl", "dispatch", step] : ["hyprctl", "eval", step.eval])
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
    if (pendingLayouts) finishLayouts(error)
    refresh()
    var kept = {}
    for (var n = job - 19; n < job; n++) if (results[n]) kept[n] = results[n]
    kept[job] = { error: error, message: error ? "" : pendingMessage }
    results = kept
    settleTimer.restart()
    actionFinished(label, error, error ? "" : pendingMessage)
    if (layoutSyncPending) layoutSync.restart()
  }

  // Keeps what a layout action changed once it succeeded. A sync counts as
  // done even when it failed, so it isn't retried in a loop; layoutError
  // says why.
  function finishLayouts(error) {
    var done = pendingLayouts
    pendingLayouts = null
    if (done.sync) {
      layoutsApplied = true
      layoutError = error
    } else if (!error) {
      layoutError = ""
    }
    if (error) return
    var text = Model.serializeLayouts(done.state)
    layoutState = done.state
    if (text !== layoutsText) {
      layoutsText = text
      layoutsFile.setText(text)
    }
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
    var focused = focusedTile()
    if (focused) audioFocus = focused.address
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

  // The tabs tiles were matched to before, for Model.matchTiles.
  function knownTabs() {
    return Object.assign({}, savedTabs, extensionCheck && extensionCheck.tiles ? extensionCheck.tiles : {})
  }

  onExtensionCheckChanged: {
    if (!tabsLoaded || !extensionCheck || !extensionCheck.tiles) return
    var kept = Model.keepTabs(savedTabs, extensionCheck, Model.listTiles(list).map(function(tile) { return tile.address }))
    if (JSON.stringify(kept) === JSON.stringify(savedTabs)) return
    savedTabs = kept
    tabsFile.setText(JSON.stringify(kept))
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
    var probe = focusProbe !== "" && focusProbe === focusedWindow ? focusProbe : ""
    focusProbe = ""
    extensionCheck = Model.matchTiles(Model.shapeList(list).tiles, bridges, knownTabs(), probe)
  }

  function bridgeOpened(socket) {
    socket.info = { browser: "", extension: "", script: "", features: null, windows: [], hello: false }
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
      // The worker script's name, which says what code actually runs.
      info.script = String(message.script || "")
      info.features = Array.isArray(message.features) ? message.features.map(String) : null
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
      return { browser: socket.info.browser, extension: socket.info.extension, script: socket.info.script,
        features: socket.info.features, windows: socket.info.windows }
    })
    autoCheck()
  }

  // Keeps extensionCheck current without a verify: the extension reports
  // its windows whenever they change, so matching again on every change of
  // them or of the tiles is enough. Without a connection there is nothing
  // to check.
  function autoCheck() {
    if (verifying) return
    extensionCheck = bridges.length > 0 ? Model.matchTiles(Model.shapeList(list).tiles, bridges, knownTabs()) : null
    applyAudioFocus()
    keepVolumes()
  }

  // Forgets volumes of tiles that are gone, follows the levels an up to
  // date extension reports, and sets them again where an older one lost
  // them (see Model.reconcileVolumes).
  function keepVolumes() {
    var audio = Model.tileAudio(extensionCheck, bridges)
    var now = Date.now()
    var result = Model.reconcileVolumes(tileVolumes, audio,
      Model.listTiles(list).map(function(tile) { return tile.address }),
      function(index) { return root.bridges[index] ? Model.bridgeHas(root.bridges[index], "follow") : false },
      function(address) { return now - (root.volumeSetAt[address] || 0) < 3000 })
    result.resend.forEach(function(address) { root.tileCommand(address, "volume", { level: result.volumes[address] }) })
    if (JSON.stringify(result.volumes) !== JSON.stringify(tileVolumes)) tileVolumes = result.volumes
  }

  // Sends a command for a tile's tab to its extension, if that extension
  // can do `feature`. Returns "" once sent, else why not.
  function tileCommand(address, feature, message) {
    var entry = tileAudio[address]
    if (!entry) return extensionState === "connected" ? "The browser extension has not found this tile" : "This needs the browser extension; see the Extension tab"
    var bridge = bridges[entry.bridge]
    if (!bridge || !Model.bridgeHas(bridge, feature))
      return "Restart the browser to load the updated extension (B on the Extension tab)"
    var sent = Object.assign({ type: feature, tab: entry.tab }, message)
    return sendBridge(entry.bridge, sent) ? "" : "The browser extension is not connected"
  }

  // Sets a tile's volume, from 0 to 1 in whole percent; 1 hands it back
  // to the site.
  function setTileVolume(address, level) {
    var clamped = Math.max(0, Math.min(1, Math.round(Number(level) * 100) / 100))
    var error = tileCommand(address, "volume", { level: clamped })
    if (error) return error
    // 1 is kept too, so the panel shows it at once instead of a report
    // that is still on its way.
    var next = Object.assign({}, tileVolumes)
    next[address] = clamped
    volumeSetAt[address] = Date.now()
    tileVolumes = next
    return ""
  }

  function tileVolume(address) {
    return tileVolumes[address] !== undefined ? tileVolumes[address] : 1
  }

  function stepTileVolume(address, delta) {
    return setTileVolume(address, Model.stepVolume(tileVolume(address), delta))
  }

  function helloSockets() {
    return bridgeSockets.filter(function(socket) { return socket.info.hello })
  }

  function sendBridge(index, message) {
    var socket = helloSockets()[index]
    if (!socket) return false
    socket.write(JSON.stringify(message) + "\n")
    socket.flush()
    return true
  }

  // Mutes or unmutes a tile (its address); "" once sent, else why not.
  // The tile's new state arrives with the extension's next windows report.
  function setTileMuted(address, muted) {
    return tileCommand(address, "mute", { muted: muted === true })
  }

  function toggleTileMute(address) {
    var entry = tileAudio[address]
    return setTileMuted(address, entry ? !entry.muted : true)
  }

  // In focus mode, leaves only the last focused tile unmuted.
  function applyAudioFocus() {
    if (!audioFollowsFocus || audioFocus === "") return
    Model.focusMutes(Model.tileAudio(extensionCheck, bridges), audioFocus).forEach(function(change) {
      root.sendBridge(change.bridge, { type: "mute", tab: change.tab, muted: change.muted })
    })
  }

  // activewindowv2: a tile that takes focus becomes the audible one. Other
  // windows leave the audio as it is.
  function windowFocused(data) {
    var address = "0x" + String(data).trim()
    focusedWindow = address
    var isTile = Model.listTiles(list).some(function(tile) { return tile.address === address })
    if (isTile && bridges.length > 0 && extensionCheck && extensionCheck.tiles && !extensionCheck.tiles[address]) {
      focusProbe = address
      focusProbeTimer.restart()
    }
    if (address === audioFocus || !isTile) return
    audioFocus = address
    applyAudioFocus()
  }

  onListChanged: {
    autoCheck()
    layoutSync.restart()
  }

  // The extension's state for scripts: `omarchy-shell pym.mosaic extension`.
  function extensionStatus() {
    return JSON.stringify({
      state: extensionState,
      error: extensionError,
      setup: extensionSetup,
      bridges: bridges.map(function(bridge) {
        return { browser: Model.browserLabel(bridge.browser), extension: bridge.extension, script: bridge.script,
          features: bridge.features, windows: bridge.windows.length }
      }),
      check: extensionCheck,
      audio: tileAudio,
      audioFollowsFocus: audioFollowsFocus
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
    // `mosaic layout --workspace N LAYOUT`.
    function layout(workspace: string, name: string): string { return root.started(root.setWorkspaceLayout(workspace, name)) }
    // `mosaic layout --session NAME LAYOUT`.
    function sessionLayout(session: string, name: string): string { return root.started(root.setSessionLayout(session, name)) }
    // `mosaic layout`: workspaces with a layout, and custom layouts.
    function layouts(): string { return Model.layoutsText(root.layoutState) }
    // Saves a custom layout from JSON (see Model.normalizeCustom), replacing
    // the one called `slug` if given.
    function layoutSave(slug: string, definition: string): string {
      var def
      try {
        def = JSON.parse(definition)
      } catch (error) {
        return "error: The layout must be JSON"
      }
      return root.started(root.saveCustomLayout(slug, def))
    }
    function layoutDelete(slug: string): string { return root.started(root.deleteCustomLayout(slug)) }

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
    // Mutes TILE (a list number or address): "on", "off", or "toggle".
    // Sets TILE's volume: a percentage ("40"), or a step ("+10", "-10").
    function volume(tile: string, level: string): string {
      var found = Model.findTile(Model.listTiles(root.list), tile)
      if (!found) return "error: No tile " + tile
      var parsed = Model.parseVolume(level, root.tileVolume(found.address))
      if (parsed === null) return "error: Use a percentage such as 40, or a step such as +10"
      var error = root.setTileVolume(found.address, parsed)
      return error ? "error: " + error : Math.round(parsed * 100) + "%"
    }
    // Plays or pauses TILE's media: "play", "pause", or "toggle".
    function media(tile: string, action: string): string {
      var found = Model.findTile(Model.listTiles(root.list), tile)
      if (!found) return "error: No tile " + tile
      if (action !== "play" && action !== "pause" && action !== "toggle") return "error: Use play, pause, or toggle"
      var error = root.tileCommand(found.address, "media", { action: action })
      return error ? "error: " + error : "ok"
    }
    // Reloads TILE's page in place.
    function reloadTile(tile: string): string {
      var found = Model.findTile(Model.listTiles(root.list), tile)
      if (!found) return "error: No tile " + tile
      var error = root.tileCommand(found.address, "reload", {})
      return error ? "error: " + error : "ok"
    }
    function mute(tile: string, state: string): string {
      var found = Model.findTile(Model.listTiles(root.list), tile)
      if (!found) return "error: No tile " + tile
      if (state !== "on" && state !== "off" && state !== "toggle") return "error: Use on, off, or toggle"
      var error = state === "toggle" ? root.toggleTileMute(found.address) : root.setTileMuted(found.address, state === "on")
      return error ? "error: " + error : "ok"
    }
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
  // Gives the browser a moment to see the focus before asking it.
  Timer {
    id: focusProbeTimer
    interval: 300
    onTriggered: if (root.focusProbe === root.focusedWindow) root.verifyExtension()
  }

  Timer {
    id: verifyTimeout
    interval: 3000
    onTriggered: root.finishVerify()
  }

  FileView {
    id: tabsFile
    path: root.tabsPath
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.savedTabs = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({})
      } catch (error) {
        root.savedTabs = ({})
      }
      root.tabsLoaded = true
      root.autoCheck()
    }
    onLoadFailed: {
      root.tabsLoaded = true
      root.autoCheck()
    }
  }

  // Covers a tile while a swap in place loads its new page.
  SwapVeil {
    id: swapVeil
    service: root
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
      if (name === "activewindowv2") root.windowFocused(event.data)
      // A config reload drops runtime binds, the swap key among them.
      // It drops runtime layouts and workspace rules too.
      if (name === "configreloaded") {
        root.layoutsApplied = false
        root.statesBeforeReload = Model.tileStates(root.list)
        layoutSync.restart()
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

  // Lets the list settle before checking where layouts belong.
  Timer {
    id: layoutSync
    interval: 300
    onTriggered: root.syncLayouts()
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
    id: extensionManifest
    path: Qt.resolvedUrl("extension/manifest.json").toString().replace(/^file:\/\//, "")
    printErrors: false
  }

  FileView {
    id: manifestFile
    path: Qt.resolvedUrl("manifest.json").toString().replace(/^file:\/\//, "")
    printErrors: false
  }

  FileView {
    id: layoutsFile
    path: root.layoutsPath
    printErrors: false
    onLoaded: {
      root.layoutsText = text()
      root.layoutState = Model.parseLayouts(root.layoutsText)
      root.layoutsRead = true
      layoutSync.restart()
    }
    onLoadFailed: {
      root.layoutsRead = true
      layoutSync.restart()
    }
    onSaveFailed: function(error) { root.layoutError = "Cannot write " + root.layoutsPath + ": " + error }
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
