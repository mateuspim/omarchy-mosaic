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

// First line of a failed command's stderr, without mosaic's prefix.
function errorLine(stderr, fallback) {
  var lines = String(stderr || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line !== "" && line.indexOf("Run `mosaic --help`") !== 0) return line.replace(/^mosaic:\s*/, "")
  }
  return fallback
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
        state: sessionTiles[j].state })
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
