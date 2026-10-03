import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// A card drawn over a tile that swaps its web app: numbered web app
// buttons, and the tile's address, ready to edit. The swap key opens it
// (`omarchy-shell pym.mosaic swap`). It only exists while it is open, so it
// never sits over a video catching clicks.
Scope {
  id: root

  // The MosaicService that owns this card.
  required property QtObject service

  // The tile being swapped (a list tile with its session), and where it
  // sits on its monitor (Model.tileRect).
  property var tile: null
  property var rect: null
  property bool opened: false
  property string error: ""

  readonly property var allApps: Model.shapeWebapps(service.webapps).apps
  readonly property var apps: Model.visibleWebapps(allApps, service.hiddenWebapps)
  readonly property var targetScreen: {
    if (!rect) return null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === rect.monitor) return screens[i]
    }
    return null
  }
  readonly property string tileLabel: tile ? Model.tileLabel(tile) : ""
  // The web app the tile shows now, if any; its tile is dimmed.
  readonly property var currentApp: {
    var site = tile ? Model.siteOf(tile.url) : ""
    for (var i = 0; site !== "" && i < allApps.length; i++) {
      if (Model.siteOf(allApps[i].url) === site) return allApps[i]
    }
    return null
  }
  // The site's logo: its web app's icon, else the tab's favicon from the
  // extension; "" when there is neither, and the header shows only the
  // title.
  readonly property string logoSource: {
    if (currentApp && currentApp.icon) return iconSource(currentApp.icon)
    var tab = tile ? Model.tileTab(service.extensionCheck, service.bridges, tile.address) : null
    return tab && /^(https?|data):/.test(tab.favIconUrl || "") ? tab.favIconUrl : ""
  }
  readonly property color dim: Util.alpha(Color.menu.text, 0.55)

  function iconSource(icon) {
    if (!icon) return ""
    if (icon.indexOf("/") === 0) return "file://" + icon
    return Quickshell.iconPath(icon, true)
  }

  // Opens the card over `tile` once its geometry is known.
  function openFor(tile) {
    root.tile = tile
    root.rect = null
    root.error = ""
    root.opened = false
    clientsQuery.running = true
    monitorsQuery.running = true
    geometryTimeout.restart()
  }

  function close() {
    root.opened = false
    geometryTimeout.stop()
  }

  function geometryReady() {
    if (clientsQuery.running || monitorsQuery.running || !root.tile) return
    geometryTimeout.stop()
    root.rect = Model.tileRect(clientsOut.text, monitorsOut.text, root.tile.address)
    if (!root.rect || !root.targetScreen) return root.notify("Cannot find that tile on screen")
    field.text = root.tile.url || ""
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // Replaces the tile with `url`; the card closes at once, and a failure
  // arrives as a notification, since the card is gone by then.
  function pick(url, label) {
    var tile = root.tile
    root.close()
    if (!tile || url === "" || url === tile.url) return
    var error = root.service.replace(tile.address, url, { browser: root.service.browser },
      "Replacing " + root.tileLabel + " with " + label)
    if (error) root.notify(error)
    else root.waitingFor = "Replacing " + root.tileLabel + " with " + label
  }

  function submitAddress() {
    var url = Model.resolveTarget(field.text, root.allApps)
    if (url === "") {
      root.error = "Enter a web address or web app name, such as twitch.tv/name"
      return
    }
    root.pick(url, field.text.trim())
  }

  function notify(text) {
    Quickshell.execDetached(["notify-send", "--app-name=Mosaic", "Mosaic", text])
  }

  // The label of the replace this card started, so its error can be shown.
  property string waitingFor: ""

  Connections {
    target: root.service
    function onActionFinished(label, error, message) {
      if (label !== root.waitingFor) return
      root.waitingFor = ""
      if (error) root.notify(error)
    }
  }

  Process {
    id: clientsQuery
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector { id: clientsOut; waitForEnd: true }
    onExited: root.geometryReady()
  }

  Process {
    id: monitorsQuery
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector { id: monitorsOut; waitForEnd: true }
    onExited: root.geometryReady()
  }

  Timer {
    id: geometryTimeout
    interval: 3000
    onTriggered: {
      clientsQuery.running = false
      monitorsQuery.running = false
      root.notify("Hyprland did not answer; the swap card could not open")
    }
  }

  PanelWindow {
    id: window
    visible: root.opened && root.rect !== null && root.targetScreen !== null
    screen: root.targetScreen
    anchors { top: true; left: true }
    margins.top: root.rect ? root.rect.y : 0
    margins.left: root.rect ? root.rect.x : 0
    implicitWidth: root.rect ? root.rect.width : 1
    implicitHeight: root.rect ? root.rect.height : 1
    color: "transparent"
    WlrLayershell.namespace: "pym-mosaic-swap"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      radius: Style.cornerRadius
    }

    // A click on the tile around the card closes it.
    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.max(Style.space(200), Math.min(Style.space(460), parent.width - Style.gapsOut * 2))
      height: Math.min(parent.height - Style.gapsOut * 2, content.implicitHeight + card.contentTopInset + card.contentBottomInset)
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding
      clip: true

      MouseArea { anchors.fill: parent }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          } else if (event.text >= "1" && event.text <= "9" && event.text.length === 1) {
            var app = root.apps[Number(event.text) - 1]
            if (app && app !== root.currentApp) root.pick(app.url, app.name)
            event.accepted = true
          } else if (event.text === "a" || event.text === "A" || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            field.forceActiveFocus()
            field.cursorPosition = field.text.length
            event.accepted = true
          }
        }

        ColumnLayout {
          id: content
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.topMargin: card.contentTopInset
          anchors.leftMargin: card.contentLeftInset
          anchors.rightMargin: card.contentRightInset
          spacing: Style.spacing.xxl

          // What the tile shows now, and how the swap will happen.
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.xl

            Rectangle {
              visible: currentIcon.status === Image.Ready
              Layout.preferredWidth: Style.space(40)
              Layout.preferredHeight: Style.space(40)
              radius: Style.cornerRadius
              color: Util.alpha(Color.menu.text, 0.06)
              border.width: 1
              border.color: Util.alpha(Color.menu.text, 0.12)
              Image {
                id: currentIcon
                anchors.centerIn: parent
                width: Style.space(24)
                height: Style.space(24)
                source: root.logoSource
                sourceSize.width: 64
                sourceSize.height: 64
                fillMode: Image.PreserveAspectFit
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.xxs
              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: "SWAP TILE" + (root.tile ? "  ·  " + root.tile.monitor + "  ·  workspace " + root.tile.workspace : "")
                color: root.dim
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                elide: Text.ElideRight
              }
              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: root.tileLabel
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }
            }

            Rectangle {
              readonly property bool inPlace: root.tile !== null && root.service.canNavigate(root.tile.address)
              Layout.alignment: Qt.AlignTop
              implicitWidth: modeText.implicitWidth + Style.space(14)
              implicitHeight: modeText.implicitHeight + Style.space(6)
              radius: height / 2
              color: inPlace ? Util.alpha(Color.accent, 0.16) : Util.alpha(Color.menu.text, 0.08)
              Text {
                id: modeText
                anchors.centerIn: parent
                text: parent.inPlace ? "In place" : "New window"
                color: parent.inPlace ? Color.accent : root.dim
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // The web apps, as an even grid of tiles.
          GridLayout {
            visible: root.apps.length > 0
            Layout.fillWidth: true
            columns: Math.max(1, Math.min(root.apps.length, Math.floor(content.width / Style.space(96))))
            columnSpacing: Style.spacing.md
            rowSpacing: Style.spacing.md

            Repeater {
              model: root.apps
              CursorSurface {
                id: appTile
                required property var modelData
                required property int index
                readonly property bool isCurrent: root.currentApp !== null && root.currentApp.url === modelData.url
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: appColumn.implicitHeight + Style.space(20)
                bordered: true
                hasCursor: appMouse.containsMouse && !isCurrent
                foreground: Color.menu.text
                opacity: isCurrent ? 0.45 : 1.0

                Column {
                  id: appColumn
                  anchors.centerIn: parent
                  spacing: Style.spacing.md
                  Image {
                    id: appIcon
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Style.space(28)
                    height: Style.space(28)
                    source: root.iconSource(appTile.modelData.icon)
                    sourceSize.width: 64
                    sourceSize.height: 64
                    fillMode: Image.PreserveAspectFit
                    visible: status === Image.Ready
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, appTile.width - Style.space(12))
                    textFormat: Text.PlainText
                    text: appTile.modelData.name
                    color: Color.menu.text
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                  }
                  KeyCap {
                    anchors.horizontalCenter: parent.horizontalCenter
                    label: appTile.isCurrent ? "now" : appTile.index < 9 ? String(appTile.index + 1) : ""
                    visible: label !== ""
                  }
                }

                MouseArea {
                  id: appMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: appTile.isCurrent ? Qt.ArrowCursor : Qt.PointingHandCursor
                  onClicked: if (!appTile.isCurrent) root.pick(appTile.modelData.url, appTile.modelData.name)
                }
              }
            }
          }

          TextField {
            id: field
            Layout.fillWidth: true
            placeholderText: "Web address or web app name"
            foreground: Color.menu.text
            font.family: Style.font.menuFamily
            onAccepted: root.submitAddress()
            Keys.onEscapePressed: keyCatcher.forceActiveFocus()
          }

          Text {
            visible: root.error !== ""
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: root.error
            color: Color.urgent
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // Keys, as key caps.
          Flow {
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.spacing.xl
            Repeater {
              model: field.activeFocus
                ? [["Enter", "replace"], ["Esc", "back"]]
                : (root.apps.length > 0 ? [["1–" + Math.min(9, root.apps.length), "web app"]] : [])
                  .concat([["A", "edit address"], ["Esc", "cancel"]])
              Row {
                required property var modelData
                spacing: Style.spacing.sm
                KeyCap { label: parent.modelData[0]; anchors.verticalCenter: parent.verticalCenter }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: parent.modelData[1]
                  color: root.dim
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }
    }
  }

  // A small key label, like a key on the keyboard.
  component KeyCap: Rectangle {
    property string label: ""
    implicitWidth: Math.max(implicitHeight, capText.implicitWidth + Style.space(10))
    implicitHeight: capText.implicitHeight + Style.space(4)
    radius: Math.max(2, Style.cornerRadius / 2)
    color: Util.alpha(Color.menu.text, 0.06)
    border.width: 1
    border.color: Util.alpha(Color.menu.text, 0.22)
    Text {
      id: capText
      anchors.centerIn: parent
      text: parent.label
      color: Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
    }
  }
}
