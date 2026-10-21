import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "plugin" as Mosaic

// Offscreen visual review: draws the Mosaic panel for each scene and saves
// one PNG per scene into MOSAIC_PREVIEW_DIR. Run through tests/preview.sh,
// which swaps in the KeyboardPanel stand-in and hands the panel the fake
// service (tests/offscreen/FakeService.qml) through a fake bar.
ShellRoot {
  id: root

  // view: the panel tab; cursor: the selected row, or -1 for none.
  readonly property var scenes: [
    { name: "tiles", view: "tiles", cursor: 1, settings: { audioFollowsFocus: false } },
    { name: "layouts", view: "layouts", cursor: 2, settings: {} },
    { name: "saved", view: "saved", cursor: 0, settings: {} },
    { name: "extension", view: "extension", cursor: -1, settings: {} }
  ]
  property int sceneIndex: 0
  property Item card: null

  TestCase { id: finder; when: false }

  Mosaic.FakeService { id: fakeService }

  QtObject {
    id: fakeShell
    function serviceFor(id) { return id === "pym.mosaic" ? fakeService : null }
    function updateEntryInline(id, settings) { console.log("preview: settings not saved") }
  }

  QtObject {
    id: fakeBar
    property QtObject shell: fakeShell
    property string position: "top"
    property bool vertical: false
    property int barSize: Style.bar.sizeHorizontal
    property color foreground: Commons.Color.foreground
    property color barForeground: Commons.Color.foreground
    property color urgent: Commons.Color.urgent
    property color background: Commons.Color.popups.background
    property string fontFamily: Style.font.family
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function targetBelongsToWindow() { return false }
    function switchPanelFrom(owner, direction) { return false }
  }

  Mosaic.Panel {
    id: widget
    settings: ({ swapKey: "", recoverStreams: true })
    bar: fakeBar
  }

  FloatingWindow {
    title: "Mosaic · sample preview"
    implicitWidth: 560
    implicitHeight: 1500
    color: Commons.Color.background
    Item { id: mount; anchors.fill: parent; anchors.margins: 20 }
  }

  function applyScene(scene) {
    widget.settings = Object.assign({ swapKey: "", recoverStreams: true }, scene.settings)
    widget.setView(scene.view)
    widget.cursor = Math.max(0, scene.cursor)
    widget.cursorActive = scene.cursor >= 0
  }

  function capture() {
    if (sceneIndex >= scenes.length) {
      console.log("MOSAIC_PREVIEW_OK")
      Qt.quit()
      return
    }
    applyScene(scenes[sceneIndex])
    // grabToImage draws on a later frame, so change the scene on one tick
    // and grab on the next.
    Qt.callLater(function() { grabTimer.restart() })
  }

  Timer {
    id: grabTimer
    interval: 600
    onTriggered: {
      var name = root.scenes[root.sceneIndex].name
      var ok = root.card.grabToImage(function(result) {
        var path = Quickshell.env("MOSAIC_PREVIEW_DIR") + "/" + name + ".png"
        if (!result.saveToFile(path)) {
          console.error("MOSAIC_PREVIEW_FAILED: cannot save " + path)
          Qt.exit(1)
          return
        }
        root.sceneIndex++
        root.capture()
      })
      if (!ok) { console.error("MOSAIC_PREVIEW_FAILED: grab"); Qt.exit(1) }
    }
  }

  Timer {
    interval: 400
    running: true
    onTriggered: {
      root.card = finder.findChild(widget, "mosaicPreviewPanel")
      if (!root.card) { console.error("MOSAIC_PREVIEW_FAILED: no panel stand-in"); Qt.exit(1); return }
      root.card.parent = mount
      widget.open()
      root.capture()
    }
  }
}
