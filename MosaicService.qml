import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Model.js" as Model

// The Mosaic engine. The shell creates exactly one while the plugin is
// enabled and destroys it on disable and on every plugin reload; the bar
// widget reaches it with `bar.shell.serviceFor("pym.mosaic")`. For now it
// is read-only: it keeps the v1 tile list current from Hyprland and
// tiles.json and the v1 web app list current from the desktop entries, and
// actions still go through the mosaic CLI.
Scope {
  id: root

  // `mosaic list --json`, version 1, rebuilt whenever Hyprland or the store
  // changes.
  property var list: ({ version: Model.LIST_VERSION, sessions: [] })
  property var records: []
  // `mosaic webapps --json`, version 1, rebuilt whenever the installed
  // applications change.
  property var webapps: ({ version: Model.WEBAPPS_VERSION, webapps: [] })

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
    var next = Model.buildList(clients, monitors, records)
    if (JSON.stringify(next) !== JSON.stringify(list)) list = next
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

  Component.onCompleted: {
    refresh()
    rebuildWebapps()
  }

  // Coalesces the burst of events one window change produces.
  Timer {
    id: refreshTimer
    interval: 150
    onTriggered: {
      Hyprland.refreshToplevels()
      Hyprland.refreshMonitors()
      store.reload()
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

  FileView {
    id: store
    path: root.storePath
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
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
