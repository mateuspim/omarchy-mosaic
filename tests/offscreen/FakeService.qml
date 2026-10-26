import QtQuick
import "Model.js" as Model

// Offscreen stand-in for MosaicService.qml, copied beside the plugin by
// tests/preview.sh: the properties and functions the panel reads, filled with sample sessions, web apps, layouts, saved sessions
// and a connected browser extension. It never talks to Hyprland, the browser
// or the native host, and every action only logs. Derived state goes through
// the same Model.js functions the real service uses, so the panel draws what
// it would draw for this data.
QtObject {
  id: root

  // Sample tiles: site roots and made-up titles, no personal channels.
  property var list: ({ version: 1, sessions: [
    { name: "streams", tiles: [
      { index: 1, address: "0x5a1e01", url: "https://www.twitch.tv", title: "Speedrun relay - Twitch", monitor: "DP-4", workspace: 8, state: "contained" },
      { index: 2, address: "0x5a1e02", url: "https://kick.com", title: "Kick", monitor: "DP-4", workspace: 8, state: "contained" },
      { index: 3, address: "0x5a1e03", url: "https://www.youtube.com", title: "Live coverage - YouTube", monitor: "DP-4", workspace: 8, state: "contained" }
    ] },
    { name: "music", tiles: [
      { index: 4, address: "0x5a1e04", url: "https://music.youtube.com", title: "Night drive - YouTube Music", monitor: "DP-5", workspace: 2, state: "contained" }
    ] }
  ] })

  property var webapps: ({ version: 1, webapps: [
    { id: "Twitch", name: "Twitch", url: "https://twitch.tv", icon: "" },
    { id: "Kick", name: "Kick", url: "https://kick.com", icon: "" },
    { id: "YouTube", name: "YouTube", url: "https://youtube.com", icon: "" },
    { id: "YouTubeMusic", name: "YouTube Music", url: "https://music.youtube.com", icon: "" },
    { id: "Discord", name: "Discord", url: "https://discord.com/channels/@me", icon: "" }
  ] })

  // Settings the panel binds onto the service.
  property string swapKey: ""
  property string browser: ""
  property string hiddenWebapps: ""
  property bool audioFollowsFocus: false
  property bool autoContain: false
  property bool recoverStreams: true
  property string recoverSites: Model.RECOVERY_SITES
  property bool addOnFocusedWorkspace: false

  property bool busy: false
  property string busyLabel: ""
  property QtObject panel: null
  property string boundSwapKey: "SUPER + SHIFT + S"
  property string swapKeyError: ""
  property string layoutError: ""
  property string savedError: ""
  property string extensionError: ""
  property bool verifying: false

  property var layoutState: Model.parseLayouts(JSON.stringify({ version: 2,
    workspaces: { "8": { layout: "custom:three", before: "dwindle" }, "2": { layout: "grid", before: "dwindle" } },
    custom: { three: { name: "Three", tree: { split: "row", sizes: [25, 50, 25], children: [{}, {}, {}] }, main: 2 } } }))
  readonly property var layoutWorkspaces: Model.layoutWorkspaceRows([
    { id: 1, monitor: "DP-5", windows: 2 }, { id: 2, monitor: "DP-5", windows: 1 },
    { id: 8, monitor: "DP-4", windows: 3 }, { id: 9, monitor: "DP-4", windows: 0 }
  ], layoutState)

  property var savedSessions: Model.parseSaved(JSON.stringify({ version: 1, sessions: {
    streams: { monitor: "DP-4", workspace: 8, layout: "custom:three", login: true, tiles: [
      { url: "https://www.twitch.tv", volume: 1, muted: false },
      { url: "https://kick.com", volume: 0.4, muted: false },
      { url: "https://www.youtube.com", volume: 1, muted: true } ] },
    music: { monitor: "DP-5", workspace: 2, layout: "grid", login: false, tiles: [
      { url: "https://music.youtube.com", volume: 0.6, muted: false } ] } } }))

  // `mosaic-native-host status`, with sample paths.
  property var extensionSetup: ({ extensionId: "ibcnbknhphdnlpfglnhelicnpnnmepbo", extension: "/opt/mosaic/extension",
    host: "/opt/mosaic/bin/mosaic-native-host", socket: "/run/user/1000/pym-mosaic.sock",
    browsers: [{ name: "Chromium", folder: "chromium", registered: true }],
    flags: [{ file: "/opt/config/chromium-flags.conf", loaded: true }] })
  readonly property string extensionDir: "/opt/mosaic/extension"
  readonly property string extensionVersion: "0.5.5"
  readonly property bool extensionOutdated: false

  // One connected browser whose app windows are the four tiles.
  property var bridges: [{ browser: "/usr/lib/chromium/chromium", extension: "0.5.5", script: "background-10.js",
    features: ["mute", "volume", "follow", "navigate", "reload", "media", "favicon", "stream", "extensions", "fullscreen"],
    windows: [
      { id: 11, type: "app", focused: false, tabs: [{ id: 101, url: "https://www.twitch.tv", title: "Speedrun relay - Twitch", favIconUrl: "", audible: true, muted: false, volume: 1,
        stream: { state: "playing", reason: "", detail: "", since: 0 } }] },
      { id: 12, type: "app", focused: true, tabs: [{ id: 102, url: "https://kick.com", title: "Kick", favIconUrl: "", audible: true, muted: false, volume: 0.4,
        stream: { state: "playing", reason: "", detail: "", since: 0 } }] },
      { id: 13, type: "app", focused: false, tabs: [{ id: 103, url: "https://www.youtube.com", title: "Live coverage - YouTube", favIconUrl: "", audible: false, muted: true, volume: 1, stream: null }] },
      { id: 14, type: "app", focused: false, tabs: [{ id: 104, url: "https://music.youtube.com", title: "Night drive - YouTube Music", favIconUrl: "", audible: true, muted: false, volume: 0.6, stream: null }] }
    ] }]
  readonly property string extensionState: Model.extensionState(extensionSetup, bridges)
  readonly property var extensionCheck: Model.matchTiles(Model.shapeList(list).tiles, bridges, {}, "", [])
  readonly property var tileAudio: Model.tileAudio(extensionCheck, bridges)
  property var tileVolumes: ({ "0x5a1e02": 0.4, "0x5a1e04": 0.6 })
  // The Kick tile's stream came back after one reload.
  property var recovery: ({ "0x5a1e02": { tries: [], waiting: 0, stalled: false, recovered: 1 } })

  signal actionFinished(string label, string error, string message)

  function sessionChoice(session) {
    var workspace = Model.sessionWorkspace(list, session)
    return workspace === null ? "default" : Model.workspaceChoice(layoutState, workspace)
  }
  function canNavigate(address) { return !!tileAudio[address] }
  function refresh() {}
  function refreshExtension() {}
  function preview(name) { console.log("preview: " + name + " (ignored)"); return "" }
  function focus(target) { return preview("focus") }
  function add(targets, options, label) { return preview("add") }
  function replace(tile, target, options, label) { return preview("replace") }
  function remove(targets) { return preview("remove") }
  function close(session) { return preview("close") }
  function contain(session) { return preview("contain") }
  function saveSession(session) { return preview("save") }
  function toggleTileMute(address) { return preview("mute") }
  function setTileVolume(address, level) { return preview("volume") }
  function stepTileVolume(address, delta) { return preview("volume") }
  function reloadTile(address) { return preview("reload") }
  function openExtensionsPage() { return preview("extensions page") }
}
