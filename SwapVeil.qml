import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Model.js" as Model

// Covers a tile while a swap in place loads its new page (SwapVeilArt),
// and lifts once the extension reports the tab on the new site with a
// title of its own (Model.navigationSettled). It shows for at least
// `shortest` ms, so the animation reads instead of flickering, and at most
// `longest`. Clicks go through it, and it never takes the keyboard.
Scope {
  id: root

  // The MosaicService that owns this veil.
  required property QtObject service

  readonly property int shortest: 900
  readonly property int longest: 6000

  property string address: ""
  property string url: ""
  property string oldTitle: ""
  property var rect: null
  property bool opened: false
  property bool settled: false

  readonly property var targetScreen: {
    if (!rect) return null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === rect.monitor) return screens[i]
    }
    return null
  }
  readonly property var tab: address !== "" ? Model.tileTab(service.extensionCheck, service.bridges, address) : null

  // Covers `tile` (a list tile) while it goes to `url`.
  function show(tile, url) {
    root.address = tile.address
    root.url = url
    root.oldTitle = tile.title || ""
    root.rect = null
    root.opened = false
    root.settled = false
    art.label = Model.tileLabel({ url: url })
    clientsQuery.running = true
    monitorsQuery.running = true
    longestTimer.restart()
  }

  function geometryReady() {
    if (clientsQuery.running || monitorsQuery.running || root.address === "") return
    root.rect = Model.tileRect(clientsOut.text, monitorsOut.text, root.address)
    if (!root.rect || !root.targetScreen) return lift()
    root.opened = true
    art.start()
    shortestTimer.restart()
  }

  // Ends the veil once the page arrived and the shortest time is up.
  function check() {
    if (!root.opened || root.settled || shortestTimer.running) return
    if (Model.navigationSettled(root.tab, root.url, root.oldTitle)) finish()
  }

  function finish() {
    root.settled = true
    longestTimer.stop()
    art.finish()
  }

  function lift() {
    shortestTimer.stop()
    longestTimer.stop()
    root.opened = false
    root.address = ""
  }

  onTabChanged: check()

  Timer {
    id: shortestTimer
    interval: root.shortest
    onTriggered: root.check()
  }

  Timer {
    id: longestTimer
    interval: root.longest
    onTriggered: root.opened ? root.finish() : root.lift()
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

  PanelWindow {
    visible: root.opened && root.rect !== null && root.targetScreen !== null
    screen: root.targetScreen
    anchors { top: true; left: true }
    margins.top: root.rect ? root.rect.y : 0
    margins.left: root.rect ? root.rect.x : 0
    implicitWidth: root.rect ? root.rect.width : 1
    implicitHeight: root.rect ? root.rect.height : 1
    color: "transparent"
    WlrLayershell.namespace: "pym-mosaic-veil"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Empty: every click reaches the tile underneath.
    mask: Region {}

    SwapVeilArt {
      id: art
      anchors.fill: parent
      onFinished: root.lift()
    }
  }
}
