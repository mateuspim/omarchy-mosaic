import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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
  // The panel's tab: "tiles", "hidden" for the hidden web apps, or "audio"
  // for the browser extension's setup.
  property string view: "tiles"
  readonly property var views: ["tiles", "hidden", "audio"]
  // The browser extension, which audio control needs.
  readonly property string extensionState: service ? service.extensionState : "unknown"
  readonly property bool extensionMissing: extensionState === "off" || extensionState === "restart"
  // The browser has to restart to load the extension, or a newer one.
  readonly property bool restartNeeded: extensionState === "restart" || (service !== null && service.extensionOutdated)
  // Each found tile's audio, by address (Model.tileAudio).
  readonly property var tileAudio: service ? service.tileAudio : ({})
  // The audioFollowsFocus setting: mute every tile but the focused one.
  readonly property bool audioFollowsFocus: setting("audioFollowsFocus", false) === true
  property bool confirmRestart: false
  // Swap mode: the tile ({ address, label }) that the next web app or
  // address replaces, or null.
  property var swapTile: null
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
  readonly property int cursorCount: view === "tiles" ? tiles.length : hiddenRows.length
  readonly property var selectedTile: view === "tiles" && cursor >= 0 && cursor < tiles.length ? tiles[cursor] : null
  readonly property var selectedHidden: view === "hidden" && cursor >= 0 && cursor < hiddenRows.length ? hiddenRows[cursor] : null
  readonly property bool editing: urlField.activeFocus || sessionField.activeFocus

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: findService()
  onBarChanged: findService()
  onCursorCountChanged: cursor = Math.max(0, Math.min(cursor, cursorCount - 1))
  onOpenedChanged: {
    if (opened) {
      status = ""
      confirmRestart = false
      swapTile = null
      view = "tiles"
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
      keyCatcher.forceActiveFocus()
    }
  }

  function addWebapp(app) {
    if (app) addUrl(app.url, app.name)
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

  function toggleAudioFocus() {
    saveSetting("audioFollowsFocus", !audioFollowsFocus)
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
    setView("tiles")
    if (selectedTile && sessionField.text === "") sessionField.text = selectedTile.session
    urlField.forceActiveFocus()
  }

  // Enters swap mode for `tile`: the web app buttons, 1–9, and the address
  // field then replace it instead of adding a tile.
  function startSwap(tile) {
    if (!tile) return
    setView("tiles")
    cursorActive = true
    cursor = tile.position
    swapTile = { address: tile.address, label: Model.tileLabel(tile) }
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
    property: "hiddenWebapps"
    value: String(root.setting("hiddenWebapps", ""))
    when: root.service !== null
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
        if (dx !== 0) root.stepView(dx < 0 ? -1 : 1)
        else root.moveCursor(dy)
      }
      onActivateRequested: {
        if (!root.cursorActive) return
        if (root.view === "hidden") root.showHidden(root.selectedHidden)
        else root.focusTile(root.selectedTile)
      }
      onDeleteRequested: if (root.cursorActive) root.removeTile(root.selectedTile)
      onCloseRequested: {
        if (root.swapTile) root.swapTile = null
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "a" || t === "A") root.startAdding()
        else if (t === "d" && root.cursorActive) root.removeTile(root.selectedTile)
        else if (t === "D" && root.cursorActive && root.selectedTile) root.closeSession(root.selectedTile.session)
        else if (t === "r" || t === "R") root.refresh()
        else if (root.view === "audio") {
          if (t === "e" || t === "E") root.enableExtension()
          else if (t === "v" || t === "V") root.verifyExtension()
          else if ((t === "b" || t === "B") && root.restartNeeded) root.restartBrowser()
          else if (t === "f" || t === "F") root.toggleAudioFocus()
        }
        else if (root.view !== "tiles") return
        else if (t === "c" || t === "C") root.contain()
        else if ((t === "s" || t === "S") && root.cursorActive) root.startSwap(root.selectedTile)
        else if ((t === "m" || t === "M") && root.cursorActive) root.toggleMute(root.selectedTile)
        else if (t >= "1" && t <= "9") root.addWebapp(root.shownWebapps[Number(t) - 1])
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
              { value: "audio", label: "Audio" + (root.extensionMissing ? "  ·  !" : ""), tooltip: "The browser extension for audio control · H/L or ←/→" }
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
              visible: root.extensionMissing && root.swapTile === null
              text: root.extensionState === "restart"
                ? "Restart the browser to load the Mosaic extension, then verify it on the Audio tab."
                : "Audio control is off: the Mosaic browser extension is not set up. Click here or open the Audio tab."
              clickable: true
              onClicked: root.setView("audio")
            }

            Notice {
              visible: root.swapTile !== null
              warning: false
              text: root.swapTile ? "Replacing " + root.swapTile.label + ". Pick a web app, or press A and type an address. Esc cancels." : ""
            }

            Repeater {
              model: root.sessions

              Column {
                id: sessionColumn
                required property var modelData
                width: column.width
                spacing: Style.space(6)

                RowLayout {
                  width: parent.width
                  PanelSectionHeader {
                    text: sessionColumn.modelData.name.toUpperCase() + "  ·  " + sessionColumn.modelData.tiles.length
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    Layout.fillWidth: true
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
                  }
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: (root.swapTile ? "REPLACE WITH" : "ADD TILE")
                  + (root.shownWebapps.length > 0 ? "  ·  1–" + Math.min(9, root.shownWebapps.length) + " WEB APP  ·  A ADDRESS" : "  ·  A")
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Flow {
                visible: root.shownWebapps.length > 0
                width: parent.width
                spacing: Style.space(6)
                Repeater {
                  model: root.shownWebapps
                  WebappButton {
                    required property var modelData
                    required property int index
                    app: modelData
                    number: index + 1
                  }
                }
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
                  // A replacement keeps the old tile's session.
                  visible: root.swapTile === null
                  Layout.fillWidth: true
                  placeholderText: "Session (" + (root.selectedTile ? root.selectedTile.session : "default") + ")"
                  foreground: root.foreground
                  font.family: root.fontFamily
                  onAccepted: root.addTile()
                  Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                }
                Item {
                  visible: root.swapTile !== null
                  Layout.fillWidth: true
                }
                Button {
                  text: root.swapTile ? "Replace" : "Add"
                  iconText: root.swapTile ? "󰓡" : "󰐕"
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
            visible: root.view === "audio"
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

            RowLayout {
              visible: root.extensionState === "connected"
              width: parent.width
              spacing: Style.space(10)
              ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Style.space(10)
                spacing: Style.space(1)
                Text {
                  Layout.fillWidth: true
                  text: "Mute every tile but the focused one"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                }
                Text {
                  Layout.fillWidth: true
                  text: "Focusing a tile unmutes it and mutes the rest  ·  F"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
              ToggleSwitch {
                checked: root.audioFollowsFocus
                foreground: root.foreground
                onToggled: root.toggleAudioFocus()
              }
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

          Text {
            width: parent.width
            text: root.view === "audio"
              ? (root.restartNeeded ? "B restart browser  ·  V verify  ·  H/L tabs"
                : root.extensionState === "connected" ? "F mute all but focused  ·  V verify  ·  H/L tabs" : "E enable  ·  V verify  ·  H/L tabs")
              : root.view === "hidden"
              ? "↑↓ select  ·  Enter show again  ·  H/L tabs  ·  R refresh"
              : root.swapTile
                ? "1–9 or A pick the replacement  ·  Esc cancel"
                : "↑↓ select  ·  Enter focus  ·  S swap  ·  M mute  ·  X remove  ·  ⇧D close session  ·  H/L tabs  ·  R refresh"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
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

  component WebappButton: CursorSurface {
    id: webappButton
    property var app: null
    property int number: 0
    bordered: true
    hasCursor: webappMouse.containsMouse
    foreground: root.foreground
    implicitWidth: webappRow.implicitWidth + Style.space(16)
    implicitHeight: webappRow.implicitHeight + Style.space(10)
    Accessible.role: Accessible.Button
    Accessible.name: app ? "Add " + app.name : ""

    Row {
      id: webappRow
      anchors.centerIn: parent
      spacing: Style.space(6)
      Image {
        id: webappIcon
        width: Style.space(16)
        height: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        source: webappButton.app ? root.iconSource(webappButton.app.icon) : ""
        sourceSize.width: 64
        sourceSize.height: 64
        fillMode: Image.PreserveAspectFit
        visible: status === Image.Ready
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: (webappButton.number <= 9 ? webappButton.number + "  " : "") + (webappButton.app ? webappButton.app.name : "")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: webappMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) root.hideWebapp(webappButton.app)
        else root.addWebapp(webappButton.app)
      }
    }

    PanelToolTip {
      visible: webappMouse.containsMouse
      text: webappButton.app ? webappButton.app.url + "  ·  right-click to hide" : ""
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
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Image {
        Layout.preferredWidth: Style.space(16)
        Layout.preferredHeight: Style.space(16)
        source: hiddenRow.entry && hiddenRow.entry.app ? root.iconSource(hiddenRow.entry.app.icon) : ""
        sourceSize.width: 64
        sourceSize.height: 64
        fillMode: Image.PreserveAspectFit
        visible: status === Image.Ready
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
          text: !hiddenRow.entry ? "" : hiddenRow.entry.app ? hiddenRow.entry.app.url : "No installed web app has this name"
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

  component TileRow: CursorSurface {
    id: row
    property var tile: null
    readonly property bool swapping: root.swapTile !== null && tile !== null && root.swapTile.address === tile.address
    hasCursor: swapping || (root.cursorActive && tile !== null && root.cursor === tile.position)
    foreground: root.foreground
    implicitHeight: content.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.cursor = row.tile.position }
      onClicked: root.focusTile(row.tile)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      ColumnLayout {
        id: content
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: row.tile ? (row.swapping ? "󰓡  " : "") + Model.tileLabel(row.tile) : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: row.tile ? Model.tileMeta(row.tile) : ""
          color: row.tile && row.tile.state === "uncontained" ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        readonly property var audio: row.tile ? root.tileAudio[row.tile.address] : undefined
        visible: audio !== undefined
        iconText: Model.audioIcon(audio)
        tooltipText: !audio ? "" : (audio.muted ? "Muted; unmute · M" : (audio.audible ? "Playing; mute · M" : "Silent; mute · M"))
        foreground: root.foreground
        onClicked: root.toggleMute(row.tile)
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
  }
}
