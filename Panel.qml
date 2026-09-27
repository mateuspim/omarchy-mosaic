import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget for omarchy-mosaic. All state comes from `mosaic list --json`,
// and every change goes through the mosaic CLI, so this widget holds no
// session state of its own.
Panel {
  id: root
  moduleName: "pym.mosaic"
  manageIpc: false

  property var sessions: []
  property var tiles: []
  property string listError: ""
  property string status: ""
  property bool statusIsError: false
  property string busyLabel: ""
  property int cursor: 0
  property bool cursorActive: false
  property bool listStarted: false
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
  readonly property var selectedTile: cursor >= 0 && cursor < tiles.length ? tiles[cursor] : null
  readonly property bool editing: urlField.activeFocus || sessionField.activeFocus

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Debounced, so the first list runs with the settings the host injects
  // after creation.
  Component.onCompleted: refreshTimer.restart()
  onCommandChanged: refreshTimer.restart()
  onOpenedChanged: {
    if (opened) {
      status = ""
      cursorActive = false
      refresh()
    }
  }

  function refresh() {
    if (listProcess.running) {
      refreshTimer.restart()
      return
    }
    listProcess.command = [command, "list", "--json"]
    listStarted = false
    listProcess.running = true
  }

  function applyList(text) {
    var list = Model.parseList(text)
    sessions = list.sessions
    tiles = list.tiles
    listError = list.error
    cursor = Math.max(0, Math.min(cursor, tiles.length - 1))
  }

  // Runs one mosaic subcommand at a time. `label` describes it while it runs.
  function run(args, label) {
    if (actionProcess.running) {
      showStatus("Still busy: " + busyLabel, true)
      return
    }
    busyLabel = label
    status = ""
    actionProcess.command = [command].concat(args)
    actionStarted = false
    actionProcess.running = true
  }

  function showListError(text) {
    sessions = []
    tiles = []
    listError = text
  }

  function showStatus(text, isError) {
    status = text
    statusIsError = isError
  }

  function addTile() {
    var url = Model.normalizeUrl(urlField.text)
    var session = Model.sessionName(sessionField.text)
    if (url === "") {
      showStatus("Enter a web address, such as twitch.tv/name", true)
      return
    }
    if (session === "") {
      showStatus("Session names use lowercase letters, digits, - and _", true)
      return
    }
    run(["add", "--session", session, url], "Adding " + url)
    urlField.text = ""
    keyCatcher.forceActiveFocus()
  }

  function startAdding() {
    if (selectedTile && sessionField.text === "") sessionField.text = selectedTile.session
    urlField.forceActiveFocus()
  }

  function focusTile(tile) {
    if (!tile) return
    run(["focus", tile.address], "Focusing " + Model.tileLabel(tile))
  }

  function removeTile(tile) {
    if (!tile) return
    run(["remove", tile.address], "Removing " + Model.tileLabel(tile))
  }

  function closeSession(name) {
    run(["close", "--session", name], "Closing " + name)
  }

  function moveCursor(delta) {
    if (tiles.length === 0) return
    cursorActive = true
    cursor = Math.max(0, Math.min(tiles.length - 1, cursor + delta))
  }

  Timer {
    id: refreshTimer
    interval: 300
    onTriggered: root.refresh()
  }

  // Refresh whenever windows come, go, or change state, so the bar count
  // stays right even when tiles are closed with ordinary Hyprland bindings.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event.name
      if (name === "openwindow" || name === "closewindow" || name === "movewindowv2"
          || name === "changefloatingmode" || name === "fullscreen") refreshTimer.restart()
    }
  }

  Process {
    id: listProcess
    running: false
    stdout: StdioCollector { id: listStdout; waitForEnd: true }
    stderr: StdioCollector { id: listStderr; waitForEnd: true }
    onStarted: root.listStarted = true
    // Quickshell never emits `exited` for a command that cannot start.
    onRunningChanged: if (!running && !root.listStarted) root.showListError(root.missingCommand)
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyList(listStdout.text)
      else root.showListError(Model.errorLine(listStderr.text, "mosaic list failed"))
    }
  }

  Process {
    id: actionProcess
    running: false
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onStarted: root.actionStarted = true
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
      onMoveRequested: function(dx, dy) { root.moveCursor(dy) }
      onActivateRequested: if (root.cursorActive) root.focusTile(root.selectedTile)
      onDeleteRequested: if (root.cursorActive) root.removeTile(root.selectedTile)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "a" || t === "A") root.startAdding()
        else if (t === "d" && root.cursorActive) root.removeTile(root.selectedTile)
        else if (t === "D" && root.cursorActive && root.selectedTile) root.closeSession(root.selectedTile.session)
        else if (t === "c" || t === "C") root.run(["contain"], "Containing fullscreen")
        else if (t === "r" || t === "R") root.refresh()
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
            detail: root.busyLabel !== "" ? root.busyLabel + "…" : ""
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
              text: "ADD TILE  ·  A"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            TextField {
              id: urlField
              width: parent.width
              placeholderText: "Web address, such as twitch.tv/name"
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
                placeholderText: "Session (default)"
                foreground: root.foreground
                font.family: root.fontFamily
                onAccepted: root.addTile()
                Keys.onEscapePressed: keyCatcher.forceActiveFocus()
              }
              Button {
                text: "Add"
                iconText: "󰐕"
                foreground: root.foreground
                enabled: root.busyLabel === ""
                onClicked: root.addTile()
              }
            }
          }

          Notice {
            visible: root.status !== ""
            text: root.status
            warning: root.statusIsError
          }

          Button {
            visible: Model.anyUncontained(root.tiles)
            width: parent.width
            text: "Contain fullscreen in every tile  C"
            iconText: "󰊓"
            foreground: root.foreground
            onClicked: root.run(["contain"], "Containing fullscreen")
          }

          Text {
            width: parent.width
            text: "↑↓ select  ·  Enter focus  ·  X remove  ·  ⇧D close session  ·  R refresh"
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
