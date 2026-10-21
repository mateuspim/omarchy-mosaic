import QtQuick
import qs.Commons
import qs.Commons as Commons

// Offscreen stand-in for qs.Ui's KeyboardPanel. Without a compositor there is
// no layer-shell PanelWindow, so the preview draws the popup card as a plain
// Item that tests/Preview.qml finds by objectName and moves into its window.
Rectangle {
  id: root
  objectName: "mosaicPreviewPanel"

  property Item anchorItem
  property QtObject bar
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property var borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
  property bool open: false
  property Item focusTarget: null
  default property alias contentItem: holder.children

  function fittedContentWidth(width, cap) { return Math.round(Number(width) || 1) }
  function fittedContentHeight(height, cap) { return Math.round((Number(height) || 0) + padding * 2 + border.width * 2) }
  function cappedContentHeight(height) { return height }
  function close() { if (owner && "close" in owner) owner.close() }

  width: contentWidth
  height: contentHeight
  color: Commons.Color.popups.background
  border.color: Commons.Color.popups.border
  border.width: Math.max(1, Style.space(2))
  radius: Style.cornerRadius

  Item {
    id: holder
    anchors.fill: parent
    anchors.margins: root.padding + root.border.width
  }
}
