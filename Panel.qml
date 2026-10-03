import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget for omarchy-mosaic. The tile list and the web apps come from
// the plugin's service (MosaicService.qml), which also does every action, so
// this widget holds no session state of its own.
Panel {
  id: root
  moduleName: "pym.mosaic"
  manageIpc: false

  // The plugin's MosaicService. The shell rebuilds it on every plugin
  // reload, and this typed property resets to null when it is destroyed.
  property QtObject service: null
  readonly property var listing: service ? Model.shapeList(service.list)
    : { sessions: [], tiles: [], error: "The Mosaic service is not running. Reload the shell's plugins or restart the shell." }
  readonly property var sessions: listing.sessions
  readonly property var tiles: listing.tiles
  readonly property string listError: listing.error
  readonly property var webapps: service ? Model.shapeWebapps(service.webapps).apps : []
  // The web apps that get a button; hidden ones can still be typed.
  readonly property var shownWebapps: Model.visibleWebapps(webapps, setting("hiddenWebapps", ""))
  readonly property var hiddenRows: Model.hiddenEntries(webapps, setting("hiddenWebapps", ""))
  // The panel's tab: "tiles", "hidden" for the hidden web apps, or
  // "extension" for the browser extension's setup and health.
  property string view: "tiles"
  readonly property var views: ["tiles", "hidden", "layouts", "extension"]
  // The Layouts tab: workspaces and custom layouts from the service, and
  // the editor (see openEditor), or null.
  readonly property var layoutCustom: service ? service.layoutState.custom : ({})
  readonly property var allWorkspaceRows: service ? service.layoutWorkspaces : []
  // Empty workspaces without a layout of their own hide until W, except
  // the focused one.
  property bool showAllWorkspaces: false
  readonly property var usedWorkspaceRows: Model.shownWorkspaceRows(allWorkspaceRows, false,
    Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0)
  readonly property var workspaceRows: showAllWorkspaces ? allWorkspaceRows : usedWorkspaceRows
  readonly property int hiddenWorkspaces: allWorkspaceRows.length - usedWorkspaceRows.length
  readonly property var customRows: Model.customRows(layoutCustom)
  property var layoutEditor: null
  // The custom layout the next D deletes, and the save the editor waits for.
  property string confirmDelete: ""
  property string savingLayout: ""
  property int editorPresetAt: 0
  property bool largeEditor: false
  property bool returningFromLarge: false
  // A layout dropdown's list is open, and takes the keys.
  property bool dropdownOpen: false
  // The browser extension, which audio control needs.
  readonly property string extensionState: service ? service.extensionState : "unknown"
  readonly property bool extensionMissing: extensionState === "off" || extensionState === "restart"
  // The browser has to restart to load the extension, or a newer one.
  readonly property bool restartNeeded: extensionState === "restart" || (service !== null && service.extensionOutdated)
  // Each found tile's audio, by address (Model.tileAudio).
  readonly property var tileAudio: service ? service.tileAudio : ({})
  // The audioFollowsFocus setting: mute every tile but the focused one.
  readonly property bool audioFollowsFocus: setting("audioFollowsFocus", false) === true
  // The autoContain setting: keep fullscreen in every tile, re-containing
  // tiles that lose it; the service does the work.
  readonly property bool autoContain: setting("autoContain", false) === true
  // Audio controls show on the Tiles tab once the extension is connected
  // and a tile is open.
  readonly property bool audioReady: extensionState === "connected" && tiles.length > 0
  property bool confirmRestart: false
  // Swap mode: the tile ({ address, label }) that the next web app or
  // address replaces, or null.
  property var swapTile: null
  // The Add tile section is open (A); it is always open without tiles.
  property bool adding: false
  readonly property bool addOpen: swapTile === null && (adding || tiles.length === 0)
  // The key bar shows every key (?), not only the main ones.
  property bool allKeys: false
  readonly property string keyContext: view === "extension"
    ? (restartNeeded ? "extension-restart" : extensionState === "connected" ? "extension" : "extension-off")
    : view === "layouts" ? (layoutEditor ? "editor" : "layouts")
    : view === "hidden" ? "hidden"
    : swapTile ? "swap" : addOpen && tiles.length > 0 ? "adding" : "tiles"
  // The address field on the tile being swapped, while it shows.
  property var swapField: null
  property string status: ""
  property bool statusIsError: false
  // What the service is doing right now.
  readonly property string activity: service && service.busy ? service.busyLabel : ""
  property int cursor: 0
  property bool cursorActive: false
  // "Mosaic 0.1.0", from the manifest.
  readonly property string versionText: {
    var manifest = Model.parseManifest(manifestFile.text())
    return manifest ? manifest.name + " " + manifest.version : ""
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // The browser setting: a Chromium-family command used instead of the
  // default browser, or "".
  readonly property string browser: {
    var value = String(setting("browser", "")).trim()
    return value.indexOf("~/") === 0 ? Quickshell.env("HOME") + value.slice(1) : value
  }
  // The swapKey setting, which the service binds in Hyprland.
  readonly property string swapKey: String(setting("swapKey", Model.DEFAULT_SWAP_KEY))
  readonly property int cursorCount: view === "tiles" ? tiles.length : view === "hidden" ? hiddenRows.length
    : view === "layouts" && !layoutEditor ? workspaceRows.length + customRows.length : 0
  readonly property var selectedTile: view === "tiles" && cursor >= 0 && cursor < tiles.length ? tiles[cursor] : null
  readonly property var selectedHidden: view === "hidden" && cursor >= 0 && cursor < hiddenRows.length ? hiddenRows[cursor] : null
  readonly property var selectedWorkspace: view === "layouts" && !layoutEditor && cursor >= 0 && cursor < workspaceRows.length ? workspaceRows[cursor] : null
  readonly property var selectedCustom: view === "layouts" && !layoutEditor && cursor >= workspaceRows.length
    && cursor < workspaceRows.length + customRows.length ? customRows[cursor - workspaceRows.length] : null
  readonly property bool editing: urlField.activeFocus || sessionField.activeFocus || (swapField !== null && swapField.activeFocus) || layoutNameField.activeFocus || dropdownOpen

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: findService()
  onBarChanged: findService()
  onCursorCountChanged: cursor = Math.max(0, Math.min(cursor, cursorCount - 1))
  onOpenedChanged: {
    if (opened) {
      // Back from the large editor, the panel's editor carries on.
      var back = returningFromLarge
      returningFromLarge = false
      if (!back) status = ""
      confirmRestart = false
      swapTile = null
      if (!back) layoutEditor = null
      confirmDelete = ""
      view = back ? "layouts" : "tiles"
      if (back && layoutEditor) layoutNameField.text = layoutEditor.def.name
      cursor = 0
      cursorActive = false
      refresh()
      if (service) service.refreshExtension()
    }
  }

  function findService() {
    if (service) return
    var shell = bar ? bar.shell : null
    service = shell && typeof shell.serviceFor === "function" ? shell.serviceFor(moduleName) : null
    if (service) service.panel = root
  }

  function refresh() {
    if (service) service.refresh()
  }

  function iconSource(icon) {
    if (!icon) return ""
    if (icon.indexOf("/") === 0) return "file://" + icon
    return Quickshell.iconPath(icon, true)
  }

  // Runs a service action, such as `service.focus`, and shows why it could
  // not start. The service reports how it ended with actionFinished.
  function runService(start) {
    if (!service) {
      showStatus(listing.error, true)
      return
    }
    status = ""
    var error = start(service)
    if (error) showStatus(error, true)
  }

  function contain() {
    runService(function(engine) { return engine.contain("") })
  }

  function showStatus(text, isError) {
    status = text
    statusIsError = isError
  }

  // The session typed in the field, else the selected tile's, else default.
  function targetSessionText() {
    if (sessionField.text.trim() !== "") return sessionField.text
    return selectedTile ? selectedTile.session : ""
  }

  function addUrl(url, label) {
    if (swapTile) {
      var old = swapTile
      swapTile = null
      runService(function(engine) {
        return engine.replace(old.address, url, { browser: root.browser }, "Replacing " + old.label + " with " + label)
      })
      return true
    }
    var session = Model.sessionName(targetSessionText())
    if (session === "") {
      showStatus("Session names use lowercase letters, digits, - and _", true)
      return false
    }
    runService(function(engine) {
      return engine.add([url], { session: session, browser: root.browser }, "Adding " + label + " to " + session)
    })
    return true
  }

  function addTile() {
    var url = Model.resolveTarget(urlField.text, webapps)
    if (url === "") {
      showStatus("Enter a web address or web app name, such as twitch.tv/name", true)
      return
    }
    if (addUrl(url, urlField.text.trim())) {
      urlField.text = ""
      adding = false
      keyCatcher.forceActiveFocus()
    }
  }

  function addWebapp(app) {
    if (app) addUrl(app.url, app.name)
  }

  function leaveField() {
    keyCatcher.forceActiveFocus()
  }

  // Enter in the swap field: a web app's name or an address.
  function swapToAddress(text) {
    var url = Model.resolveTarget(text, webapps)
    if (url === "") {
      showStatus("Enter a web address or web app name, such as twitch.tv/name", true)
      return
    }
    keyCatcher.forceActiveFocus()
    addUrl(url, text.trim())
  }

  // Saves one widget setting; the shell writes it to shell.json.
  function saveSetting(key, value) {
    var shell = bar ? bar.shell : null
    if (!shell || typeof shell.updateEntryInline !== "function") {
      showStatus("Cannot save settings here", true)
      return false
    }
    var changed = {}
    changed[key] = value
    settings = Object.assign({}, settings, changed)
    shell.updateEntryInline(moduleName, settings)
    return true
  }

  function saveHidden(text) {
    return saveSetting("hiddenWebapps", text)
  }

  function toggleMute(tile) {
    if (!tile) return
    runService(function(engine) { return engine.toggleTileMute(tile.address) })
  }

  // Slider drags arrive many times a second; send the latest level at most
  // every 80 ms.
  property var pendingVolume: null

  // `now` sends at once, as on release, so the last position never waits.
  function dragVolume(tile, level, now) {
    if (!tile) return
    pendingVolume = { address: tile.address, level: level }
    if (now) {
      volumeThrottle.stop()
      sendPendingVolume()
    } else if (!volumeThrottle.running) {
      sendPendingVolume()
      volumeThrottle.start()
    }
  }

  function sendPendingVolume() {
    var pending = pendingVolume
    pendingVolume = null
    if (pending) runService(function(engine) { return engine.setTileVolume(pending.address, pending.level) })
  }

  function stepVolume(tile, delta) {
    if (!tile) return
    runService(function(engine) { return engine.stepTileVolume(tile.address, delta) })
  }

  function toggleAudioFocus() {
    saveSetting("audioFollowsFocus", !audioFollowsFocus)
  }

  function toggleAutoContain() {
    saveSetting("autoContain", !autoContain)
  }

  function hideWebapp(app) {
    if (app && saveHidden(Model.hideWebapp(setting("hiddenWebapps", ""), app)))
      showStatus("Hid " + app.name + ". The Hidden tab (L) brings it back.", false)
  }

  function showHidden(entry) {
    if (entry && saveHidden(Model.showWebapp(setting("hiddenWebapps", ""), entry)))
      showStatus(entry.app ? entry.app.name + " is back on the Tiles tab." : "Removed " + entry.label + " from the hidden list.", false)
  }

  function setView(name) {
    if (view === name) return
    if (name !== "tiles") swapTile = null
    layoutEditor = null
    confirmDelete = ""
    adding = false
    status = ""
    view = name
    cursor = 0
    cursorActive = false
  }

  function stepView(delta) {
    var next = views.indexOf(view) + delta
    if (next >= 0 && next < views.length) setView(views[next])
  }

  function enableExtension() {
    runService(function(engine) { return engine.enableExtension() })
  }

  function disableExtension() {
    runService(function(engine) { return engine.disableExtension() })
  }

  function verifyExtension() {
    runService(function(engine) { return engine.verifyExtension() })
  }

  // Restarting closes every window of the browser, so the first press only
  // asks; a second press within a few seconds restarts it.
  function restartBrowser() {
    if (!confirmRestart) {
      confirmRestart = true
      restartConfirmTimer.restart()
      return
    }
    confirmRestart = false
    runService(function(engine) { return engine.restartBrowser({ browser: root.browser }, "Restarting the browser") })
  }

  function copyExtensionPath() {
    if (!service) return
    Quickshell.execDetached(["wl-copy", service.extensionDir])
    showStatus("Copied " + service.extensionDir, false)
  }

  function startAdding() {
    if (swapTile && swapField) {
      swapField.forceActiveFocus()
      swapField.selectAll()
      return
    }
    setView("tiles")
    adding = true
    if (selectedTile && sessionField.text === "") sessionField.text = selectedTile.session
    Qt.callLater(function() { urlField.forceActiveFocus() })
  }

  // Enters swap mode for `tile`: the web app buttons, 1–9, and the address
  // field then replace it instead of adding a tile.
  function startSwap(tile) {
    if (!tile) return
    setView("tiles")
    cursorActive = true
    cursor = tile.position
    swapTile = { address: tile.address, label: Model.tileLabel(tile), url: tile.url || "" }
    status = ""
  }

  function focusTile(tile) {
    if (!tile) return
    runService(function(engine) { return engine.focus(tile.address, "Focusing " + Model.tileLabel(tile)) })
  }

  function removeTile(tile) {
    if (!tile) return
    runService(function(engine) { return engine.remove([tile.address], "Removing " + Model.tileLabel(tile)) })
  }

  function closeSession(name) {
    runService(function(engine) { return engine.close(name) })
  }

  // Gives a session the next layout in Model.LAYOUT_CHOICES.
  // Gives the workspace a session is on the next layout in
  // Model.layoutChoices.
  function cycleLayout(name) {
    runService(function(engine) {
      var next = Model.nextLayout(engine.sessionChoice(name), root.layoutCustom)
      return engine.setSessionLayout(name, next, "Layout of " + name + ": " + Model.layoutLabel(next, root.layoutCustom))
    })
  }

  function layoutOf(name) {
    return service ? service.sessionChoice(name) : "default"
  }

  // Width over height of the monitor named `name`, as it is turned.
  function monitorAspect(name) {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === name && screens[i].height > 0) return screens[i].width / screens[i].height
    }
    return 16 / 9
  }

  function setWorkspaceLayout(row, choice) {
    if (!row) return
    runService(function(engine) {
      return engine.setWorkspaceLayout(row.id, choice, "Workspace " + row.id + ": " + Model.layoutLabel(choice, root.layoutCustom))
    })
  }

  function cycleWorkspaceLayout(row) {
    if (row) setWorkspaceLayout(row, Model.nextLayout(row.choice, layoutCustom))
  }

  // The layout editor: { oldSlug ("" for a new one), def, zone (0-based,
  // visual order) }.
  function newLayout() {
    editorPresetAt = 0
    openEditor("", Model.newCustom(Model.freeLayoutName(layoutCustom), "columns"), 1)
  }

  function editLayout(row) {
    if (row) openEditor(row.slug, JSON.parse(JSON.stringify(row.def)), row.def.main - 1)
  }

  function openEditor(oldSlug, def, zone) {
    setView("layouts")
    confirmDelete = ""
    status = ""
    layoutEditor = { oldSlug: oldSlug, def: def, zone: zone }
    layoutNameField.text = def.name
  }

  function editorChange(def, zone) {
    if (!layoutEditor) return
    var count = Model.zoneCount(def)
    var at = zone === undefined ? layoutEditor.zone : zone
    layoutEditor = { oldSlug: layoutEditor.oldSlug, def: def, zone: Math.max(0, Math.min(count - 1, at)) }
  }

  function editorName(text) {
    if (layoutEditor && text !== layoutEditor.def.name) editorChange(Model.withName(layoutEditor.def, text))
  }

  // The large editor: the same editor over the focused monitor, at its
  // shape, for layouts with small zones. The panel closes meanwhile.
  function openLargeEditor() {
    if (!layoutEditor) return
    largeEditor = true
    close()
    largeNameField.text = layoutEditor.def.name
    Qt.callLater(function() { largeKeys.forceActiveFocus() })
  }

  // Back to the panel's editor, with the changes so far.
  function closeLargeEditor() {
    largeEditor = false
    returningFromLarge = layoutEditor !== null
    open()
  }

  // −/+: grows or shrinks the selected zone within its split.
  function editorSize(delta) {
    editorChange(Model.withZoneSize(layoutEditor.def, layoutEditor.zone, delta * Model.SIZE_STEP))
  }

  // Splits a zone: "row" puts a new zone beside it, "column" below it. The
  // new zone is selected.
  function editorSplit(zone, direction) {
    var def = Model.withSplit(layoutEditor.def, zone, direction)
    if (def === layoutEditor.def) return showStatus("That zone is too small to split, or the layout is full", true)
    status = ""
    editorChange(def, zone + 1)
  }

  function editorRemove(zone) {
    if (Model.zoneCount(layoutEditor.def) <= 1) return showStatus("A layout needs at least one zone", true)
    editorChange(Model.withoutZone(layoutEditor.def, zone), Math.max(0, zone - 1))
  }

  function editorMain(zone) {
    editorChange(Model.withMain(layoutEditor.def, zone), zone)
  }

  // Starts over from a preset (Model.PRESETS); T cycles them.
  function editorPreset(preset) {
    editorPresetAt = Model.PRESETS.indexOf(preset)
    editorChange(Model.withPreset(layoutEditor.def, preset), 0)
  }

  function editorNextPreset() {
    editorPreset(Model.PRESETS[(editorPresetAt + 1) % Model.PRESETS.length])
  }

  // Moves a line between zones (see Model.zoneDividers) to `position`, a
  // fraction of the preview along the line's split.
  function editorDivider(line, position) {
    editorChange(Model.withDivider(layoutEditor.def, line.path, line.index, position, line.from, line.span))
  }

  function saveLayout() {
    if (!layoutEditor) return
    var def = Model.withName(layoutEditor.def, layoutEditor.def.name.trim())
    if (!Model.normalizeCustom(def)) {
      showStatus("Give the layout a name", true)
      return
    }
    var label = "Saving layout " + def.name
    savingLayout = label
    var editor = layoutEditor
    runService(function(engine) { return engine.saveCustomLayout(editor.oldSlug, def, label) })
  }

  function deleteLayout(row) {
    if (!row) return
    if (confirmDelete !== row.slug) {
      confirmDelete = row.slug
      showStatus("Press D again to delete " + row.def.name + ". Workspaces using it get their own layout back.", false)
      return
    }
    confirmDelete = ""
    runService(function(engine) { return engine.deleteCustomLayout(row.slug, "Deleting layout " + row.def.name) })
  }

  // Keys on the Layouts tab; true when handled.
  function layoutKey(t) {
    var key = t.toLowerCase()
    if (layoutEditor) {
      var zone = layoutEditor.zone
      if (t === "-") editorSize(-1)
      else if (t === "+" || t === "=") editorSize(1)
      else if (key === "s") editorSplit(zone, "row")
      else if (key === "b") editorSplit(zone, "column")
      else if (key === "m") editorMain(zone)
      else if (key === "t") editorNextPreset()
      else if (key === "n") (largeEditor ? largeNameField : layoutNameField).forceActiveFocus()
      else if (key === "f" && !largeEditor) openLargeEditor()
      else return false
      return true
    }
    if (key === "n") newLayout()
    else if (key === "e" && cursorActive) editLayout(selectedCustom)
    else if (key === "d" && cursorActive) deleteLayout(selectedCustom)
    else if (key === "g" && cursorActive) cycleWorkspaceLayout(selectedWorkspace)
    else if (t === "0" && cursorActive) setWorkspaceLayout(selectedWorkspace, "default")
    else if (key === "w" && (showAllWorkspaces || hiddenWorkspaces > 0)) showAllWorkspaces = !showAllWorkspaces
    else return false
    return true
  }

  function moveCursor(delta) {
    if (cursorCount === 0) return
    cursorActive = true
    cursor = Math.max(0, Math.min(cursorCount - 1, cursor + delta))
  }

  // The shell may create the service after this widget, and rebuilds it on
  // every plugin reload, so look again while it is missing.
  Timer {
    interval: 500
    repeat: true
    running: root.service === null
    onTriggered: root.findService()
  }

  Binding {
    target: root.service
    property: "swapKey"
    value: root.swapKey
    when: root.service !== null
  }

  // The swap card, which the service draws, uses these settings too.
  Binding {
    target: root.service
    property: "browser"
    value: root.browser
    when: root.service !== null
  }

  Binding {
    target: root.service
    property: "audioFollowsFocus"
    value: root.audioFollowsFocus
    when: root.service !== null
  }

  Binding {
    target: root.service
    property: "autoContain"
    value: root.autoContain
    when: root.service !== null
  }

  Binding {
    target: root.service
    property: "hiddenWebapps"
    value: String(root.setting("hiddenWebapps", ""))
    when: root.service !== null
  }

  Timer {
    id: volumeThrottle
    interval: 80
    onTriggered: root.sendPendingVolume()
  }

  Timer {
    id: restartConfirmTimer
    interval: 4000
    onTriggered: root.confirmRestart = false
  }

  FileView {
    id: manifestFile
    path: Qt.resolvedUrl("manifest.json").toString().replace(/^file:\/\//, "")
    printErrors: false
  }

  Connections {
    target: root.service
    function onActionFinished(label, error, message) {
      if (error) root.showStatus(error, true)
      // A saved layout closes the editor; a failed save keeps it open.
      if (label === root.savingLayout) {
        root.savingLayout = ""
        if (!error) {
          root.layoutEditor = null
          root.largeEditor = false
          root.showStatus(message, false)
        }
      }
    }
  }

  BarIconButton {
    id: button
    bar: root.bar
    text: "󰕰"
    dimmed: root.tiles.length === 0
    tooltipText: root.listError !== "" ? "Mosaic · " + root.listError : "Mosaic · " + Model.summary(root.sessions, root.tiles)
    Accessible.role: Accessible.Button
    Accessible.name: "Mosaic tiles"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editing
      onMoveRequested: function(dx, dy) {
        // In the layout editor, ←/→ pick a zone and ↑/↓ add or remove one.
        if (root.layoutEditor) root.editorChange(root.layoutEditor.def, root.layoutEditor.zone + (dx + dy < 0 ? -1 : 1))
        else if (dx !== 0) root.stepView(dx < 0 ? -1 : 1)
        else root.moveCursor(dy)
      }
      onActivateRequested: {
        if (root.layoutEditor) return root.saveLayout()
        if (!root.cursorActive) return
        if (root.view === "hidden") root.showHidden(root.selectedHidden)
        else if (root.view === "layouts") {
          if (root.selectedWorkspace) root.cycleWorkspaceLayout(root.selectedWorkspace)
          else root.editLayout(root.selectedCustom)
        }
        else root.focusTile(root.selectedTile)
      }
      onDeleteRequested: {
        if (root.layoutEditor) return root.editorRemove(root.layoutEditor.zone)
        if (!root.cursorActive) return
        if (root.view === "layouts") root.deleteLayout(root.selectedCustom)
        else if (root.view === "tiles") root.removeTile(root.selectedTile)
      }
      onCloseRequested: {
        if (root.layoutEditor) root.layoutEditor = null
        else if (root.swapTile) root.swapTile = null
        else if (root.adding) root.adding = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "?") { root.allKeys = !root.allKeys; return }
        if (root.view === "layouts" && root.layoutKey(t)) return
        if (t === "a" || t === "A") root.startAdding()
        else if (t === "d" && root.cursorActive) root.removeTile(root.selectedTile)
        else if (t === "D" && root.cursorActive && root.selectedTile) root.closeSession(root.selectedTile.session)
        else if ((t === "g" || t === "G") && root.view === "tiles" && root.cursorActive && root.selectedTile) root.cycleLayout(root.selectedTile.session)
        else if (t === "r" || t === "R") root.refresh()
        else if (root.view === "extension") {
          if (t === "e" || t === "E") root.enableExtension()
          else if (t === "v" || t === "V") root.verifyExtension()
          else if ((t === "b" || t === "B") && root.restartNeeded) root.restartBrowser()
        }
        else if (root.view !== "tiles") return
        else if (t === "C") root.toggleAutoContain()
        else if (t === "c") root.contain()
        else if ((t === "s" || t === "S") && root.cursorActive) root.startSwap(root.selectedTile)
        else if ((t === "m" || t === "M") && root.cursorActive) root.toggleMute(root.selectedTile)
        else if ((t === "f" || t === "F") && root.audioReady) root.toggleAudioFocus()
        else if (t === "-" && root.cursorActive) root.stepVolume(root.selectedTile, -0.1)
        else if ((t === "+" || t === "=") && root.cursorActive) root.stepVolume(root.selectedTile, 0.1)
        else if (t >= "1" && t <= "9") {
          var app = root.shownWebapps[Number(t) - 1]
          if (!(root.swapTile && app && Model.siteOf(app.url) === Model.siteOf(root.swapTile.url))) root.addWebapp(app)
        }
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Mosaic"
            meta: root.listError !== "" ? "Unavailable" : Model.summary(root.sessions, root.tiles)
            detail: root.activity !== "" ? root.activity + "…" : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.tiles.length > 0 ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                text: "󰕰"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          ButtonGroup {
            focusable: false
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            value: root.view
            options: [
              { value: "tiles", label: "Tiles", tooltip: "H/L or ←/→" },
              { value: "hidden", label: "Hidden" + (root.hiddenRows.length > 0 ? "  ·  " + root.hiddenRows.length : ""), tooltip: "Hidden web apps · H/L or ←/→" },
              { value: "layouts", label: "Layouts", tooltip: "Workspace layouts and your own · H/L or ←/→" },
              { value: "extension", label: "Extension" + (root.extensionMissing || (root.service !== null && root.service.extensionOutdated) ? "  ·  !" : ""), tooltip: "The browser extension that audio control needs · H/L or ←/→" }
            ]
            onChanged: function(value) { root.setView(value) }
          }

          Column {
            visible: root.view === "tiles"
            width: parent.width
            spacing: Style.space(12)

            Notice {
              visible: root.listError !== ""
              text: root.listError
            }

            Notice {
              visible: root.service !== null && root.service.swapKeyError !== ""
              text: root.service ? root.service.swapKeyError : ""
              warning: true
            }

            Notice {
              visible: root.service !== null && root.service.layoutError !== ""
              text: root.service ? "Layouts: " + root.service.layoutError : ""
              warning: true
            }

            Notice {
              visible: root.extensionMissing && root.swapTile === null
              text: root.extensionState === "restart"
                ? "Restart the browser to load the Mosaic extension; the Extension tab does it."
                : "Audio control is off: the Mosaic browser extension is not set up. Click here or open the Extension tab."
              clickable: true
              onClicked: root.setView("extension")
            }

            // Switches for the whole mosaic, one line each; each tile's own
            // controls are on its row.
            SwitchRow {
              visible: root.audioReady
              width: parent.width
              checked: root.audioFollowsFocus
              iconOn: "󰕾"
              iconOff: "󰖀"
              text: "Only the focused tile plays"
              keyLabel: "F"
              onToggled: root.toggleAudioFocus()
            }

            SwitchRow {
              visible: root.tiles.length > 0
              width: parent.width
              checked: root.autoContain
              iconOn: "󰊓"
              iconOff: "󰊔"
              text: "Keep fullscreen in tiles"
              keyLabel: "⇧C"
              tooltip: "Contains a tile again whenever it loses containment, and shrinks a fullscreen tile back once another window takes focus"
              onToggled: root.toggleAutoContain()
            }

            Repeater {
              model: root.sessions

              Column {
                id: sessionColumn
                required property var modelData
                readonly property string place: Model.sessionPlace(modelData.tiles)
                width: column.width
                spacing: Style.space(6)

                RowLayout {
                  width: parent.width
                  spacing: Style.space(6)
                  PanelSectionHeader {
                    text: sessionColumn.modelData.name.toUpperCase()
                      + (sessionColumn.place !== "" ? "  ·  " + sessionColumn.place.toUpperCase() : "")
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    Layout.fillWidth: true
                  }
                  LayoutChip {
                    session: sessionColumn.modelData
                  }
                  PanelActionButton {
                    iconText: "󰅙"
                    tooltipText: "Close every tile in " + sessionColumn.modelData.name + " · Shift+D"
                    foreground: root.foreground
                    hoverColor: root.urgent
                    onClicked: root.closeSession(sessionColumn.modelData.name)
                  }
                }

                Repeater {
                  model: sessionColumn.modelData.tiles
                  TileRow {
                    required property var modelData
                    width: sessionColumn.width
                    tile: modelData
                    place: sessionColumn.place
                  }
                }
              }
            }

            // Add tile: one row until A or a click opens it. Hidden while
            // swapping, since the tile's own card holds the picker then.
            CursorSurface {
              visible: root.swapTile === null && !root.addOpen
              width: parent.width
              foreground: root.foreground
              hasCursor: addMouse.containsMouse
              implicitHeight: addRow.implicitHeight + Style.space(12)
              Accessible.role: Accessible.Button
              Accessible.name: "Add tile"

              MouseArea {
                id: addMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.startAdding()
              }

              RowLayout {
                id: addRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(10)
                Rectangle {
                  Layout.preferredWidth: Style.space(28)
                  Layout.preferredHeight: Style.space(28)
                  radius: Style.cornerRadius
                  color: "transparent"
                  border.width: 1
                  border.color: Qt.darker(root.foreground, 2.2)
                  Text {
                    anchors.centerIn: parent
                    text: "󰐕"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                }
                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: "Add tile"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                KeyCap {
                  label: "A"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }
              }
            }

            Column {
              visible: root.addOpen
              width: parent.width
              spacing: Style.space(8)

              RowLayout {
                width: parent.width
                PanelSectionHeader {
                  text: "ADD TILE"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  Layout.fillWidth: true
                }
                PanelActionButton {
                  visible: root.tiles.length > 0
                  iconText: "󰅖"
                  tooltipText: "Close · Esc"
                  foreground: root.foreground
                  onClicked: { root.adding = false; root.leaveField() }
                }
              }

              AppGrid {
                width: parent.width
              }

              TextField {
                id: urlField
                width: parent.width
                placeholderText: "Web address or web app name"
                foreground: root.foreground
                font.family: root.fontFamily
                onAccepted: root.addTile()
                Keys.onEscapePressed: keyCatcher.forceActiveFocus()
              }

              RowLayout {
                width: parent.width
                spacing: Style.space(6)
                TextField {
                  id: sessionField
                  Layout.fillWidth: true
                  placeholderText: "Session (" + (root.selectedTile ? root.selectedTile.session : "default") + ")"
                  foreground: root.foreground
                  font.family: root.fontFamily
                  onAccepted: root.addTile()
                  Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                }
                Button {
                  text: "Add"
                  iconText: "󰐕"
                  foreground: root.foreground
                  enabled: root.activity === ""
                  onClicked: root.addTile()
                }
              }
            }

            Button {
              visible: Model.anyUncontained(root.tiles)
              width: parent.width
              text: "Contain fullscreen in every tile  C"
              iconText: "󰊓"
              foreground: root.foreground
              onClicked: root.contain()
            }
          }

          Column {
            visible: root.view === "hidden"
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "HIDDEN WEB APPS  ·  " + root.hiddenRows.length
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.hiddenRows.length === 0
              width: parent.width
              text: "No web apps are hidden. Right-click a web app button on the Tiles tab to hide it."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.hiddenRows
              HiddenRow {
                required property var modelData
                required property int index
                width: parent.width
                entry: modelData
                position: index
              }
            }
          }

          Column {
            visible: root.view === "layouts" && root.layoutEditor === null
            width: parent.width
            spacing: Style.space(6)

            Notice {
              visible: root.service !== null && root.service.layoutError !== ""
              text: root.service ? "Layouts: " + root.service.layoutError : ""
              warning: true
            }

            PanelSectionHeader {
              text: "WORKSPACES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.workspaceRows
              WorkspaceRow {
                required property var modelData
                required property int index
                width: parent.width
                entry: modelData
                position: index
              }
            }

            Button {
              visible: root.showAllWorkspaces || root.hiddenWorkspaces > 0
              width: parent.width
              text: root.showAllWorkspaces ? "Only workspaces in use" : "Show all workspaces  ·  " + root.hiddenWorkspaces + " more"
              iconText: root.showAllWorkspaces ? "󰅃" : "󰅀"
              foreground: root.foreground
              onClicked: root.showAllWorkspaces = !root.showAllWorkspaces
            }

            PanelSectionHeader {
              text: "YOUR LAYOUTS  ·  " + root.customRows.length
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.customRows.length === 0
              width: parent.width
              text: "Design your own: columns, rows, or a grid, with the zone sizes you want and a main zone that the first window takes. Then pick it for a workspace above."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.customRows
              CustomLayoutRow {
                required property var modelData
                required property int index
                width: parent.width
                entry: modelData
                position: root.workspaceRows.length + index
              }
            }

            Button {
              width: parent.width
              text: "New layout  N"
              iconText: "󰐕"
              foreground: root.foreground
              onClicked: root.newLayout()
            }
          }

          Column {
            visible: root.view === "layouts" && root.layoutEditor !== null
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: root.layoutEditor && root.layoutEditor.oldSlug !== "" ? "EDIT LAYOUT" : "NEW LAYOUT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            TextField {
              id: layoutNameField
              width: parent.width
              placeholderText: "Layout name"
              foreground: root.foreground
              font.family: root.fontFamily
              onTextChanged: root.editorName(text)
              onAccepted: keyCatcher.forceActiveFocus()
              Keys.onEscapePressed: keyCatcher.forceActiveFocus()
            }

            ButtonGroup {
              focusable: false
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              // Presets start over; none stays selected.
              value: ""
              options: Model.PRESETS.map(function(preset) {
                return { value: preset, label: Model.PRESET_LABELS[preset], tooltip: "Start over from " + Model.PRESET_LABELS[preset] + " · T" }
              })
              onChanged: function(value) { root.editorPreset(value) }
            }

            ZonePreview {
              width: parent.width
              height: Math.round(width * 9 / 16)
              def: root.layoutEditor ? root.layoutEditor.def : null
              selected: root.layoutEditor ? root.layoutEditor.zone : -1
              editable: true
            }

            EditorToolbar {
              width: parent.width
            }

            Text {
              width: parent.width
              text: "Drag the lines between zones to resize them. Click a zone to select it; the buttons on it, or here, split it beside or below, make it the main zone, or remove it."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)
              Button {
                Layout.fillWidth: true
                text: "Save"
                iconText: "󰆓"
                foreground: root.foreground
                enabled: root.activity === ""
                onClicked: root.saveLayout()
              }
              Button {
                Layout.fillWidth: true
                text: "Large"
                iconText: "󰊓"
                foreground: root.foreground
                onClicked: root.openLargeEditor()
              }
              Button {
                Layout.fillWidth: true
                text: "Cancel"
                iconText: "󰅖"
                foreground: root.foreground
                onClicked: root.layoutEditor = null
              }
            }
          }

          Column {
            visible: root.view === "extension"
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "BROWSER EXTENSION"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Notice {
              text: root.service ? Model.extensionNotice(root.service.extensionSetup, root.service.bridges) : root.listError
              warning: root.extensionState !== "connected"
            }

            Notice {
              visible: root.service !== null && root.service.extensionError !== ""
              text: root.service ? root.service.extensionError : ""
            }

            Repeater {
              model: root.service ? Model.extensionSteps(root.service.extensionSetup, root.service.bridges, root.service.extensionCheck) : []
              StepRow {
                required property var modelData
                required property int index
                width: parent.width
                step: modelData
                number: index + 1
              }
            }

            Notice {
              visible: root.service !== null && root.service.extensionOutdated
              text: root.service ? "The browser is running an older copy of the Mosaic extension. Restart it to load the current one (" + root.service.extensionVersion + ")." : ""
            }

            // Button labels don't wrap or elide, so the warning goes here.
            Notice {
              visible: root.confirmRestart && root.restartNeeded
              text: "This closes every window of the browser, your tiles included, and opens it again. Press again to go ahead."
            }

            Button {
              visible: root.restartNeeded
              width: parent.width
              text: root.confirmRestart ? "Press again to restart" : "Restart the browser  B"
              iconText: "󰑓"
              foreground: root.foreground
              enabled: root.activity === ""
              onClicked: root.restartBrowser()
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)
              Button {
                visible: root.extensionState === "off" || root.extensionState === "unknown"
                Layout.fillWidth: true
                text: "Enable  E"
                iconText: "󰐕"
                foreground: root.foreground
                onClicked: root.enableExtension()
              }
              Button {
                visible: root.extensionState === "restart" || root.extensionState === "connected"
                Layout.fillWidth: true
                text: "Turn off"
                iconText: "󰅖"
                foreground: root.foreground
                onClicked: root.disableExtension()
              }
              Button {
                Layout.fillWidth: true
                text: root.service && root.service.verifying ? "Verifying…" : "Verify  V"
                iconText: "󰄬"
                foreground: root.foreground
                enabled: !(root.service && root.service.verifying)
                onClicked: root.verifyExtension()
              }
            }

            Text {
              visible: root.extensionState !== "connected"
              width: parent.width
              text: "By hand, in any Chromium browser: open its extensions page, turn on Developer mode, choose Load unpacked, and pick the extension folder."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Button {
              visible: root.extensionState !== "connected"
              width: parent.width
              text: "Copy the extension folder's path"
              iconText: "󰆏"
              foreground: root.foreground
              onClicked: root.copyExtensionPath()
            }
          }

          Notice {
            visible: root.status !== ""
            text: root.status
            warning: root.statusIsError
          }

          // The keys for what's on screen, as key caps; ? shows the rest.
          // The block is centred as a whole: Flow can't centre each line.
          Item {
            width: parent.width
            implicitHeight: keyBar.childrenRect.height
          Flow {
            id: keyBar
            x: Math.max(0, (parent.width - childrenRect.width) / 2)
            width: parent.width
            spacing: Style.space(12)
            Repeater {
              model: Model.keyHints(root.keyContext, root.allKeys, root.shownWebapps.length)
              Row {
                required property var modelData
                spacing: Style.space(5)
                KeyCap {
                  anchors.verticalCenter: parent.verticalCenter
                  label: parent.modelData[0]
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: parent.modelData[1]
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
          }

          Text {
            visible: root.versionText !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.versionText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component Notice: Rectangle {
    id: notice
    property alias text: noticeText.text
    property bool warning: true
    // A clickable notice reacts to the mouse with `clicked`.
    property bool clickable: false
    signal clicked()
    width: parent ? parent.width : 0
    height: noticeText.implicitHeight + Style.spacing.md * 2
    radius: Style.cornerRadius
    color: Style.hoverFillFor(notice.warning ? root.urgent : root.foreground, Color.accent)
    Text {
      id: noticeText
      anchors.fill: parent
      anchors.margins: Style.spacing.md
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
    MouseArea {
      anchors.fill: parent
      enabled: notice.clickable
      cursorShape: Qt.PointingHandCursor
      onClicked: notice.clicked()
    }
  }

  // One step of the extension's setup, done or not.
  component StepRow: Item {
    id: stepRow
    property var step: null
    property int number: 0
    implicitHeight: stepContent.implicitHeight + Style.space(6)

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      spacing: Style.space(10)

      Text {
        Layout.alignment: Qt.AlignTop
        text: stepRow.step && stepRow.step.done ? "󰗠" : "󰄰"
        color: stepRow.step && stepRow.step.done ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      ColumnLayout {
        id: stepContent
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: stepRow.step ? stepRow.number + ". " + stepRow.step.label : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: stepRow.step ? stepRow.step.detail : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  // The web apps as an even grid, each with its number key: a click or the
  // number adds it, or, while swapping, puts it in the tile. The one the
  // tile already shows (`currentUrl`'s site) is dimmed. Right-click hides.
  component AppGrid: GridLayout {
    id: grid
    property string currentUrl: ""
    visible: root.shownWebapps.length > 0
    columns: 3
    columnSpacing: Style.space(6)
    rowSpacing: Style.space(6)

    Repeater {
      model: root.shownWebapps
      CursorSurface {
        id: appTile
        required property var modelData
        required property int index
        readonly property bool current: grid.currentUrl !== "" && Model.siteOf(modelData.url) === Model.siteOf(grid.currentUrl)
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: appRow.implicitHeight + Style.space(12)
        bordered: true
        opacity: current ? 0.45 : 1.0
        hasCursor: appMouse.containsMouse && !current
        foreground: root.foreground
        Accessible.role: Accessible.Button
        Accessible.name: (root.swapTile ? "Swap to " : "Add ") + modelData.name

        RowLayout {
          id: appRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(6)
          spacing: Style.space(6)
          Image {
            Layout.preferredWidth: Style.space(18)
            Layout.preferredHeight: Style.space(18)
            source: root.iconSource(appTile.modelData.icon)
            sourceSize.width: 64
            sourceSize.height: 64
            fillMode: Image.PreserveAspectFit
            visible: status === Image.Ready
          }
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: appTile.modelData.name
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
          KeyCap {
            visible: appTile.index < 9
            label: appTile.current ? "now" : String(appTile.index + 1)
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
        }

        MouseArea {
          id: appMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) root.hideWebapp(appTile.modelData)
            else if (!appTile.current) root.addWebapp(appTile.modelData)
          }
        }

        PanelToolTip {
          visible: appMouse.containsMouse
          text: appTile.current ? "This tile already shows " + appTile.modelData.name
            : appTile.modelData.url + "  ·  right-click to hide"
        }
      }
    }
  }

  // A workspace on the Layouts tab: pick its layout from the dropdown, or
  // Enter for the next one.
  component WorkspaceRow: CursorSurface {
    id: workspaceRow
    property var entry: null
    property int position: 0
    hasCursor: root.cursorActive && root.view === "layouts" && root.cursor === position
    foreground: root.foreground
    implicitHeight: Math.max(workspaceContent.implicitHeight, Style.spacing.controlHeight) + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.cursor = workspaceRow.position }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      ColumnLayout {
        id: workspaceContent
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          text: workspaceRow.entry ? "Workspace " + workspaceRow.entry.id : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: !workspaceRow.entry ? "" : (workspaceRow.entry.monitor !== "" ? workspaceRow.entry.monitor : "Not open")
            + (workspaceRow.entry.windows > 0 ? "  ·  " + workspaceRow.entry.windows + (workspaceRow.entry.windows === 1 ? " window" : " windows") : "  ·  empty")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Dropdown {
        Layout.preferredWidth: Style.space(150)
        showLabel: false
        foreground: root.foreground
        fontFamily: root.fontFamily
        value: workspaceRow.entry ? workspaceRow.entry.choice : "default"
        options: Model.layoutChoices(root.layoutCustom).map(function(choice) {
          return { value: choice, label: Model.layoutLabel(choice, root.layoutCustom) }
        })
        onChanged: function(choice) {
          if (workspaceRow.entry && choice !== workspaceRow.entry.choice) root.setWorkspaceLayout(workspaceRow.entry, choice)
        }
        onPopupOpenChanged: root.dropdownOpen = popupOpen
      }
    }
  }

  // A custom layout on the Layouts tab, with a small preview.
  component CustomLayoutRow: CursorSurface {
    id: customRow
    property var entry: null
    property int position: 0
    hasCursor: root.cursorActive && root.view === "layouts" && root.cursor === position
    foreground: root.foreground
    implicitHeight: Math.max(customContent.implicitHeight, Style.space(27)) + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.cursor = customRow.position }
      onClicked: root.editLayout(customRow.entry)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(10)

      ZonePreview {
        Layout.preferredWidth: Style.space(48)
        Layout.preferredHeight: Style.space(27)
        def: customRow.entry ? customRow.entry.def : null
        compact: true
      }

      ColumnLayout {
        id: customContent
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: customRow.entry ? customRow.entry.def.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: customRow.entry ? Model.customSummary(customRow.entry.def) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: "󰏫"
        tooltipText: "Edit · E or Enter"
        foreground: root.foreground
        onClicked: root.editLayout(customRow.entry)
      }
      PanelActionButton {
        iconText: "󰆴"
        tooltipText: root.confirmDelete === (customRow.entry ? customRow.entry.slug : "") ? "Click again to delete" : "Delete · D"
        foreground: root.foreground
        hoverColor: root.urgent
        onClicked: root.deleteLayout(customRow.entry)
      }
    }
  }

  // A custom layout's zones, numbered in the order windows fill them. The
  // editor's (`editable`) marks the selected zone, takes clicks, shows
  // split, main, and remove buttons on the zone under the pointer, and
  // lets the lines between zones be dragged. Repeaters count zones and
  // lines instead of taking the arrays, so a drag that changes sizes
  // keeps the handle being dragged.
  component ZonePreview: Item {
    id: preview
    property var def: null
    property int selected: -1
    property bool compact: false
    property bool editable: false
    property real toolSize: Style.space(22)
    property int hovered: -1
    readonly property var zones: def ? Model.visualZones(def) : []
    readonly property var lines: def && editable ? Model.zoneDividers(def) : []
    readonly property real gap: compact ? 1 : Style.space(3)

    Repeater {
      model: preview.zones.length
      Rectangle {
        id: zoneBox
        required property int index
        readonly property var zone: preview.zones[index] || ({ x: 0, y: 0, w: 0, h: 0, fill: 0, main: false })
        readonly property bool active: preview.editable && (index === preview.hovered || index === preview.selected)
        x: zone.x * preview.width + preview.gap / 2
        y: zone.y * preview.height + preview.gap / 2
        width: Math.max(0, zone.w * preview.width - preview.gap)
        height: Math.max(0, zone.h * preview.height - preview.gap)
        radius: preview.compact ? 1 : Style.cornerRadius
        color: zone.main ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, preview.compact ? 0.55 : 0.28) : Style.hoverFillFor(root.foreground, Color.accent)
        border.width: index === preview.selected ? 2 : preview.compact ? 0 : 1
        border.color: index === preview.selected ? Color.accent : Qt.darker(root.foreground, 2.2)

        // Hover counts over the zone's buttons too.
        HoverHandler {
          enabled: preview.editable
          onHoveredChanged: {
            if (hovered) preview.hovered = zoneBox.index
            else if (preview.hovered === zoneBox.index) preview.hovered = -1
          }
        }
        MouseArea {
          anchors.fill: parent
          enabled: preview.editable
          onClicked: root.editorChange(root.layoutEditor.def, zoneBox.index)
        }

        Text {
          visible: !preview.compact && !(zoneBox.active && zoneTools.fits)
          anchors.centerIn: parent
          text: zoneBox.zone.main ? zoneBox.zone.fill + "  ★" : String(zoneBox.zone.fill)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // Split beside, split below, main, remove: in a row, or two by two
        // on a narrow zone. Too small for either, the toolbar under the
        // preview does the same for the selected zone.
        Grid {
          id: zoneTools
          readonly property real tool: preview.toolSize
          readonly property real room: Style.space(6)
          readonly property bool wide: zoneBox.width >= tool * 4 + spacing * 3 + room && zoneBox.height >= tool + room
          readonly property bool fits: wide || (zoneBox.width >= tool * 2 + spacing + room && zoneBox.height >= tool * 2 + spacing + room)
          visible: zoneBox.active && fits
          anchors.centerIn: parent
          columns: wide ? 4 : 2
          spacing: Style.space(2)
          ZoneTool {
            size: preview.toolSize
            kind: "beside"
            tip: "Split: a new zone beside this one · S"
            onClicked: root.editorSplit(zoneBox.index, "row")
          }
          ZoneTool {
            size: preview.toolSize
            kind: "below"
            tip: "Split: a new zone below this one · B"
            onClicked: root.editorSplit(zoneBox.index, "column")
          }
          ZoneTool {
            size: preview.toolSize
            kind: "main"
            tip: "Main zone: the first window goes here · M"
            on: zoneBox.zone.main
            onClicked: root.editorMain(zoneBox.index)
          }
          ZoneTool {
            size: preview.toolSize
            kind: "remove"
            tip: "Remove this zone · X"
            onClicked: root.editorRemove(zoneBox.index)
          }
        }
      }
    }

    // The lines between zones: drag to resize.
    Repeater {
      model: preview.lines.length
      Item {
        id: handle
        required property int index
        readonly property var line: preview.lines[index] || ({ vertical: true, x: 0, y: 0, length: 0, from: 0, span: 1 })
        readonly property real thickness: Style.space(10)
        x: line.vertical ? line.x * preview.width - thickness / 2 : line.x * preview.width
        y: line.vertical ? line.y * preview.height : line.y * preview.height - thickness / 2
        width: line.vertical ? thickness : line.length * preview.width
        height: line.vertical ? line.length * preview.height : thickness
        z: 2

        Rectangle {
          anchors.centerIn: parent
          width: handle.line.vertical ? Style.space(3) : parent.width - Style.space(8)
          height: handle.line.vertical ? parent.height - Style.space(8) : Style.space(3)
          radius: Style.space(2)
          color: Color.accent
          visible: dragArea.containsMouse || dragArea.pressed
        }

        MouseArea {
          id: dragArea
          anchors.fill: parent
          hoverEnabled: true
          preventStealing: true
          cursorShape: handle.line.vertical ? Qt.SplitHCursor : Qt.SplitVCursor
          onPositionChanged: function(mouse) {
            if (!pressed) return
            var point = mapToItem(preview, mouse.x, mouse.y)
            root.editorDivider(handle.line, handle.line.vertical ? point.x / preview.width : point.y / preview.height)
          }
        }
      }
    }
  }

  // The selected zone and its buttons, under the editor's preview, for
  // zones too small to hold them.
  component EditorToolbar: RowLayout {
    id: toolbar
    // Larger in the large editor.
    property real toolSize: Style.space(22)
    property real textSize: Style.font.caption
    spacing: Style.space(2)
    Text {
      Layout.fillWidth: true
      text: {
        var editor = root.layoutEditor
        if (!editor) return ""
        var zone = Model.visualZones(editor.def)[editor.zone]
        return "Zone " + zone.fill + "  ·  " + Model.zonePercent(zone) + "%"
          + (zone.main ? "  ·  main, the first window goes here" : "")
      }
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: toolbar.textSize
      elide: Text.ElideRight
    }
    ZoneTool {
      size: toolbar.toolSize
      kind: "smaller"
      tip: "Make this zone smaller · −"
      onClicked: root.editorSize(-1)
    }
    ZoneTool {
      size: toolbar.toolSize
      kind: "bigger"
      tip: "Make this zone bigger · +"
      onClicked: root.editorSize(1)
    }
    ZoneTool {
      size: toolbar.toolSize
      kind: "beside"
      tip: "Split: a new zone beside this one · S"
      onClicked: root.editorSplit(root.layoutEditor.zone, "row")
    }
    ZoneTool {
      size: toolbar.toolSize
      kind: "below"
      tip: "Split: a new zone below this one · B"
      onClicked: root.editorSplit(root.layoutEditor.zone, "column")
    }
    ZoneTool {
      size: toolbar.toolSize
      kind: "main"
      tip: "Main zone: the first window goes here · M"
      on: root.layoutEditor !== null && root.layoutEditor.def.main === root.layoutEditor.zone + 1
      onClicked: root.editorMain(root.layoutEditor.zone)
    }
    ZoneTool {
      size: toolbar.toolSize
      kind: "remove"
      tip: "Remove this zone · X"
      onClicked: root.editorRemove(root.layoutEditor.zone)
    }
  }

  // The large editor, over the focused monitor, drawn at its shape.
  PanelWindow {
    id: largeWindow
    visible: root.largeEditor && root.layoutEditor !== null
    screen: {
      var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
      var screens = Quickshell.screens
      for (var i = 0; i < screens.length; i++) if (screens[i].name === name) return screens[i]
      return screens.length > 0 ? screens[0] : null
    }
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "pym-mosaic-layout-editor"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    BorderSurface {
      id: largeCard
      anchors.fill: parent
      anchors.margins: Style.space(40)
      radius: Style.cornerRadius
      // Opaque: the windows behind would show through a translucent theme.
      color: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 1)
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      Item {
        id: largeKeys
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
          var editor = root.layoutEditor
          if (!editor) return
          event.accepted = true
          if (event.key === Qt.Key_Escape) root.closeLargeEditor()
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.saveLayout()
          else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.text === "h" || event.text === "k")
            root.editorChange(editor.def, editor.zone - 1)
          else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.text === "l" || event.text === "j")
            root.editorChange(editor.def, editor.zone + 1)
          else if (event.key === Qt.Key_Delete || event.text === "x" || event.text === "X") root.editorRemove(editor.zone)
          else if (event.text === "" || !root.layoutKey(event.text)) event.accepted = false
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.topMargin: largeCard.contentTopInset
          anchors.bottomMargin: largeCard.contentBottomInset
          anchors.leftMargin: largeCard.contentLeftInset
          anchors.rightMargin: largeCard.contentRightInset
          spacing: Style.spacing.md

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)
            TextField {
              id: largeNameField
              Layout.preferredWidth: Style.space(260)
              placeholderText: "Layout name"
              foreground: root.foreground
              font.family: root.fontFamily
              onTextChanged: root.editorName(text)
              onAccepted: largeKeys.forceActiveFocus()
              Keys.onEscapePressed: largeKeys.forceActiveFocus()
            }
            ButtonGroup {
              focusable: false
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              value: ""
              options: Model.PRESETS.map(function(preset) {
                return { value: preset, label: Model.PRESET_LABELS[preset], tooltip: "Start over from " + Model.PRESET_LABELS[preset] + " · T" }
              })
              onChanged: function(value) { root.editorPreset(value) }
            }
            Item { Layout.fillWidth: true }
            Button {
              text: "Save"
              iconText: "󰆓"
              foreground: root.foreground
              enabled: root.activity === ""
              onClicked: root.saveLayout()
            }
            Button {
              text: "Back"
              iconText: "󰁍"
              foreground: root.foreground
              onClicked: root.closeLargeEditor()
            }
          }

          // The preview at the monitor's shape, as large as fits.
          Item {
            id: largeArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            readonly property real aspect: largeWindow.screen && largeWindow.screen.height > 0 ? largeWindow.screen.width / largeWindow.screen.height : 16 / 9
            ZonePreview {
              width: Math.min(largeArea.width, largeArea.height * largeArea.aspect)
              height: width / largeArea.aspect
              anchors.centerIn: parent
              def: root.layoutEditor ? root.layoutEditor.def : null
              selected: root.layoutEditor ? root.layoutEditor.zone : -1
              editable: true
              toolSize: Style.space(40)
            }
          }

          EditorToolbar {
            Layout.fillWidth: true
            toolSize: Style.space(36)
            textSize: Style.font.body
          }

          Text {
            Layout.fillWidth: true
            visible: root.status !== ""
            text: root.status
            color: root.statusIsError ? root.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            Layout.fillWidth: true
            text: "Drag the lines between zones to resize  ·  ←→ zone  ·  −/+ size  ·  S split beside  ·  B below  ·  X remove  ·  M main  ·  T preset  ·  N name  ·  Enter save  ·  Esc back to the panel"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  // A small button on a zone in the layout editor. The split icons are
  // drawn, so they don't depend on the font.
  component ZoneTool: Rectangle {
    id: tool
    property real size: Style.space(22)
    property string kind: ""
    property string tip: ""
    property bool on: false
    signal clicked()
    width: size
    height: size
    radius: Style.cornerRadius
    color: toolMouse.containsMouse ? Style.hoverFillFor(kind === "remove" ? root.urgent : root.foreground, Color.accent)
      : Color.popups.background
    border.width: 1
    border.color: Qt.darker(root.foreground, 1.8)

    // A zone outline with its split line.
    Rectangle {
      visible: tool.kind === "beside" || tool.kind === "below"
      anchors.centerIn: parent
      width: tool.size * 0.55
      height: tool.size * 0.45
      color: "transparent"
      border.width: 1
      border.color: root.foreground
      Rectangle {
        anchors.centerIn: parent
        width: tool.kind === "beside" ? 1 : parent.width
        height: tool.kind === "beside" ? parent.height : 1
        color: root.foreground
      }
    }
    Text {
      visible: tool.kind !== "beside" && tool.kind !== "below"
      anchors.centerIn: parent
      text: tool.kind === "main" ? (tool.on ? "★" : "☆") : tool.kind === "remove" ? "×" : tool.kind === "smaller" ? "−" : "+"
      color: tool.kind === "main" && tool.on ? Color.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Math.max(Style.font.body, tool.size * 0.55)
    }
    MouseArea {
      id: toolMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: tool.clicked()
    }
    PanelToolTip {
      visible: toolMouse.containsMouse
      text: tool.tip
    }
  }

  component HiddenRow: CursorSurface {
    id: hiddenRow
    property var entry: null
    property int position: 0
    hasCursor: root.cursorActive && root.view === "hidden" && root.cursor === position
    foreground: root.foreground
    implicitHeight: hiddenContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.cursor = hiddenRow.position }
      onClicked: root.showHidden(hiddenRow.entry)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(10)

      SiteLogo {
        source: hiddenRow.entry && hiddenRow.entry.app ? root.iconSource(hiddenRow.entry.app.icon) : ""
        initial: hiddenRow.entry ? String(hiddenRow.entry.label).charAt(0).toUpperCase() : ""
      }

      ColumnLayout {
        id: hiddenContent
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: hiddenRow.entry ? hiddenRow.entry.label : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: !hiddenRow.entry ? "" : hiddenRow.entry.app ? Model.siteOf(hiddenRow.entry.app.url) : "No installed web app has this name"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: hiddenRow.entry && hiddenRow.entry.app ? "󰈈" : "󰅖"
        tooltipText: hiddenRow.entry && hiddenRow.entry.app ? "Show this web app again · Enter" : "Remove from the hidden list · Enter"
        foreground: root.foreground
        onClicked: root.showHidden(hiddenRow.entry)
      }
    }
  }

  // A small key label, like a key on the keyboard, as the swap card draws
  // them.
  component KeyCap: Rectangle {
    property string label: ""
    property color foreground: root.foreground
    property string fontFamily: root.fontFamily
    implicitWidth: Math.max(implicitHeight, capText.implicitWidth + Style.space(10))
    implicitHeight: capText.implicitHeight + Style.space(4)
    radius: Math.max(2, Style.cornerRadius / 2)
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.06)
    border.width: 1
    border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.22)

    Text {
      id: capText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: parent.label
      color: parent.foreground
      font.family: parent.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // A site's logo in a 28px square, or its initial when there is none.
  component SiteLogo: Rectangle {
    property alias source: logoImage.source
    property string initial: ""
    implicitWidth: Style.space(28)
    implicitHeight: Style.space(28)
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    radius: Style.cornerRadius
    color: logoImage.status === Image.Ready ? "transparent" : Style.selectedFillFor(root.foreground, Color.accent)

    Image {
      id: logoImage
      anchors.fill: parent
      anchors.margins: Style.space(2)
      sourceSize.width: 64
      sourceSize.height: 64
      fillMode: Image.PreserveAspectFit
      smooth: true
      visible: status === Image.Ready
    }
    Text {
      visible: logoImage.status !== Image.Ready
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: parent.initial
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }
  }

  // A setting for the whole mosaic: an icon, what it does, and a switch.
  component SwitchRow: CursorSurface {
    id: switchRow
    property bool checked: false
    property string iconOn: ""
    property string iconOff: ""
    property string text: ""
    property string tooltip: ""
    property string keyLabel: ""
    signal toggled()
    foreground: root.foreground
    hasCursor: switchMouse.containsMouse
    implicitHeight: switchContent.implicitHeight + Style.space(6)
    Accessible.role: Accessible.CheckBox
    Accessible.name: text
    Accessible.checked: checked

    MouseArea {
      id: switchMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: switchRow.toggled()
    }

    RowLayout {
      id: switchContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)
      Text {
        text: switchRow.checked ? switchRow.iconOn : switchRow.iconOff
        color: switchRow.checked ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: switchRow.text
        color: switchRow.checked ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
      KeyCap {
        visible: switchRow.keyLabel !== ""
        label: switchRow.keyLabel
      }
      ToggleSwitch {
        checked: switchRow.checked
        interactive: false
        foreground: root.foreground
      }
    }

    PanelToolTip {
      visible: switchMouse.containsMouse && switchRow.tooltip !== ""
      text: switchRow.tooltip
    }
  }

  // A session's layout in its header: a small picture of where its tiles
  // go, and the layout's name. A click (or G) moves to the next layout.
  component LayoutChip: CursorSurface {
    id: chip
    property var session: null
    readonly property string choice: session ? root.layoutOf(session.name) : "default"
    readonly property string label: Model.layoutLabel(choice, root.layoutCustom)
    hasCursor: chipMouse.containsMouse
    bordered: true
    foreground: root.foreground
    implicitWidth: chipRow.implicitWidth + Style.space(14)
    implicitHeight: Style.space(24)
    Accessible.role: Accessible.Button
    Accessible.name: "Layout: " + label

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.space(6)
      // Fits a 22 × 14 box, so a portrait monitor's picture stays legible.
      LayoutThumb {
        anchors.verticalCenter: parent.verticalCenter
        height: Math.round(Math.min(Style.space(14), Style.space(22) / aspect))
        width: Math.round(height * aspect)
        aspect: chip.session && chip.session.tiles.length > 0 ? root.monitorAspect(chip.session.tiles[0].monitor) : 16 / 9
        boxes: Model.layoutBoxes(chip.choice, root.layoutCustom, chip.session ? chip.session.tiles.length : 0, aspect)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: chip.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: if (chip.session) root.cycleLayout(chip.session.name)
    }

    PanelToolTip {
      visible: chipMouse.containsMouse
      text: chip.session ? "Layout of this session's workspace. Click for "
        + Model.layoutLabel(Model.nextLayout(chip.choice, root.layoutCustom), root.layoutCustom) + " · G" : ""
    }
  }

  // Boxes from Model.layoutBoxes, drawn small; the first window's box,
  // the main one, in the accent colour.
  component LayoutThumb: Item {
    id: thumb
    property var boxes: []
    property real aspect: 16 / 9
    Repeater {
      model: thumb.boxes.length
      Rectangle {
        required property int index
        readonly property var cell: thumb.boxes[index] || ({ x: 0, y: 0, w: 0, h: 0 })
        x: Math.round(cell.x * thumb.width) + 0.5
        y: Math.round(cell.y * thumb.height) + 0.5
        width: Math.max(1, Math.round(cell.w * thumb.width) - 1)
        height: Math.max(1, Math.round(cell.h * thumb.height) - 1)
        radius: 1
        color: index === 0 ? Color.accent : root.foreground
        opacity: index === 0 ? 0.9 : 0.45
      }
    }
  }

  component TileRow: CursorSurface {
    id: row
    property var tile: null
    // The session's shared monitor and workspace, which its header shows.
    property string place: ""
    readonly property bool swapping: root.swapTile !== null && tile !== null && root.swapTile.address === tile.address
    readonly property var audio: tile ? root.tileAudio[tile.address] : undefined
    readonly property var app: Model.tileApp(root.webapps, tile)
    // The site's logo: its web app's icon, else the tab's favicon from the
    // extension; without either, the row shows the name's first letter.
    readonly property string logo: {
      if (app && app.icon) return root.iconSource(app.icon)
      var tab = root.service && tile ? Model.tileTab(root.service.extensionCheck, root.service.bridges, tile.address) : null
      return tab && /^(https?|data):/.test(tab.favIconUrl || "") ? tab.favIconUrl : ""
    }
    readonly property string meta: tile ? Model.tileMeta(tile, place, app) : ""
    // The volume slider shows on the row under the cursor only, so the
    // list stays one line per tile.
    readonly property bool showSlider: audio !== undefined && hasCursor && !swapping
    // The level the user set, which the slider shows right away; the
    // browser's report of it arrives a moment later.
    readonly property real volume: {
      var set = root.service && tile ? root.service.tileVolumes[tile.address] : undefined
      return set !== undefined ? set : (audio ? audio.volume : 1)
    }
    hasCursor: swapping || (root.cursorActive && tile !== null && root.cursor === tile.position)
    foreground: root.foreground
    implicitHeight: rowColumn.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.cursor = row.tile.position }
      onClicked: root.focusTile(row.tile)
    }

    ColumnLayout {
      id: rowColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(4)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(10)

        SiteLogo {
          id: logoBox
          Layout.alignment: Qt.AlignVCenter
          source: row.logo
          initial: row.tile ? Model.tileInitial(row.tile, row.app) : ""
        }

        ColumnLayout {
          id: content
          Layout.fillWidth: true
          spacing: Style.space(1)
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: row.tile ? (row.swapping ? "󰓡  " : "") + Model.tileName(row.tile, row.app) : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            visible: row.meta !== ""
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: row.meta
            color: row.tile && row.tile.state === "uncontained" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Text {
          visible: row.audio !== undefined
          textFormat: Text.PlainText
          text: row.audio ? Math.round(row.volume * 100) + "%" : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          horizontalAlignment: Text.AlignRight
          Layout.preferredWidth: Style.space(36)
          opacity: row.audio && row.audio.muted ? 0.5 : 1.0
        }

        PanelActionButton {
          readonly property var audio: row.audio
          visible: audio !== undefined
          iconText: Model.audioIcon(audio)
          tooltipText: !audio ? "" : (audio.muted ? "Muted; unmute · M" : (audio.audible ? "Playing; mute · M" : "Silent; mute · M"))
            + "  ·  scroll or −/+ for volume"
          foreground: root.foreground
          onClicked: root.toggleMute(row.tile)
          WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(event) {
              if (event.angleDelta.y !== 0) root.stepVolume(row.tile, event.angleDelta.y > 0 ? 0.05 : -0.05)
            }
          }
        }

        PanelActionButton {
          iconText: "󰓡"
          tooltipText: "Swap this tile's web app · S"
            + (root.service && root.service.boundSwapKey !== "" ? " here, " + root.service.boundSwapKey + " on the tile" : "")
          foreground: root.foreground
          onClicked: {
            if (row.swapping) root.swapTile = null
            else root.startSwap(row.tile)
          }
        }

        PanelActionButton {
          iconText: "󰅖"
          tooltipText: "Remove this tile · X or D"
          foreground: root.foreground
          hoverColor: root.urgent
          onClicked: root.removeTile(row.tile)
        }
      }

      // The tile's own volume, as the built-in audio panel shows app
      // streams: right-click mutes, and a muted tile's slider is dimmed.
      PanelSlider {
        visible: row.showSlider
        bar: root.bar
        Layout.fillWidth: true
        Layout.leftMargin: logoBox.width + Style.space(10)
        minimum: 0
        maximum: 1
        step: 0.05
        value: row.volume
        opacity: row.audio && row.audio.muted ? 0.5 : 1.0
        onMoved: function(v) { root.dragVolume(row.tile, v, false) }
        onReleased: function(v) { root.dragVolume(row.tile, v, true) }
        onRightClicked: root.toggleMute(row.tile)
      }

      // Swapping: what replaces this tile, right on its card.
      Loader {
        active: row.swapping
        visible: active
        Layout.fillWidth: true
        Layout.topMargin: Style.space(4)
        sourceComponent: ColumnLayout {
          spacing: Style.space(6)

          AppGrid {
            Layout.fillWidth: true
            currentUrl: row.tile ? row.tile.url : ""
          }

          TextField {
            id: swapAddress
            Layout.fillWidth: true
            text: row.tile && row.tile.url ? row.tile.url : ""
            placeholderText: "Web address or web app name"
            foreground: root.foreground
            font.family: root.fontFamily
            onAccepted: root.swapToAddress(text)
            Keys.onEscapePressed: root.leaveField()
            Component.onCompleted: root.swapField = swapAddress
            Component.onDestruction: if (root.swapField === swapAddress) root.swapField = null
          }

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: root.service && row.tile && root.service.canNavigate(row.tile.address)
              ? "Changes the page in place: same window, slot, and volume."
              : "Opens a new window in this slot, since the browser extension has not found this tile."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
