.pragma library

// Pure helpers for the Mosaic bar widget. Kept free of QML so node can test
// them (see tests/model.test.js).

// The `mosaic list --json` format versions this widget understands.
var SUPPORTED_VERSIONS = [1]
var LIST_VERSION = 1
var WEBAPPS_VERSION = 1
var DEFAULT_SESSION = "default"
// Hyprland tag on every tile; `mosaic-<session>` names its session.
var TAG = "mosaic"

// The session a client belongs to, from its tags, or null when it is not a
// tile. Mirrors `session::session_of` in the Rust CLI.
function sessionOf(tags) {
  var list = stringList(tags)
  if (list.indexOf(TAG) === -1) return null
  var prefix = TAG + "-"
  for (var i = 0; i < list.length; i++) {
    if (list[i].indexOf(prefix) === 0) return list[i].slice(prefix.length)
  }
  return DEFAULT_SESSION
}

// A plain array of strings from any array-like, such as a list that comes
// from C++ or from another JavaScript realm, where `instanceof Array` fails.
function stringList(value) {
  var list = []
  if (!value || typeof value === "string" || typeof value.length !== "number") return list
  for (var i = 0; i < value.length; i++) list.push(String(value[i]))
  return list
}

// A client from Hyprland's raw client JSON (`hyprctl -j clients`, or a
// Quickshell toplevel's lastIpcObject), with the fields the list needs.
function clientFromIpc(object) {
  if (!object || typeof object.address !== "string" || object.address === "") return null
  return {
    address: object.address,
    title: String(object.title || ""),
    workspace: object.workspace && object.workspace.id !== undefined ? Number(object.workspace.id) : 0,
    monitor: object.monitor !== undefined && object.monitor !== null ? Number(object.monitor) : -1,
    tags: stringList(object.tags),
    floating: object.floating === true,
    fullscreen: Number(object.fullscreen || 0),
    fullscreenClient: Number(object.fullscreenClient || 0)
  }
}

// Records from tiles.json, `{ "tiles": [{ address, session, url }] }`. An
// unreadable file is an empty store, because the tags stay authoritative.
function parseStore(text) {
  var parsed
  try {
    parsed = JSON.parse(String(text || ""))
  } catch (error) {
    return []
  }
  var source = parsed && parsed.tiles instanceof Array ? parsed.tiles : []
  var records = []
  for (var i = 0; i < source.length; i++) {
    var tile = source[i]
    if (!tile || typeof tile.address !== "string" || typeof tile.session !== "string"
        || typeof tile.url !== "string") continue
    records.push({ address: tile.address, session: tile.session, url: tile.url })
  }
  return records
}

function tileState(client) {
  if (client.floating) return "floating"
  if (client.fullscreen !== 0) return "fullscreen"
  if (client.fullscreenClient === 2) return "contained"
  return "uncontained"
}

function compareText(a, b) {
  return a < b ? -1 : a > b ? 1 : 0
}

// The v1 `mosaic list --json` object from live clients, monitors
// ([{ id, name }]) and store records. Sessions are sorted by name, tiles by
// store order and then address, and `index` is 1-based across all sessions.
// Mirrors `session::tiles` and `list` in the Rust CLI.
function buildList(clients, monitors, records) {
  var entries = []
  for (var i = 0; i < clients.length; i++) {
    var client = clients[i]
    var session = client ? sessionOf(client.tags) : null
    if (session === null) continue
    var position = -1
    for (var r = 0; r < records.length; r++) {
      if (records[r].address === client.address) { position = r; break }
    }
    var monitor = "?"
    for (var m = 0; m < monitors.length; m++) {
      if (monitors[m].id === client.monitor) { monitor = String(monitors[m].name); break }
    }
    entries.push({
      order: position === -1 ? Infinity : position,
      session: session,
      tile: {
        index: 0,
        address: client.address,
        url: position === -1 ? null : records[position].url,
        title: client.title,
        monitor: monitor,
        workspace: client.workspace,
        state: tileState(client)
      }
    })
  }
  entries.sort(function(a, b) {
    return compareText(a.session, b.session)
      || (a.order === b.order ? 0 : a.order < b.order ? -1 : 1)
      || compareText(a.tile.address, b.tile.address)
  })
  var sessions = []
  for (var e = 0; e < entries.length; e++) {
    entries[e].tile.index = e + 1
    var last = sessions[sessions.length - 1]
    if (!last || last.name !== entries[e].session) {
      last = { name: entries[e].session, tiles: [] }
      sessions.push(last)
    }
    last.tiles.push(entries[e].tile)
  }
  return { version: LIST_VERSION, sessions: sessions }
}

// Parses `mosaic list --json` into { sessions, tiles, error }; see shapeList.
function parseList(text) {
  var parsed
  try {
    parsed = JSON.parse(String(text || ""))
  } catch (error) {
    return { sessions: [], tiles: [], error: "Unexpected output from mosaic list" }
  }
  return shapeList(parsed)
}

// Shapes a v1 list object into { sessions, tiles, error }. `tiles` is every
// tile in listing order, each with its session name attached, which is the
// order keyboard navigation walks.
function shapeList(parsed) {
  if (!parsed || SUPPORTED_VERSIONS.indexOf(parsed.version) === -1) {
    return { sessions: [], tiles: [], error: "This mosaic version is not supported; update mosaic and the widget together" }
  }
  var sessions = []
  var tiles = []
  var source = parsed.sessions instanceof Array ? parsed.sessions : []
  for (var i = 0; i < source.length; i++) {
    var name = String(source[i].name || DEFAULT_SESSION)
    var sessionTiles = []
    var raw = source[i].tiles instanceof Array ? source[i].tiles : []
    for (var j = 0; j < raw.length; j++) {
      var tile = {
        index: Number(raw[j].index),
        address: String(raw[j].address || ""),
        url: raw[j].url ? String(raw[j].url) : "",
        title: String(raw[j].title || ""),
        monitor: String(raw[j].monitor || "?"),
        workspace: Number(raw[j].workspace),
        state: String(raw[j].state || ""),
        session: name,
        position: tiles.length
      }
      sessionTiles.push(tile)
      tiles.push(tile)
    }
    sessions.push({ name: name, tiles: sessionTiles })
  }
  return { sessions: sessions, tiles: tiles, error: "" }
}

// The URL a desktop entry's parsed Exec argv opens as a web app, or "" when
// it is not one: the first http(s) word after `omarchy-launch-webapp`, else
// a browser's first `--app=` value. Mirrors `webapps::web_url`.
function webappUrl(command) {
  var words = stringList(command)
  var isWeb = function(url) { return url.indexOf("https://") === 0 || url.indexOf("http://") === 0 }
  for (var i = 0; i < words.length; i++) {
    if (words[i].split("/").pop() !== "omarchy-launch-webapp") continue
    for (var j = i + 1; j < words.length; j++) {
      if (isWeb(words[j])) return words[j]
    }
    return ""
  }
  for (var k = 0; k < words.length; k++) {
    if (words[k].indexOf("--app=") === 0) return isWeb(words[k].slice(6)) ? words[k].slice(6) : ""
  }
  return ""
}

// A web app from a desktop entry ({ id, name, icon, noDisplay, command }, as
// Quickshell's DesktopEntries gives them), or null when it is not one.
function webappFromEntry(entry) {
  if (!entry || entry.noDisplay) return null
  var id = String(entry.id || "")
  var name = String(entry.name || "")
  var url = webappUrl(entry.command)
  if (id === "" || name === "" || url === "") return null
  return { icon: String(entry.icon || ""), id: id, name: name, url: url }
}

// The v1 `mosaic webapps --json` object from desktop entries, sorted by name
// without case. DesktopEntries already lets a user entry hide a system entry
// with the same id and drops Hidden and NoDisplay entries.
function buildWebapps(entries) {
  var apps = []
  var source = entries || []
  for (var i = 0; i < source.length; i++) {
    var app = webappFromEntry(source[i])
    if (app) apps.push(app)
  }
  apps.sort(function(a, b) {
    return compareText(a.name.toLowerCase(), b.name.toLowerCase()) || compareText(a.id, b.id)
  })
  return { version: WEBAPPS_VERSION, webapps: apps }
}

// Shapes a v1 web app object into { apps, error }.
function shapeWebapps(parsed) {
  if (!parsed || SUPPORTED_VERSIONS.indexOf(parsed.version) === -1) {
    return { apps: [], error: "This mosaic version is not supported; update mosaic and the widget together" }
  }
  var apps = []
  var source = Array.isArray(parsed.webapps) ? parsed.webapps : []
  for (var i = 0; i < source.length; i++) {
    if (!source[i].url || !source[i].name) continue
    apps.push({
      id: String(source[i].id || source[i].name),
      name: String(source[i].name),
      url: String(source[i].url),
      icon: String(source[i].icon || "")
    })
  }
  return { apps: apps, error: "" }
}

function findWebapp(apps, text) {
  var name = String(text || "").trim().toLowerCase()
  if (name === "") return null
  for (var i = 0; i < apps.length; i++) {
    if (apps[i].name.toLowerCase() === name || apps[i].id.toLowerCase() === name) return apps[i]
  }
  return null
}

// The hiddenWebapps setting: web app names or ids separated by commas,
// compared without case.
function nameList(text) {
  var names = []
  var parts = String(text || "").split(",")
  for (var i = 0; i < parts.length; i++) {
    var name = parts[i].trim().toLowerCase()
    if (name !== "" && names.indexOf(name) === -1) names.push(name)
  }
  return names
}

function isHidden(app, hidden) {
  return hidden.indexOf(app.name.toLowerCase()) !== -1 || hidden.indexOf(app.id.toLowerCase()) !== -1
}

// The web apps that get a button: every one not named in `hiddenText`.
function visibleWebapps(apps, hiddenText) {
  var hidden = nameList(hiddenText)
  return apps.filter(function(app) { return !isHidden(app, hidden) })
}

// The hiddenWebapps setting with `app` added, keeping what the user typed.
function hideWebapp(hiddenText, app) {
  var text = String(hiddenText || "").trim()
  if (!app || isHidden(app, nameList(text))) return text
  return text === "" ? app.name : text.replace(/,\s*$/, "") + ", " + app.name
}

// One row per name in the hiddenWebapps setting, in the order written, with
// the web app it matches, or null when no installed web app has that name.
function hiddenEntries(apps, hiddenText) {
  var names = nameList(hiddenText)
  var entries = []
  var seen = []
  for (var i = 0; i < names.length; i++) {
    var app = null
    for (var j = 0; j < apps.length; j++) {
      if (isHidden(apps[j], [names[i]])) { app = apps[j]; break }
    }
    // A web app written by both name and id gets a single row.
    if (app && seen.indexOf(app) !== -1) continue
    if (app) seen.push(app)
    entries.push({ key: names[i], label: app ? app.name : names[i], app: app })
  }
  return entries
}

// The hiddenWebapps setting without `entry`, and without any other name for
// the same web app, keeping the rest as the user typed it.
function showWebapp(hiddenText, entry) {
  var drop = [entry.key]
  if (entry.app) drop.push(entry.app.name.toLowerCase(), entry.app.id.toLowerCase())
  return String(hiddenText || "").split(",").map(function(part) { return part.trim() })
    .filter(function(part) { return part !== "" && drop.indexOf(part.toLowerCase()) === -1 })
    .join(", ")
}

// What the URL field means: a web app's name, or a web address.
function resolveTarget(text, apps) {
  var app = findWebapp(apps, text)
  return app ? app.url : normalizeUrl(text)
}

// Short label for a tile: host plus path for web URLs, else the page title.
function tileLabel(tile) {
  var match = /^https?:\/\/(?:www\.)?([^\/?#]+)([^?#]*)/.exec(tile.url || "")
  if (match) {
    var path = match[2].replace(/\/+$/, "")
    return match[1] + path
  }
  if (tile.title) return tile.title
  return tile.url || "Tile " + tile.index
}

function tileMeta(tile) {
  var parts = [tile.monitor + " · workspace " + tile.workspace]
  if (tile.state && tile.state !== "contained") parts.push(stateLabel(tile.state))
  return parts.join("  ·  ")
}

function stateLabel(state) {
  if (state === "uncontained") return "fullscreen not contained"
  if (state === "floating") return "floating"
  if (state === "fullscreen") return "fullscreen"
  return state
}

// Accepts what people type into the URL field: a bare host gets https://.
function normalizeUrl(text) {
  var url = String(text || "").trim()
  if (url === "" || /\s/.test(url)) return ""
  if (/^(https?|file):\/\//i.test(url)) return url
  if (/^[a-z][a-z0-9+.-]*:/i.test(url) && !/^[^:\/]+:\d+(\/|$)/.test(url)) return ""
  return "https://" + url
}

// Mirrors `session::valid_name` in mosaic. An empty name means the default.
function sessionName(text) {
  var name = String(text || "").trim()
  if (name === "") return DEFAULT_SESSION
  return /^[a-z0-9_-]{1,32}$/.test(name) ? name : ""
}

function summary(sessions, tiles) {
  if (tiles.length === 0) return "No tiles open"
  var tileText = tiles.length === 1 ? "1 tile" : tiles.length + " tiles"
  var sessionText = sessions.length === 1 ? "1 session" : sessions.length + " sessions"
  return tileText + "  ·  " + sessionText
}

function anyUncontained(tiles) {
  for (var i = 0; i < tiles.length; i++) {
    if (tiles[i].state === "uncontained") return true
  }
  return false
}

// { name, version } from the plugin's manifest.json text, or null.
function parseManifest(text) {
  try {
    var manifest = JSON.parse(String(text || ""))
    return manifest && manifest.name && manifest.version ? { name: String(manifest.name), version: String(manifest.version) } : null
  } catch (error) {
    return null
  }
}

// Clients from `hyprctl -j clients`, or null when the text is not that list.
function parseClients(text) {
  var parsed
  try {
    parsed = JSON.parse(String(text || ""))
  } catch (error) {
    return null
  }
  if (!Array.isArray(parsed)) return null
  var clients = []
  for (var i = 0; i < parsed.length; i++) {
    var client = clientFromIpc(parsed[i])
    if (client) clients.push(client)
  }
  return clients
}

// Whether `address` is the hex form Hyprland reports. Addresses are
// interpolated into Lua dispatch expressions, so nothing else is accepted.
// Mirrors `platform::selector`.
function validAddress(address) {
  return /^0x[0-9a-fA-F]+$/.test(String(address || ""))
}

// The Lua dispatch that focuses ("focus"), closes ("close"), contains
// fullscreen in ("contain"), or releases fullscreen containment of
// ("release") a window, or "" for an invalid address.
function dispatchExpression(action, address) {
  if (!validAddress(address)) return ""
  var window = 'window = "address:' + address + '"'
  if (action === "focus") return "hl.dsp.focus({ " + window + " })"
  if (action === "close") return "hl.dsp.window.close({ " + window + " })"
  if (action === "contain") return "hl.dsp.window.fullscreen_state({ internal = 0, client = 2, " + window + " })"
  if (action === "release") return "hl.dsp.window.fullscreen_state({ internal = 0, client = 0, " + window + " })"
  return ""
}

// Every tile of a v1 list, in listing order, with its session name.
function listTiles(list) {
  var tiles = []
  var sessions = list && Array.isArray(list.sessions) ? list.sessions : []
  for (var i = 0; i < sessions.length; i++) {
    var sessionTiles = Array.isArray(sessions[i].tiles) ? sessions[i].tiles : []
    for (var j = 0; j < sessionTiles.length; j++) {
      tiles.push({ session: sessions[i].name, index: sessionTiles[j].index, address: sessionTiles[j].address,
        state: sessionTiles[j].state, workspace: sessionTiles[j].workspace, url: sessionTiles[j].url })
    }
  }
  return tiles
}

// The tile a target names: its number in the list, or its window address.
function findTile(tiles, target) {
  var text = String(target === undefined || target === null ? "" : target).trim()
  var index = /^\+?\d+$/.test(text) ? Number(text) : -1
  for (var i = 0; i < tiles.length; i++) {
    if (tiles[i].index === index || tiles[i].address === text) return tiles[i]
  }
  return null
}

// Checks an optional session filter; "" or null means every session.
function sessionFilterError(session) {
  if (session === undefined || session === null || session === "") return ""
  return sessionName(session) === String(session) ? ""
    : "Invalid session name " + JSON.stringify(String(session)) + ": use up to 32 lowercase letters, digits, - or _"
}

// A plan for the engine: the Lua dispatches to run in order and the message
// to report once they all succeed, or an error, in which case nothing runs.
function plan(action, tiles, message) {
  var expressions = []
  for (var i = 0; i < tiles.length; i++) {
    var expression = dispatchExpression(action, tiles[i].address)
    if (expression === "") return { error: "Unexpected Hyprland window address " + JSON.stringify(String(tiles[i].address)) }
    expressions.push(expression)
  }
  return { error: "", expressions: expressions, message: message }
}

// `mosaic focus TILE`.
function planFocus(list, target) {
  var tile = findTile(listTiles(list), target)
  if (!tile) return { error: "No mosaic tile " + JSON.stringify(String(target)) + "; see `mosaic list`" }
  return plan("focus", [tile], "")
}

// `mosaic remove TILE...`: every target is resolved before any tile closes.
function planRemove(list, targets) {
  var all = listTiles(list)
  var chosen = []
  var names = stringList(targets)
  if (names.length === 0) return { error: "Name at least one tile to remove" }
  for (var i = 0; i < names.length; i++) {
    var tile = findTile(all, names[i])
    if (!tile) return { error: "No mosaic tile " + JSON.stringify(names[i]) + "; see `mosaic list`" }
    if (chosen.indexOf(tile) === -1) chosen.push(tile)
  }
  return plan("close", chosen, "Removed " + chosen.length + " tile(s).")
}

// `mosaic close [--session NAME]`: a session's tiles, or every tile.
function planClose(list, session) {
  var error = sessionFilterError(session)
  if (error) return { error: error }
  var chosen = listTiles(list).filter(function(tile) { return !session || tile.session === session })
  return plan("close", chosen, "Closed " + chosen.length + " tile(s).")
}

// `mosaic contain [--session NAME]`: only uncontained tiles, so floating
// tiles and ones the user made truly fullscreen are left alone.
function planContain(list, session) {
  var error = sessionFilterError(session)
  if (error) return { error: error }
  var chosen = listTiles(list).filter(function(tile) {
    return (!session || tile.session === session) && tile.state === "uncontained"
  })
  return plan("contain", chosen, "Contained fullscreen in " + chosen.length + " tile(s).")
}

// The fullscreen state to re-apply after Hyprland's `movewindowv2` event
// (`ADDRESS,WORKSPACEID,WORKSPACENAME`, the address without `0x`), or "".
// A move leaves Hyprland's record of the client fullscreen state stale in
// either direction without telling the browser, so the tile gets the state
// it had before the move: contained or released. When the record happens to
// be right, the dispatch changes nothing; when it is wrong, the change makes
// Hyprland tell the browser, and both agree again. Floating and truly
// fullscreen tiles are left alone.
function restoreAfterMove(list, eventData) {
  var hex = String(eventData || "").split(",")[0]
  var address = hex.indexOf("0x") === 0 ? hex : "0x" + hex
  var tile = findTile(listTiles(list), address)
  if (!tile || tile.address !== address) return ""
  if (tile.state === "contained") return dispatchExpression("contain", address)
  if (tile.state === "uncontained") return dispatchExpression("release", address)
  return ""
}

// How long `add` waits for a launched browser's app window.
var WINDOW_TIMEOUT_MS = 15000
// How many targets one `add` accepts.
var MAX_ADD = 9
// Desktop ids of browsers known to support `--app` windows. Mirrors
// `CHROMIUM_FAMILY` in the Rust CLI and Omarchy's `omarchy-launch-webapp`.
var CHROMIUM_FAMILY = ["chromium", "google-chrome", "brave", "microsoft-edge", "opera", "vivaldi", "helium"]

// A monitor from `hyprctl -j monitors`, with its logical size after scale
// and rotation and the work area left by reserved edges, or null. Mirrors
// `platform::monitor_from`.
function monitorFromIpc(object) {
  if (!object || typeof object.name !== "string" || typeof object.id !== "number"
      || typeof object.width !== "number" || typeof object.height !== "number"
      || !object.activeWorkspace || typeof object.activeWorkspace.id !== "number") return null
  var scale = object.scale > 0 ? object.scale : 1
  var width = Math.round(object.width / scale)
  var height = Math.round(object.height / scale)
  if (Number(object.transform || 0) % 2 === 1) {
    var swap = width
    width = height
    height = swap
  }
  var reserved = Array.isArray(object.reserved) && object.reserved.length === 4 ? object.reserved.map(function(edge) {
    return Math.trunc(Number(edge) || 0)
  }) : [0, 0, 0, 0]
  return {
    id: object.id,
    name: object.name,
    focused: object.focused === true,
    activeWorkspace: object.activeWorkspace.id,
    size: [width, height],
    workArea: {
      x: Math.trunc(Number(object.x) || 0) + reserved[0],
      y: Math.trunc(Number(object.y) || 0) + reserved[1],
      width: Math.max(1, width - reserved[0] - reserved[2]),
      height: Math.max(1, height - reserved[1] - reserved[3])
    }
  }
}

// Enabled monitors from `hyprctl -j monitors`, or null when the text is not
// that list.
function parseMonitors(text) {
  var parsed
  try {
    parsed = JSON.parse(String(text || ""))
  } catch (error) {
    return null
  }
  if (!Array.isArray(parsed)) return null
  var monitors = []
  for (var i = 0; i < parsed.length; i++) {
    if (parsed[i] && parsed[i].disabled === true) continue
    var monitor = monitorFromIpc(parsed[i])
    if (monitor) monitors.push(monitor)
  }
  return monitors
}

// The URLs `add` opens: each target is a URL (http, https, or file) or a
// web app's name or id. Every target is resolved before anything opens, so a
// typo opens nothing. Returns { urls } or { error }.
function resolveAddTargets(targets, apps) {
  var names = stringList(targets)
  if (names.length < 1 || names.length > MAX_ADD) return { error: "Pass 1 to 9 URLs or web apps" }
  var urls = []
  for (var i = 0; i < names.length; i++) {
    var target = names[i]
    if (/^(https?|file):\/\//.test(target)) {
      urls.push(target)
      continue
    }
    var app = findWebapp(apps, target)
    if (!app) return { error: JSON.stringify(target) + " is neither a URL (http, https, or file) nor a web app; see `mosaic webapps`" }
    urls.push(app.url)
  }
  return { urls: urls }
}

// The workspace new tiles of `session` go to: the named monitor's active
// workspace, else the workspace of the session's first tiled window, else
// the focused monitor's. Returns { workspace } or { error }.
function chooseWorkspace(list, monitors, session, monitorName) {
  if (monitors.length === 0) return { error: "No active Hyprland monitors" }
  if (monitorName) {
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i].name === monitorName) return { workspace: monitors[i].activeWorkspace }
    }
    return { error: "Monitor " + JSON.stringify(String(monitorName)) + " is not active" }
  }
  var sessions = list && Array.isArray(list.sessions) ? list.sessions : []
  for (var s = 0; s < sessions.length; s++) {
    if (sessions[s].name !== session) continue
    for (var t = 0; t < sessions[s].tiles.length; t++) {
      if (sessions[s].tiles[t].state !== "floating") return { workspace: sessions[s].tiles[t].workspace }
    }
  }
  for (var m = 0; m < monitors.length; m++) {
    if (monitors[m].focused) return { workspace: monitors[m].activeWorkspace }
  }
  return { workspace: monitors[0].activeWorkspace }
}

// The desktop id `xdg-settings get default-web-browser` printed, without
// `.desktop`, or "".
function desktopId(text) {
  var id = String(text || "").trim().split("\n")[0].trim()
  return id.slice(-8) === ".desktop" ? id.slice(0, -8) : id
}

function isChromiumFamily(id) {
  for (var i = 0; i < CHROMIUM_FAMILY.length; i++) {
    if (String(id).indexOf(CHROMIUM_FAMILY[i]) === 0) return true
  }
  return false
}

// Chromium names Wayland app windows `<browser>-<host>__<path>-<profile>`,
// which tells them apart from restored normal browser windows.
function isAppWindow(windowClass) {
  return String(windowClass || "").indexOf("__") !== -1
}

// The window Hyprland's `openwindow` event (`ADDRESS,WORKSPACE,CLASS,TITLE`,
// the address without `0x`) announces, or null.
function parseOpenWindow(data) {
  var parts = String(data || "").split(",")
  if (parts.length < 3) return null
  var address = parts[0].indexOf("0x") === 0 ? parts[0] : "0x" + parts[0]
  if (!validAddress(address)) return null
  return { address: address, windowClass: parts[2] }
}

// The dispatches that make a new window a tile of `session` on `workspace`:
// tags first, then (once the store has the record) placement and
// containment last, because switching between floating and tiled resets it.
// Mirrors `platform::tag`, `tile_on`, and `contain_fullscreen`. With
// `replacing` (a tile from listTiles), the new window also takes that
// tile's slot, when it is tiled, and the old window closes before the new
// one is contained. Returns { tags, place } or { error }.
function tileDispatches(address, session, workspace, replacing) {
  if (!validAddress(address)) return { error: "Unexpected Hyprland window address " + JSON.stringify(String(address)) }
  if (sessionName(session) !== session) return { error: "Invalid session name " + JSON.stringify(String(session)) }
  if (typeof workspace !== "number" || Math.floor(workspace) !== workspace) return { error: "Unexpected workspace " + JSON.stringify(workspace) }
  var window = 'window = "address:' + address + '"'
  var replaced = []
  if (replacing) {
    if (!validAddress(replacing.address) || replacing.address === address)
      return { error: "Unexpected Hyprland window address " + JSON.stringify(String(replacing.address)) }
    // Swapping puts the new window in the old one's slot, and its size.
    if (replacing.state !== "floating")
      replaced.push("hl.dsp.window.swap({ " + window + ', target = "address:' + replacing.address + '" })')
    replaced.push(dispatchExpression("close", replacing.address))
  }
  return {
    tags: [
      "hl.dsp.window.tag({ " + window + ', tag = "+' + TAG + '" })',
      "hl.dsp.window.tag({ " + window + ', tag = "+' + TAG + "-" + session + '" })'
    ],
    place: [
      "hl.dsp.window.move({ " + window + ', workspace = "' + workspace + '", follow = false })',
      "hl.dsp.window.float({ " + window + ', action = "disable" })',
      "hl.dsp.window.set_prop({ " + window + ', prop = "opaque", value = "1" })'
    ].concat(replaced, [dispatchExpression("contain", address)])
  }
}

// Store records without the ones whose window is gone or no longer a tile.
// Mirrors `Store::prune`.
function pruneRecords(records, clients) {
  var live = []
  for (var i = 0; i < clients.length; i++) {
    if (sessionOf(clients[i].tags) !== null) live.push(clients[i].address)
  }
  return records.filter(function(record) { return live.indexOf(record.address) !== -1 })
}

// tiles.json text for `records`, formatted as the Rust CLI writes it.
function serializeStore(records) {
  return JSON.stringify({ tiles: records.map(function(record) {
    return { address: record.address, session: record.session, url: record.url }
  }) }, null, 2)
}

// The tile `mosaic replace TILE TARGET` swaps out: its number in the list or
// its address. Returns { tile } (from listTiles) or { error }.
function planReplace(list, target) {
  var tile = findTile(listTiles(list), target)
  if (!tile) return { error: "No mosaic tile " + JSON.stringify(String(target)) + "; see `mosaic list`" }
  if (tile.state === "fullscreen") return { error: "Leave fullscreen on that tile before replacing it" }
  return { tile: tile }
}

// Store records with `record` in place of the one for `oldAddress`, so the
// new tile keeps the old one's position in the list; appended when the old
// tile had no record.
function replaceRecord(records, oldAddress, record) {
  var next = []
  var placed = false
  for (var i = 0; i < records.length; i++) {
    if (records[i].address === oldAddress && !placed) {
      next.push(record)
      placed = true
    } else if (records[i].address !== oldAddress) {
      next.push(records[i])
    }
  }
  if (!placed) next.push(record)
  return next
}

// The cursor position `hyprctl cursorpos` printed ("X, Y"), or null.
function parseCursorPos(text) {
  var match = /^\s*(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\s*$/.exec(String(text || ""))
  return match ? { x: Math.round(Number(match[1])), y: Math.round(Number(match[2])) } : null
}

// The dispatch that puts the cursor back at `position`, or "". A new app
// window takes focus as it maps (Chromium asks to be activated, and Omarchy
// sets focus_on_activate), and Hyprland warps the cursor to it, so add and
// replace move it back before anything else.
function cursorMoveExpression(position) {
  if (!position || typeof position.x !== "number" || typeof position.y !== "number"
      || Math.floor(position.x) !== position.x || Math.floor(position.y) !== position.y) return ""
  return "hl.dsp.cursor.move({ x = " + position.x + ", y = " + position.y + " })"
}

// The swap key's default, and the description its Hyprland bind carries,
// which is how the service recognises its own bind.
var DEFAULT_SWAP_KEY = "SUPER + SHIFT + S"
var SWAP_BIND_DESCRIPTION = "Mosaic: swap the focused tile's web app"
// Hyprland's modifier names and mask bits.
var KEY_MODIFIERS = { SHIFT: 1, CAPS: 2, CTRL: 4, CONTROL: 4, ALT: 8, MOD2: 16, MOD3: 32, SUPER: 64, WIN: 64, LOGO: 64, MOD4: 64, MOD5: 128 }

// A key setting such as "super + shift + s": { spec, modmask, key } with
// the spec written the way Hyprland's config writes it
// ("SUPER + SHIFT + S"); { spec: "" } for an empty setting, which means no
// key; or null when it isn't a key. The spec is interpolated into Lua, so
// only modifier names and a plain key name (or `code:N`) pass.
function parseKeySpec(text) {
  var value = String(text || "").trim()
  if (value === "") return { spec: "", modmask: 0, key: "" }
  var parts = value.split("+").map(function(part) { return part.trim() })
  var key = parts.pop()
  if (!/^(code:\d{1,3}|[A-Za-z0-9_]{1,32})$/.test(key)) return null
  var modmask = 0
  var names = []
  for (var i = 0; i < parts.length; i++) {
    var name = parts[i].toUpperCase()
    if (!KEY_MODIFIERS.hasOwnProperty(name)) return null
    modmask |= KEY_MODIFIERS[name]
    names.push(name)
  }
  if (key.length === 1) key = key.toUpperCase()
  return { spec: names.concat([key]).join(" + "), modmask: modmask, key: key }
}

// The description of another bind on the same key in `hyprctl -j binds`
// output, or "" when the key is free (or only bound by the service itself).
function bindConflict(bindsText, parsed) {
  var binds
  try {
    binds = JSON.parse(String(bindsText || ""))
  } catch (error) {
    return ""
  }
  if (!Array.isArray(binds) || !parsed || parsed.spec === "") return ""
  for (var i = 0; i < binds.length; i++) {
    var bind = binds[i]
    if (!bind || bind.submap !== "" || bind.modmask !== parsed.modmask) continue
    if (String(bind.key).toLowerCase() !== parsed.key.toLowerCase()) continue
    if (bind.description === SWAP_BIND_DESCRIPTION) continue
    return String(bind.description || bind.dispatcher || "another binding")
  }
  return ""
}

// Lua for `hyprctl eval` that binds or unbinds the swap key. The command is
// a constant; only a spec that parseKeySpec produced goes in.
function swapBindLua(spec) {
  return 'hl.bind("' + spec + '", hl.dsp.exec_cmd("omarchy-shell pym.mosaic swap"), { description = "'
    + SWAP_BIND_DESCRIPTION + '" })'
}

function unbindLua(spec) {
  return 'hl.unbind("' + spec + '")'
}
