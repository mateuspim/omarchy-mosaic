import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget for omarchy-mosaic. The tile list and the web apps come from
// the plugin's service (MosaicService.qml), which also focuses, removes,
// closes, and contains tiles. Adding still goes through the mosaic CLI until
// the engine can do it, so this widget holds no session state of its own.
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
  // The panel's tab: "tiles", or "hidden" for the hidden web apps.
  property string view: "tiles"
  property string mosaicVersion: ""
  property string status: ""
  property bool statusIsError: false
  // The running CLI command's description.
  property string busyLabel: ""
  // What is running right now, in the CLI or in the service.
  readonly property string activity: busyLabel !== "" ? busyLabel : service && service.busy ? service.busyLabel : ""
  property int cursor: 0
  property bool cursorActive: false
  property bool actionStarted: false
  readonly property string missingCommand: "Cannot run " + command + ". Install mosaic or set its path in the widget settings."

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string command: {
    var value = String(setting("command", "mosaic")).trim() || "mosaic"
    return value.indexOf("~/") === 0 ? Quickshell.env("HOME") + value.slice(1) : value
  }
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
      view = "tiles"
      cursor = 0
      cursorActive = false
      refresh()
      refreshVersion()
    }
  }

  function findService() {
    if (service) return
    var shell = bar ? bar.shell : null
    service = shell && typeof shell.serviceFor === "function" ? shell.serviceFor(moduleName) : null
  }

  function refresh() {
    if (service) service.refresh()
  }

  function refreshVersion() {
    if (versionProcess.running) return
    versionProcess.command = [command, "--version"]
    versionProcess.running = true
  }

  function iconSource(icon) {
    if (!icon) return ""
    if (icon.indexOf("/") === 0) return "file://" + icon
    return Quickshell.iconPath(icon, true)
  }

  // Runs one mosaic subcommand at a time. `label` describes it while it runs.
  function run(args, label) {
    if (activity !== "") {
      showStatus("Still busy: " + activity, true)
      return
    }
    busyLabel = label
    status = ""
    actionProcess.command = [command].concat(args)
    actionStarted = false
    actionProcess.running = true
  }

  // Runs a service action, such as `service.focus`, and shows why it could
  // not start. The service reports how it ended with actionFinished.
  function runService(start) {
    if (!service) {
      showStatus(listing.error, true)
      return
    }
    if (busyLabel !== "") {
      showStatus("Still busy: " + busyLabel, true)
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
    var session = Model.sessionName(targetSessionText())
    if (session === "") {
      showStatus("Session names use lowercase letters, digits, - and _", true)
      return false
    }
    run(["add", "--session", session, url], "Adding " + label + " to " + session)
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

  // Saves the hiddenWebapps setting; the shell writes it to shell.json.
  function saveHidden(text) {
    var shell = bar ? bar.shell : null
    if (!shell || typeof shell.updateEntryInline !== "function") {
      showStatus("Cannot save settings here; edit Hidden web apps in the widget settings", true)
      return false
    }
    settings = Object.assign({}, settings, { hiddenWebapps: text })
    shell.updateEntryInline(moduleName, settings)
    return true
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
    view = name
    cursor = 0
    cursorActive = false
  }

  function startAdding() {
    setView("tiles")
    if (selectedTile && sessionField.text === "") sessionField.text = selectedTile.session
    urlField.forceActiveFocus()
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

  Process {
    id: versionProcess
    running: false
    stdout: StdioCollector { id: versionStdout; waitForEnd: true }
    onExited: function(exitCode) {
      root.mosaicVersion = exitCode === 0 ? String(versionStdout.text).trim() : ""
    }
  }

  Connections {
    target: root.service
    function onActionFinished(label, error, message) {
      if (error) root.showStatus(error, true)
    }
  }

  Process {
    id: actionProcess
    running: false
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onStarted: root.actionStarted = true
    // Quickshell never emits `exited` for a command that cannot start.
    onRunningChanged: if (!running && !root.actionStarted) {
      root.showStatus(root.missingCommand, true)
      root.busyLabel = ""
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.showStatus(Model.errorLine(actionStderr.text, root.busyLabel + " failed"), true)
      root.busyLabel = ""
      root.refresh()
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
        if (dx !== 0) root.setView(dx < 0 ? "tiles" : "hidden")
        else root.moveCursor(dy)
      }
      onActivateRequested: {
        if (!root.cursorActive) return
        if (root.view === "hidden") root.showHidden(root.selectedHidden)
        else root.focusTile(root.selectedTile)
      }
      onDeleteRequested: if (root.cursorActive) root.removeTile(root.selectedTile)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "a" || t === "A") root.startAdding()
        else if (t === "d" && root.cursorActive) root.removeTile(root.selectedTile)
        else if (t === "D" && root.cursorActive && root.selectedTile) root.closeSession(root.selectedTile.session)
        else if (t === "r" || t === "R") root.refresh()
        else if (root.view !== "tiles") return
        else if (t === "c" || t === "C") root.contain()
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
              { value: "tiles", label: "Tiles", tooltip: "H or ←" },
              { value: "hidden", label: "Hidden web apps" + (root.hiddenRows.length > 0 ? "  ·  " + root.hiddenRows.length : ""), tooltip: "L or →" }
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
                text: root.shownWebapps.length > 0 ? "ADD TILE  ·  1–" + Math.min(9, root.shownWebapps.length) + " WEB APP  ·  A ADDRESS" : "ADD TILE  ·  A"
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

          Notice {
            visible: root.status !== ""
            text: root.status
            warning: root.statusIsError
          }

          Text {
            width: parent.width
            text: root.view === "hidden"
              ? "↑↓ select  ·  Enter show again  ·  H/L tabs  ·  R refresh"
              : "↑↓ select  ·  Enter focus  ·  X remove  ·  ⇧D close session  ·  H/L tabs  ·  R refresh"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.mosaicVersion !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.mosaicVersion
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
    hasCursor: root.cursorActive && tile !== null && root.cursor === tile.position
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
          text: row.tile ? Model.tileLabel(row.tile) : ""
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
        iconText: "󰅖"
        tooltipText: "Remove this tile · X or D"
        foreground: root.foreground
        hoverColor: root.urgent
        onClicked: root.removeTile(row.tile)
      }
    }
  }
}
