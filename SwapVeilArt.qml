import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons

// What SwapVeil draws over a tile while its page changes, after Omarchy's
// boot screen: the Omarchy wordmark, with a light sweeping across it, over
// a thin bar that eases forward like the boot progress and fills when the
// page has arrived (`finish()`). `label` names where the tile is going.
Item {
  id: root

  property string label: ""
  // 0 to 1. Eases towards `waitLimit` on its own, like the boot screen's
  // fake progress, and to 1 on finish().
  property real progress: 0
  readonly property real waitLimit: 0.7
  signal finished()

  readonly property string logoPath: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/logo.svg"
  readonly property real logoWidth: Math.max(Style.space(80), Math.min(width * 0.5, Style.space(360)))

  // Starts the animation from the beginning.
  function start() {
    finishing.stop()
    progress = 0
    opacity = 0
    entrance.restart()
    waiting.restart()
  }

  // The page arrived: fill the bar, then fade out and emit finished().
  function finish() {
    if (finishing.running) return
    waiting.stop()
    finishing.restart()
  }

  NumberAnimation on opacity { id: entrance; running: false; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }

  NumberAnimation {
    id: waiting
    target: root
    property: "progress"
    to: root.waitLimit
    duration: 2500
    easing.type: Easing.OutCubic
  }

  SequentialAnimation {
    id: finishing
    NumberAnimation { target: root; property: "progress"; to: 1; duration: 220; easing.type: Easing.OutCubic }
    PauseAnimation { duration: 120 }
    NumberAnimation { target: root; property: "opacity"; to: 0; duration: 260; easing.type: Easing.InCubic }
    ScriptAction { script: root.finished() }
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Color.menu.background
  }

  Column {
    anchors.centerIn: parent
    spacing: Style.space(18)

    Item {
      id: logo
      width: root.logoWidth
      height: Math.round(width * 285 / 1215)
      anchors.horizontalCenter: parent.horizontalCenter

      // The wordmark's shape, used as a mask over `paint`.
      Image {
        id: shape
        anchors.fill: parent
        source: "file://" + root.logoPath
        sourceSize.width: Math.ceil(parent.width * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: false
        layer.enabled: true
      }

      // The theme's text colour, dimmed, with a brighter band sweeping
      // across it.
      Item {
        id: paint
        anchors.fill: parent
        visible: false
        layer.enabled: true
        clip: true

        Rectangle {
          anchors.fill: parent
          color: Color.menu.text
          opacity: 0.5
        }

        Rectangle {
          id: band
          width: parent.width * 0.4
          height: parent.height * 3
          anchors.verticalCenter: parent.verticalCenter
          rotation: 18
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Color.menu.text }
            GradientStop { position: 1.0; color: "transparent" }
          }
          NumberAnimation on x {
            from: -band.width
            to: logo.width
            duration: 1100
            loops: Animation.Infinite
            easing.type: Easing.InOutSine
          }
        }
      }

      MultiEffect {
        anchors.fill: parent
        source: paint
        maskEnabled: true
        maskSource: shape
        maskThresholdMin: 0.4
        maskSpreadAtMin: 0.2
        visible: shape.status === Image.Ready
      }

      // Without the logo file, the name.
      Text {
        anchors.centerIn: parent
        visible: shape.status === Image.Error
        text: "omarchy"
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.display
        font.bold: true
      }
    }

    Rectangle {
      id: track
      width: root.logoWidth * 0.5
      height: Math.max(2, Style.space(3))
      radius: height / 2
      anchors.horizontalCenter: parent.horizontalCenter
      color: Util.alpha(Color.menu.text, 0.15)

      Rectangle {
        width: parent.width * root.progress
        height: parent.height
        radius: parent.radius
        color: Color.accent
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(implicitWidth, root.width - Style.space(32))
      visible: root.label !== ""
      textFormat: Text.PlainText
      text: root.label
      color: Util.alpha(Color.menu.text, 0.6)
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignHCenter
    }
  }
}
