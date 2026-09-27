.pragma library

// Pure helpers for the Mosaic bar widget. Kept free of QML so node can test
// them (see tests/model.test.js).

// The `mosaic list --json` format versions this widget understands.
var SUPPORTED_VERSIONS = [1]
var LIST_VERSION = 1
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

// Parses `mosaic webapps --json` into { apps, error }. Older mosaic builds
// without the command make this fail, which only hides the web app buttons.
function parseWebapps(text) {
  var parsed
  try {
    parsed = JSON.parse(String(text || ""))
  } catch (error) {
    return { apps: [], error: "Unexpected output from mosaic webapps" }
  }
  if (!parsed || SUPPORTED_VERSIONS.indexOf(parsed.version) === -1) {
    return { apps: [], error: "This mosaic version is not supported; update mosaic and the widget together" }
  }
  var apps = []
  var source = parsed.webapps instanceof Array ? parsed.webapps : []
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
