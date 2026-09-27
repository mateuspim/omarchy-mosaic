.pragma library

// Pure helpers for the Mosaic bar widget. Kept free of QML so node can test
// them (see tests/model.test.js).

// The `mosaic list --json` format versions this widget understands.
var SUPPORTED_VERSIONS = [1]
var DEFAULT_SESSION = "default"

// Parses `mosaic list --json` into { sessions, tiles, error }. `tiles` is
// every tile in listing order, each with its session name attached, which
// is the order keyboard navigation walks.
function parseList(text) {
  var parsed
  try {
    parsed = JSON.parse(String(text || ""))
  } catch (error) {
    return { sessions: [], tiles: [], error: "Unexpected output from mosaic list" }
  }
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
