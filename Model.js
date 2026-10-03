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

// The line under a tile's name. `place` is its session's shared place
// (see sessionPlace); when there is one, the tile leaves it to the header.
function tileMeta(tile, place, app) {
  // A problem comes first, where eliding cannot hide it.
  var parts = tile.state && tile.state !== "contained" ? [stateLabel(tile.state)] : []
  parts.push(place ? tileSubtitle(tile, app) : tile.monitor + " · workspace " + tile.workspace)
  return parts.filter(function(part) { return part !== "" }).join("  ·  ")
}

// "DP-4 · workspace 10" when every tile of a session is there, else "".
function sessionPlace(tiles) {
  if (!tiles || tiles.length === 0) return ""
  for (var i = 1; i < tiles.length; i++) {
    if (tiles[i].monitor !== tiles[0].monitor || tiles[i].workspace !== tiles[0].workspace) return ""
  }
  return tiles[0].monitor + " · workspace " + tiles[0].workspace
}

// The web app showing the tile's site, or null.
function tileApp(apps, tile) {
  var site = tile ? siteOf(tile.url) : ""
  for (var i = 0; site !== "" && apps && i < apps.length; i++) {
    if (siteOf(apps[i].url) === site) return apps[i]
  }
  return null
}

// A tile's name: its web app's, else its site ("example.org"), else its
// page title.
function tileName(tile, app) {
  if (app) return app.name
  var site = siteOf(tile.url)
  return site !== "" ? site : tileLabel(tile)
}

// What sets a tile apart from others on its site: the path of its
// address ("twitch.tv/somechannel"), else the page's title without an
// unread count or the site's name ("(5) Home / X" is "Home").
function tileSubtitle(tile, app) {
  var label = tileLabel(tile)
  if (label.indexOf("/") !== -1) return label
  var title = String(tile.title || "").trim().replace(/^\(\d+\+?\)\s*/, "")
  var names = [label.split(".")[0]].concat(app ? [app.name] : [])
  for (var i = 0; i < names.length; i++) {
    var suffix = new RegExp("\\s+[-–—|/·:]\\s+" + names[i].replace(/[^a-z0-9]/gi, "\\$&") + "$", "i")
    title = title.replace(suffix, "")
  }
  return title !== "" && title.toLowerCase() !== label.toLowerCase() && title.toLowerCase() !== (app ? app.name.toLowerCase() : "") ? title : ""
}

// One letter for a tile without an icon.
function tileInitial(tile, app) {
  var name = tileName(tile, app).replace(/^[^a-z0-9]+/i, "")
  return name === "" ? "?" : name.charAt(0).toUpperCase()
}

// Where `n` windows go in a layout, as fractions of an area with `aspect`
// (width / height), in fill order: the same arrangement `layouts.lua`
// makes, for the panel's small picture of it. "default" is Hyprland's own
// dwindle, which halves the last window along its longer side.
function layoutBoxes(choice, custom, n, aspect) {
  var area = { x: 0, y: 0, w: aspect > 0 ? aspect : 16 / 9, h: 1 }
  var portrait = area.h > area.w
  function box(x, y, w, h) { return { x: x, y: y, w: w, h: h } }
  function rowsOf(count, cols) {
    var rows = []
    for (var left = count; left > 0; left -= Math.min(cols, left)) rows.push(Math.min(cols, left))
    return rows
  }
  function lines(a, counts, vertical) {
    var boxes = []
    for (var l = 0; l < counts.length; l++) {
      for (var c = 0; c < counts[l]; c++) {
        if (vertical) boxes.push(box(a.x + l * a.w / counts.length, a.y + c * a.h / counts[l], a.w / counts.length, a.h / counts[l]))
        else boxes.push(box(a.x + c * a.w / counts[l], a.y + l * a.h / counts.length, a.w / counts[l], a.h / counts.length))
      }
    }
    return boxes
  }
  var boxes = []
  var slug = customSlug(choice)
  if (n <= 0) boxes = []
  else if (slug !== "" && custom && custom[slug]) {
    var zones = fillZones(custom[slug]).map(function(z) { return box(z.x * area.w, z.y, z.w * area.w, z.h) })
    var own = Math.min(n, zones.length)
    boxes = zones.slice(0, own - 1)
    var last = zones[own - 1]
    boxes = boxes.concat(lines(last, [n - own + 1], last.h > last.w))
  } else if (choice === "stack") boxes = lines(area, [n], portrait)
  else if (choice === "main") {
    if (n === 1) boxes = [area]
    else if (portrait) boxes = [box(0, 0, area.w, 0.7)].concat(lines(box(0, 0.7, area.w, 0.3), [n - 1], false))
    else boxes = [box(0, 0, area.w * 0.7, 1)].concat(lines(box(area.w * 0.7, 0, area.w * 0.3, 1), [n - 1], true))
  } else if (choice === "fit") {
    var best = null
    for (var cols = 1; cols <= n; cols++) {
      var w = Math.min(area.w / cols, area.h / Math.ceil(n / cols) * 16 / 9)
      if (!best || w > best.w + 0.001) best = { cols: cols, w: w }
    }
    var h = best.w * 9 / 16
    var counts = rowsOf(n, best.cols)
    var top = (area.h - counts.length * h) / 2
    for (var r = 0; r < counts.length; r++) {
      var left = (area.w - counts[r] * best.w) / 2
      for (var c = 0; c < counts[r]; c++) boxes.push(box(left + c * best.w, top + r * h, best.w, h))
    }
  } else if (choice === "default") {
    var rest = area
    for (var i = 0; i < n; i++) {
      if (i === n - 1) { boxes.push(rest); break }
      if (rest.w >= rest.h) {
        boxes.push(box(rest.x, rest.y, rest.w / 2, rest.h))
        rest = box(rest.x + rest.w / 2, rest.y, rest.w / 2, rest.h)
      } else {
        boxes.push(box(rest.x, rest.y, rest.w, rest.h / 2))
        rest = box(rest.x, rest.y + rest.h / 2, rest.w, rest.h / 2)
      }
    }
  } else boxes = lines(area, rowsOf(n, Math.ceil(Math.sqrt(n))), portrait)
  return boxes.map(function(b) { return box(b.x / area.w, b.y, b.w / area.w, b.h) })
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

// What the "keep fullscreen in tiles" setting contains: every tile that
// lost its containment, and a truly fullscreen one once `focused` (the
// last focused window's address) is another window, so a tile made big on
// purpose stays big while it has focus. Floating tiles are left alone.
// Returns the dispatch expressions.
function planAutoContain(list, focused) {
  return listTiles(list).filter(function(tile) {
    return tile.state === "uncontained" || (tile.state === "fullscreen" && tile.address !== focused)
  }).map(function(tile) { return dispatchExpression("contain", tile.address) })
    .filter(function(expression) { return expression !== "" })
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

// Layouts (layouts.lua): Hyprland Lua tiling layouts, set per workspace. A
// choice is "default" (the workspace's own layout again), a built-in name,
// or "custom:<slug>" for a layout designed on the panel's Layouts tab.
var LAYOUTS = ["grid", "stack", "main", "fit"]
var LAYOUT_LABELS = { "default": "Hyprland", grid: "Grid", stack: "Stack", main: "Main + small", fit: "16:9 fit" }
var CUSTOM_PREFIX = "custom:"
// Limits for custom layouts: zones in all, zones per split, splits
// inside splits, and the smallest share of a split, in percent.
var MAX_ZONES = 16
var MAX_CHILDREN = 6
var MAX_DEPTH = 4
var MIN_ZONE = 5
var SIZE_STEP = 5

function customSlug(choice) {
  var text = String(choice || "")
  return text.indexOf(CUSTOM_PREFIX) === 0 ? text.slice(CUSTOM_PREFIX.length) : ""
}

// Every choice, in the order the panel cycles them: default, the
// built-ins, then custom layouts by name.
function layoutChoices(custom) {
  var slugs = Object.keys(custom || {}).sort(function(a, b) { return compareText(custom[a].name.toLowerCase(), custom[b].name.toLowerCase()) })
  return ["default"].concat(LAYOUTS, slugs.map(function(slug) { return CUSTOM_PREFIX + slug }))
}

function layoutLabel(name, custom) {
  var slug = customSlug(name)
  if (slug !== "") return custom && custom[slug] ? custom[slug].name : "Missing layout"
  return LAYOUT_LABELS[name] || LAYOUT_LABELS["default"]
}

// The choice after `name` in the panel's cycle.
function nextLayout(name, custom) {
  var choices = layoutChoices(custom)
  return choices[(choices.indexOf(name) + 1) % choices.length]
}

// A choice from user text ("Grid", "16:9", "main", a custom layout's name
// or slug), or "".
function parseLayoutName(text, custom) {
  var name = String(text || "").trim().toLowerCase()
  if (name === "16:9" || name === "16x9") return "fit"
  if (name === "hyprland" || name === "none" || name === "off" || name === "default") return "default"
  if (LAYOUTS.indexOf(name) !== -1) return name
  var slugs = Object.keys(custom || {})
  var slug = customSlug(name) || layoutSlug(name)
  for (var i = 0; i < slugs.length; i++) {
    if (slugs[i] === slug || custom[slugs[i]].name.toLowerCase() === name) return CUSTOM_PREFIX + slugs[i]
  }
  return ""
}

// A layout Hyprland reports in `tiledLayout`, safe to put back in a rule.
function validHyprLayout(name) {
  return /^[a-z][a-z0-9_:-]{0,39}$/.test(String(name || ""))
}

// The name Hyprland knows a choice by, or "" when invalid. A Hyprland
// layout name (from `before`) passes through.
function hyprLayoutName(choice) {
  if (LAYOUTS.indexOf(choice) !== -1) return "lua:mosaic-" + choice
  var slug = customSlug(choice)
  if (slug !== "") return sessionName(slug) === slug ? "lua:mosaic-c-" + slug : ""
  return validHyprLayout(choice) ? String(choice) : ""
}

// A custom layout's slug from its name: lowercase letters, digits, - and _.
function layoutSlug(name) {
  return String(name || "").toLowerCase().replace(/[^a-z0-9_-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 32)
}

// Equal percent sizes for `count` zones, the remainder on the first ones.
function equalSizes(count) {
  var sizes = []
  for (var i = 0; i < count; i++) sizes.push(Math.floor(100 / count) + (i < 100 % count ? 1 : 0))
  return sizes
}

// A custom layout is { name, tree, main }. The tree is a zone (`{}`) or a
// split: { split: "row" (side by side) or "column" (stacked), sizes
// (percent, at least MIN_ZONE each, adding up to 100), children }. `main`
// is the 1-based zone, counting zones depth first (left to right, top to
// bottom), that the first window takes.
function splitNode(direction, sizes, children) {
  return { split: direction, sizes: sizes, children: children }
}

function isSplit(node) {
  return !!node && (node.split === "row" || node.split === "column")
}

// A checked copy of a tree, with one-child splits collapsed, or null.
function cleanTree(node, depth) {
  if (!node || typeof node !== "object" || depth > MAX_DEPTH) return null
  if (node.split === undefined) return {}
  if (!isSplit(node) || !Array.isArray(node.children) || !Array.isArray(node.sizes)
      || node.children.length !== node.sizes.length || node.children.length < 1 || node.children.length > MAX_CHILDREN) return null
  var sum = 0
  for (var i = 0; i < node.sizes.length; i++) {
    var size = Number(node.sizes[i])
    if (!(size >= MIN_ZONE) || size % 1) return null
    sum += size
  }
  if (sum !== 100) return null
  if (node.children.length === 1) return cleanTree(node.children[0], depth)
  var children = []
  for (var c = 0; c < node.children.length; c++) {
    var child = cleanTree(node.children[c], depth + 1)
    if (!child) return null
    children.push(child)
  }
  return splitNode(node.split, node.sizes.map(Number), children)
}

function countZones(node) {
  if (!isSplit(node)) return 1
  return node.children.reduce(function(total, child) { return total + countZones(child) }, 0)
}

// The tree the earlier columns, rows, and grid definitions describe.
function templateTree(def) {
  if (def.template === "grid") {
    var cols = Number(def.cols), rows = Number(def.rows)
    if (!(cols >= 1 && cols <= 4 && rows >= 1 && rows <= 4) || cols % 1 || rows % 1) return null
    var row = function() {
      return cols === 1 ? {} : splitNode("row", equalSizes(cols), Array.apply(null, Array(cols)).map(function() { return {} }))
    }
    if (rows === 1) return row()
    return splitNode("column", equalSizes(rows), Array.apply(null, Array(rows)).map(row))
  }
  if ((def.template !== "columns" && def.template !== "rows") || !Array.isArray(def.sizes)) return null
  return { split: def.template === "columns" ? "row" : "column", sizes: def.sizes, children: def.sizes.map(function() { return {} }) }
}

// A custom layout definition, checked and tidied, or null. The earlier
// { template, sizes | cols, rows } form is read as a tree.
function normalizeCustom(def) {
  if (!def || typeof def !== "object") return null
  var name = String(def.name || "").trim().slice(0, 40)
  if (layoutSlug(name) === "") return null
  var tree = cleanTree(def.tree !== undefined ? def.tree : templateTree(def), 0)
  if (!tree) return null
  var count = countZones(tree)
  if (count > MAX_ZONES) return null
  var main = Number(def.main)
  return { name: name, tree: tree, main: main >= 1 && main <= count && main % 1 === 0 ? main : 1 }
}

// Starting points for a new layout.
var PRESETS = ["columns", "rows", "grid", "side"]
var PRESET_LABELS = { columns: "Columns", rows: "Rows", grid: "Grid", side: "Main + side" }

function presetTree(preset) {
  if (preset === "rows") return { tree: splitNode("column", [34, 33, 33], [{}, {}, {}]), main: 1 }
  if (preset === "grid") return { tree: splitNode("column", [50, 50], [splitNode("row", [50, 50], [{}, {}]), splitNode("row", [50, 50], [{}, {}])]), main: 1 }
  if (preset === "side") return { tree: splitNode("row", [70, 30], [{}, splitNode("column", [50, 50], [{}, {}])]), main: 1 }
  return { tree: splitNode("row", [25, 50, 25], [{}, {}, {}]), main: 2 }
}

// A new layout from a preset: Columns 25 / 50 / 25 with the middle main.
function newCustom(name, preset) {
  var start = presetTree(preset)
  return { name: name, tree: start.tree, main: start.main }
}

function withPreset(def, preset) {
  var next = newCustom(def.name, preset)
  return next
}

function zoneCount(def) {
  return countZones(def.tree)
}

function copyDef(def) {
  return JSON.parse(JSON.stringify(def))
}

// Zones in visual order as fractions: [{ x, y, w, h, main, fill, path }],
// where `fill` is the 1-based order windows take them in (the main zone
// first, then the rest in visual order) and `path` the child indexes that
// lead to the zone in the tree.
function visualZones(def) {
  var zones = []
  function walk(node, x, y, w, h, path) {
    if (!isSplit(node)) {
      zones.push({ x: x, y: y, w: w, h: h, path: path })
      return
    }
    var at = 0
    for (var i = 0; i < node.children.length; i++) {
      var part = node.sizes[i] / 100
      if (node.split === "row") walk(node.children[i], x + at * w, y, part * w, h, path.concat([i]))
      else walk(node.children[i], x, y + at * h, w, part * h, path.concat([i]))
      at += part
    }
  }
  walk(def.tree, 0, 0, 1, 1, [])
  var fill = 2
  for (var z = 0; z < zones.length; z++) {
    zones[z].main = z + 1 === def.main
    zones[z].fill = zones[z].main ? 1 : fill++
  }
  return zones
}

// Zones in the order windows fill them.
function fillZones(def) {
  return visualZones(def).slice().sort(function(a, b) { return a.fill - b.fill })
}

function luaNumber(value) {
  return String(Math.round(value * 10000) / 10000)
}

// The Lua that gives Hyprland a custom layout's zones, or "".
function defineLua(slug, def) {
  if (sessionName(slug) !== slug || !def) return ""
  var zones = fillZones(def).map(function(z) {
    return "{ x = " + luaNumber(z.x) + ", y = " + luaNumber(z.y) + ", w = " + luaNumber(z.w) + ", h = " + luaNumber(z.h) + " }"
  })
  return 'MosaicLayouts.define("' + slug + '", { ' + zones.join(", ") + " })"
}

// The lines between zones, for dragging: [{ path, index, vertical, x, y,
// length, from, span }], all fractions of the whole. `path` leads to the
// split, `index` is the line after child `index`; `vertical` lines sit at
// `x` and run down from `y` for `length`. `from` and `span` are the
// split's own extent along its direction, to turn a pointer position into
// a size.
function zoneDividers(def) {
  var lines = []
  function walk(node, x, y, w, h, path) {
    if (!isSplit(node)) return
    var at = 0
    for (var i = 0; i < node.children.length; i++) {
      var part = node.sizes[i] / 100
      if (node.split === "row") walk(node.children[i], x + at * w, y, part * w, h, path.concat([i]))
      else walk(node.children[i], x, y + at * h, w, part * h, path.concat([i]))
      at += part
      if (i === node.children.length - 1) continue
      if (node.split === "row") lines.push({ path: path, index: i, vertical: true, x: x + at * w, y: y, length: h, from: x, span: w })
      else lines.push({ path: path, index: i, vertical: false, x: x, y: y + at * h, length: w, from: y, span: h })
    }
  }
  walk(def.tree, 0, 0, 1, 1, [])
  return lines
}

function nodeAt(tree, path) {
  var node = tree
  for (var i = 0; i < path.length; i++) node = node.children[path[i]]
  return node
}

// Moves line `index` of the split at `path` to `position` (a fraction of
// the whole, along the split), keeping both zones at least MIN_ZONE.
function withDivider(def, path, index, position, from, span) {
  var next = copyDef(def)
  var node = nodeAt(next.tree, path)
  if (!isSplit(node) || index < 0 || index >= node.sizes.length - 1 || !(span > 0)) return def
  var before = 0
  for (var i = 0; i < index; i++) before += node.sizes[i]
  var pair = node.sizes[index] + node.sizes[index + 1]
  var wanted = Math.round((position - from) / span * 100) - before
  var size = Math.max(MIN_ZONE, Math.min(pair - MIN_ZONE, wanted))
  node.sizes[index] = size
  node.sizes[index + 1] = pair - size
  return next
}

// Splits zone `zone` (0-based, visual order) in two: "row" puts the new
// zone beside it, "column" below it. The zone keeps its share and the new
// one takes half; within a split of the same direction it becomes a
// sibling. Returns the definition unchanged when the zone is too small or
// the layout is full.
function withSplit(def, zone, direction) {
  var zones = visualZones(def)
  if (zone < 0 || zone >= zones.length || zones.length >= MAX_ZONES) return def
  var next = copyDef(def)
  var path = zones[zone].path
  if (path.length > 0) {
    var parent = nodeAt(next.tree, path.slice(0, -1))
    var at = path[path.length - 1]
    if (parent.split === direction) {
      var size = parent.sizes[at]
      if (size < MIN_ZONE * 2 || parent.children.length >= MAX_CHILDREN) return def
      parent.sizes.splice(at, 1, size - Math.floor(size / 2), Math.floor(size / 2))
      parent.children.splice(at + 1, 0, {})
    } else {
      if (path.length >= MAX_DEPTH) return def
      parent.children[at] = splitNode(direction, [50, 50], [{}, {}])
    }
  } else {
    next.tree = splitNode(direction, [50, 50], [{}, {}])
  }
  if (next.main > zone + 1) next.main += 1
  return next
}

// Removes zone `zone`; its neighbour (the one before, or else after) takes
// its share, and a split left with one zone becomes that zone.
function withoutZone(def, zone) {
  var zones = visualZones(def)
  if (zones.length <= 1 || zone < 0 || zone >= zones.length) return def
  var next = copyDef(def)
  var path = zones[zone].path
  var parentPath = path.slice(0, -1)
  var parent = nodeAt(next.tree, parentPath)
  var at = path[path.length - 1]
  parent.sizes[at > 0 ? at - 1 : at + 1] += parent.sizes[at]
  parent.sizes.splice(at, 1)
  parent.children.splice(at, 1)
  if (parent.children.length === 1) {
    if (parentPath.length === 0) next.tree = parent.children[0]
    else nodeAt(next.tree, parentPath.slice(0, -1)).children[parentPath[parentPath.length - 1]] = parent.children[0]
  }
  if (next.main === zone + 1) next.main = 1
  else if (next.main > zone + 1) next.main -= 1
  return next
}

// Grows zone `zone` by `delta` percent of its split, taken from the next
// zone there (the one before, for the last), keeping both at least
// MIN_ZONE.
function withZoneSize(def, zone, delta) {
  var zones = visualZones(def)
  if (zone < 0 || zone >= zones.length || zones[zone].path.length === 0) return def
  var next = copyDef(def)
  var path = zones[zone].path
  var parent = nodeAt(next.tree, path.slice(0, -1))
  var at = path[path.length - 1]
  var other = at + 1 < parent.sizes.length ? at + 1 : at - 1
  var change = Math.max(MIN_ZONE - parent.sizes[at], Math.min(delta, parent.sizes[other] - MIN_ZONE))
  parent.sizes[at] += change
  parent.sizes[other] -= change
  return next
}

function withMain(def, zone) {
  if (zone < 0 || zone >= zoneCount(def)) return def
  var next = copyDef(def)
  next.main = zone + 1
  return next
}

function withName(def, name) {
  var next = copyDef(def)
  next.name = String(name || "")
  return next
}

// "2nd", "3rd", "4th", …
function ordinal(n) {
  var tens = n % 100
  var suffix = tens >= 11 && tens <= 13 ? "th" : ["th", "st", "nd", "rd"][n % 10] || "th"
  return n + suffix
}

// A zone's size as the percent of the whole it covers.
function zonePercent(zone) {
  return Math.round(zone.w * zone.h * 100)
}

// One line about a custom layout: "3 zones  ·  main 50%".
function customSummary(def) {
  var zones = visualZones(def)
  var main = zones[def.main - 1]
  return zones.length + (zones.length === 1 ? " zone" : " zones") + "  ·  main " + zonePercent(main) + "%"
}

// layouts.json: `{ version: 2, workspaces: { "8": { layout, before } },
// custom: { SLUG: definition } }`, where `before` is the workspace's
// layout before Mosaic changed it. Version 1 kept layouts per session;
// those come back as `legacy` ({ SESSION: layout }) for the service to
// move to the sessions' workspaces. An unreadable file has no layouts.
function parseLayouts(text) {
  var parsed
  try {
    parsed = JSON.parse(String(text || ""))
  } catch (error) {
    parsed = null
  }
  var state = { workspaces: {}, custom: {}, legacy: {} }
  if (!parsed || typeof parsed !== "object") return state
  var custom = parsed.custom && typeof parsed.custom === "object" ? parsed.custom : {}
  Object.keys(custom).forEach(function(slug) {
    var def = normalizeCustom(custom[slug])
    if (def && sessionName(slug) === slug) state.custom[slug] = def
  })
  var workspaces = parsed.workspaces && typeof parsed.workspaces === "object" ? parsed.workspaces : {}
  Object.keys(workspaces).forEach(function(id) {
    var entry = workspaces[id]
    if (!/^[1-9]\d{0,3}$/.test(id) || !entry) return
    var layout = String(entry.layout || "")
    if (LAYOUTS.indexOf(layout) === -1 && !state.custom[customSlug(layout)]) return
    state.workspaces[id] = { layout: layout, before: validHyprLayout(entry.before) ? entry.before : "" }
  })
  var sessions = parsed.version === 1 && parsed.sessions && typeof parsed.sessions === "object" ? parsed.sessions : {}
  Object.keys(sessions).forEach(function(session) {
    var entry = sessions[session]
    if (sessionName(session) === session && entry && LAYOUTS.indexOf(entry.layout) !== -1)
      state.legacy[session] = { layout: entry.layout, before: validHyprLayout(entry.before) ? entry.before : "" }
  })
  return state
}

function serializeLayouts(state) {
  var workspaces = {}
  Object.keys(state.workspaces).sort(function(a, b) { return Number(a) - Number(b) }).forEach(function(id) {
    workspaces[id] = { layout: state.workspaces[id].layout, before: state.workspaces[id].before }
  })
  var custom = {}
  Object.keys(state.custom).sort().forEach(function(slug) { custom[slug] = state.custom[slug] })
  return JSON.stringify({ version: 2, workspaces: workspaces, custom: custom }, null, 2) + "\n"
}

function copyState(state) {
  return { workspaces: JSON.parse(JSON.stringify(state.workspaces)), custom: JSON.parse(JSON.stringify(state.custom)), legacy: {} }
}

// The Lua that loads layouts.lua into Hyprland, or "" for a path that can't
// be quoted plainly.
function layoutsLoadLua(path) {
  if (!/^\/[A-Za-z0-9_.\/ +-]+\.lua$/.test(String(path || ""))) return ""
  return 'dofile("' + path + '")'
}

// Whether a reply to layoutsLoadLua means the layouts are there: "ok", or
// only complaints that a name is already registered (by an older load that
// predates layouts.lua's own guard).
function layoutsLoaded(reply) {
  var lines = String(reply || "").trim().split("\n").filter(function(line) { return line.trim() !== "" })
  if (lines.length === 1 && lines[0].trim() === "ok") return true
  return lines.length > 0 && lines.every(function(line) { return /is already registered/.test(line) || line.trim() === "ok" })
}

// The Lua that sets workspace `workspace`'s tiled layout to a choice or a
// Hyprland layout name. "" when invalid.
function layoutRuleLua(workspace, layout) {
  var id = Number(workspace)
  if (!(id >= 1) || Math.floor(id) !== id) return ""
  var value = hyprLayoutName(layout)
  if (value === "") return ""
  return 'hl.workspace_rule({ workspace = "' + id + '", layout = "' + value + '" })'
}

// The workspace a session's tiles are on: its first tiled tile's, or null
// when every tile floats or the session is gone.
function sessionWorkspace(list, session) {
  var tiles = listTiles(list).filter(function(tile) { return tile.session === session && tile.state !== "floating" })
  return tiles.length > 0 ? tiles[0].workspace : null
}

// Each tile's state by address, to keep across a config reload.
function tileStates(list) {
  var states = {}
  listTiles(list).forEach(function(tile) { states[tile.address] = tile.state })
  return states
}

// The steps that load the layouts, define `slugs`' zones, give each
// workspace in `changes` ([{ workspace, layout, refresh }]) its layout,
// and then put back the fullscreen state of every tile there, since
// switching a workspace's layout resets Hyprland's record of it (contained
// tiles read 0 again). `refresh` switches away first, because setting a
// workspace's own layout again doesn't lay it out anew. `states` ({ ADDRESS:
// state }, optional) overrides the list's state for tiles whose record was
// reset before the list saw it, as by a config reload. Steps are { eval }
// for `hyprctl eval` and plain strings for dispatches. Returns {
// expressions } or { error }.
function layoutSteps(list, state, changes, slugs, loadLua, states) {
  if (changes.length === 0 && slugs.length === 0) return { expressions: [] }
  if (loadLua === "") return { error: "Cannot load the layouts from this plugin's folder" }
  var steps = [{ eval: loadLua }]
  for (var s = 0; s < slugs.length; s++) {
    var define = defineLua(slugs[s], state.custom[slugs[s]])
    if (define === "") return { error: "Cannot define layout " + JSON.stringify(String(slugs[s])) }
    steps.push({ eval: define })
  }
  var tiles = listTiles(list)
  for (var i = 0; i < changes.length; i++) {
    var rule = layoutRuleLua(changes[i].workspace, changes[i].layout)
    if (rule === "") return { error: "Cannot set layout " + JSON.stringify(String(changes[i].layout)) + " on workspace " + changes[i].workspace }
    if (changes[i].refresh) steps.push({ eval: layoutRuleLua(changes[i].workspace, "dwindle") })
    steps.push({ eval: rule })
    for (var t = 0; t < tiles.length; t++) {
      if (tiles[t].workspace !== Number(changes[i].workspace)) continue
      var tileState = states && states[tiles[t].address] ? states[tiles[t].address] : tiles[t].state
      var action = tileState === "contained" ? "contain" : tileState === "uncontained" ? "release" : ""
      if (action !== "") steps.push(dispatchExpression(action, tiles[t].address))
    }
  }
  return { expressions: steps }
}

// Custom layouts a set of changes uses.
function usedSlugs(changes) {
  var slugs = []
  changes.forEach(function(change) {
    var slug = customSlug(change.layout)
    if (slug !== "" && slugs.indexOf(slug) === -1) slugs.push(slug)
  })
  return slugs
}

// `mosaic layout --workspace N NAME`: the new state and the steps.
// `current` is the workspace's tiledLayout now (for `before`). Returns {
// state, expressions, message } or { error }.
function planWorkspaceLayout(list, state, workspace, name, current, loadLua) {
  var id = Number(workspace)
  if (!(id >= 1 && id <= 9999) || Math.floor(id) !== id) return { error: "Unexpected workspace " + JSON.stringify(String(workspace)) }
  var choice = parseLayoutName(name, state.custom)
  if (choice === "") return { error: "Unknown layout " + JSON.stringify(String(name)) + "; use " + layoutChoices(state.custom).map(function(c) { return layoutLabel(c, state.custom) }).join(", ") }
  var next = copyState(state)
  var saved = state.workspaces[id]
  var target
  if (choice === "default") {
    delete next.workspaces[id]
    target = saved && saved.before ? saved.before : "dwindle"
  } else {
    var mosaicNow = String(current || "").indexOf("lua:") === 0
    var before = saved ? saved.before : mosaicNow || !validHyprLayout(current) ? "" : String(current)
    next.workspaces[id] = { layout: choice, before: before }
    target = choice
  }
  var changes = [{ workspace: id, layout: target }]
  var steps = layoutSteps(list, next, changes, usedSlugs(changes), loadLua)
  if (steps.error) return { error: steps.error }
  return { state: next, expressions: steps.expressions, message: "Workspace " + id + ": " + layoutLabel(choice, state.custom) + "." }
}

// Everything saved, applied again: after a start or a config reload, which
// drops runtime layouts and rules. Version 1's session layouts move to
// their sessions' workspaces first. Returns { state, expressions } or {
// error }.
function planSyncLayouts(list, state, loadLua, states) {
  var next = copyState(state)
  Object.keys(state.legacy || {}).forEach(function(session) {
    var workspace = sessionWorkspace(list, session)
    if (workspace !== null && !next.workspaces[workspace]) next.workspaces[workspace] = state.legacy[session]
  })
  var changes = Object.keys(next.workspaces).map(function(id) { return { workspace: Number(id), layout: next.workspaces[id].layout } })
  var steps = layoutSteps(list, next, changes, Object.keys(next.custom).sort(), loadLua, states)
  if (steps.error) return { error: steps.error }
  return { state: next, expressions: steps.expressions }
}

// Saves a custom layout (new, or replacing `oldSlug`), and lays out again
// the workspaces that use it. Returns { state, slug, expressions, message }
// or { error }.
function planSaveCustom(list, state, oldSlug, def, loadLua) {
  var clean = normalizeCustom(def)
  if (!clean) return { error: "Give the layout a name, and zones of at least " + MIN_ZONE + "% that add up to 100%" }
  var slug = layoutSlug(clean.name)
  if (slug !== oldSlug && state.custom[slug]) return { error: "There is already a layout called " + state.custom[slug].name }
  if (oldSlug && !state.custom[oldSlug]) return { error: "No custom layout " + JSON.stringify(String(oldSlug)) }
  var next = copyState(state)
  if (oldSlug && oldSlug !== slug) delete next.custom[oldSlug]
  next.custom[slug] = clean
  var changes = []
  Object.keys(next.workspaces).forEach(function(id) {
    var slugNow = customSlug(next.workspaces[id].layout)
    if (oldSlug && slugNow === oldSlug) {
      next.workspaces[id].layout = CUSTOM_PREFIX + slug
      changes.push({ workspace: Number(id), layout: CUSTOM_PREFIX + slug, refresh: slug === oldSlug })
    }
  })
  var steps = layoutSteps(list, next, changes, [slug], loadLua)
  if (steps.error) return { error: steps.error }
  return { state: next, slug: slug, expressions: steps.expressions, message: "Saved layout " + clean.name + "." }
}

// Deletes a custom layout; workspaces using it get their earlier layout
// back. Returns { state, expressions, message } or { error }.
function planDeleteCustom(list, state, slug, loadLua) {
  if (!state.custom[slug]) return { error: "No custom layout " + JSON.stringify(String(slug)) }
  var next = copyState(state)
  var name = next.custom[slug].name
  delete next.custom[slug]
  var changes = []
  Object.keys(next.workspaces).forEach(function(id) {
    if (customSlug(next.workspaces[id].layout) !== slug) return
    changes.push({ workspace: Number(id), layout: next.workspaces[id].before || "dwindle" })
    delete next.workspaces[id]
  })
  var steps = layoutSteps(list, next, changes, [], loadLua)
  if (steps.error) return { error: steps.error }
  return { state: next, expressions: steps.expressions, message: "Deleted layout " + name + "." }
}

// The layout choice of a workspace: its saved one, or "default".
function workspaceChoice(state, workspace) {
  var entry = state.workspaces[Number(workspace)]
  return entry ? entry.layout : "default"
}

// The Layouts tab's workspaces: the ones Hyprland has ([{ id, monitor,
// windows }], special ones left out) and any with a saved layout, by
// number, each with its choice: [{ id, monitor, windows, choice }].
function layoutWorkspaceRows(workspaces, state) {
  var rows = {}
  ;(workspaces || []).forEach(function(workspace) {
    if (workspace.id >= 1) rows[workspace.id] = { id: workspace.id, monitor: String(workspace.monitor || ""), windows: Number(workspace.windows) || 0 }
  })
  Object.keys(state.workspaces).forEach(function(id) {
    if (!rows[id]) rows[id] = { id: Number(id), monitor: "", windows: 0 }
  })
  return Object.keys(rows).map(function(id) {
    var row = rows[id]
    return { id: row.id, monitor: row.monitor, windows: row.windows, choice: workspaceChoice(state, id) }
  }).sort(function(a, b) { return a.id - b.id })
}

// The rows the tab shows: all of them, or only workspaces with windows or
// a layout of their own (and `keep`, the one under the cursor).
function shownWorkspaceRows(rows, all, keep) {
  if (all) return rows
  return rows.filter(function(row) { return row.windows > 0 || row.choice !== "default" || row.id === keep })
}

// Clients per workspace, from `clients` ([{ workspace }]): { id: count }.
function windowCounts(clients) {
  var counts = {}
  ;(clients || []).forEach(function(client) {
    if (client.workspace >= 1) counts[client.workspace] = (counts[client.workspace] || 0) + 1
  })
  return counts
}

// Custom layouts by name: [{ slug, def }].
function customRows(custom) {
  return Object.keys(custom || {}).map(function(slug) { return { slug: slug, def: custom[slug] } })
    .sort(function(a, b) { return compareText(a.def.name.toLowerCase(), b.def.name.toLowerCase()) })
}

// A name for a new custom layout: "Layout 1", or the next free number.
function freeLayoutName(custom) {
  for (var n = 1; ; n++) {
    if (!(custom || {})[layoutSlug("Layout " + n)]) return "Layout " + n
  }
}

// `mosaic layout`: workspaces with a layout, then custom layouts.
function layoutsText(state) {
  var ids = Object.keys(state.workspaces).sort(function(a, b) { return Number(a) - Number(b) })
  var lines = ids.length === 0 ? ["No workspace has a Mosaic layout."]
    : ids.map(function(id) { return "workspace " + id + "  " + layoutLabel(state.workspaces[id].layout, state.custom) })
  var slugs = Object.keys(state.custom).sort()
  if (slugs.length > 0) {
    lines.push("", "Custom layouts:")
    slugs.forEach(function(slug) { lines.push("  " + state.custom[slug].name + "  (" + customSummary(state.custom[slug]) + ")") })
  }
  return lines.join("\n")
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
    // Position in Hyprland's global layout, in logical pixels.
    origin: [Math.trunc(Number(object.x) || 0), Math.trunc(Number(object.y) || 0)],
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

// Where the window at `address` sits on its monitor, from `hyprctl -j
// clients` and `hyprctl -j monitors` output: { monitor (name), x, y, width,
// height } in the monitor's logical pixels, or null.
function tileRect(clientsText, monitorsText, address) {
  var clients
  try {
    clients = JSON.parse(String(clientsText || ""))
  } catch (error) {
    return null
  }
  var monitors = parseMonitors(monitorsText)
  if (!Array.isArray(clients) || !monitors) return null
  for (var i = 0; i < clients.length; i++) {
    var client = clients[i]
    if (!client || client.address !== address || !Array.isArray(client.at) || !Array.isArray(client.size)) continue
    for (var m = 0; m < monitors.length; m++) {
      if (monitors[m].id !== client.monitor) continue
      return {
        monitor: monitors[m].name,
        x: client.at[0] - monitors[m].origin[0],
        y: client.at[1] - monitors[m].origin[1],
        width: client.size[0],
        height: client.size[1]
      }
    }
  }
  return null
}

// `mosaic list` without --json, from a v1 list. Mirrors `list` in the CLI.
function listText(list) {
  var sessions = list && Array.isArray(list.sessions) ? list.sessions : []
  if (sessions.length === 0) return "No mosaic tiles are open."
  var lines = []
  for (var i = 0; i < sessions.length; i++) {
    lines.push(sessions[i].name)
    for (var j = 0; j < sessions[i].tiles.length; j++) {
      var tile = sessions[i].tiles[j]
      var index = String(tile.index)
      while (index.length < 2) index = " " + index
      var state = tile.state === "contained" ? "" : "  (" + tile.state + ")"
      lines.push("  " + index + "  " + tile.monitor + ":" + tile.workspace + "  " + (tile.url || tile.title) + state)
    }
  }
  return lines.join("\n")
}

// `mosaic webapps` without --json, from a v1 web app list.
function webappsText(webapps) {
  var apps = webapps && Array.isArray(webapps.webapps) ? webapps.webapps : []
  if (apps.length === 0) return "No web apps are installed."
  var width = 0
  for (var i = 0; i < apps.length; i++) width = Math.max(width, apps[i].name.length)
  return apps.map(function(app) {
    var name = app.name
    while (name.length < width) name += " "
    return name + "  " + app.url
  }).join("\n")
}

// `mosaic monitors`, from parseMonitors output.
function monitorsText(monitors) {
  return monitors.map(function(monitor) {
    var area = monitor.workArea
    return (monitor.focused ? "*" : " ") + " " + monitor.name + ": " + monitor.size[0] + "x" + monitor.size[1]
      + " logical, work area " + area.width + "x" + area.height + " at " + area.x + "," + area.y
  }).join("\n")
}

// Targets passed over IPC as one string, one per line; lines are trimmed and
// empty ones dropped. A line can hold a web app name with spaces.
function splitLines(text) {
  return String(text || "").split("\n").map(function(line) { return line.trim() })
    .filter(function(line) { return line !== "" })
}

// The browser extension (extension/), which reaches the service through the
// native host (bin/mosaic-native-host) and the service's bridge socket.

// A line from the bridge socket: a JSON object with a string `type`, or null.
function parseBridgeMessage(line) {
  try {
    var message = JSON.parse(String(line))
    return message && typeof message === "object" && !Array.isArray(message) && typeof message.type === "string" ? message : null
  } catch (error) {
    return null
  }
}

// Browser names by a word in their executable's path or flags file's name,
// most specific first.
var BROWSER_LABELS = [
  ["brave-origin", "Brave Origin"], ["brave", "Brave"], ["chromium", "Chromium"], ["chrome", "Google Chrome"],
  ["msedge", "Microsoft Edge"], ["microsoft-edge", "Microsoft Edge"], ["vivaldi", "Vivaldi"], ["helium", "Helium"], ["opera", "Opera"]
]

function browserLabel(path) {
  var text = String(path || "").toLowerCase()
  for (var i = 0; i < BROWSER_LABELS.length; i++) {
    if (text.indexOf(BROWSER_LABELS[i][0]) !== -1) return BROWSER_LABELS[i][1]
  }
  var name = text.split("/").pop()
  return name || "the browser"
}

// The extension's app windows, keeping only well-formed ones.
function bridgeWindows(list) {
  var windows = []
  var given = Array.isArray(list) ? list : []
  for (var i = 0; i < given.length; i++) {
    var window = given[i]
    if (!window || !Number.isInteger(window.id) || !Array.isArray(window.tabs)) continue
    var tabs = []
    for (var t = 0; t < window.tabs.length; t++) {
      var tab = window.tabs[t]
      if (!tab || !Number.isInteger(tab.id)) continue
      var volume = Number(tab.volume)
      tabs.push({ id: tab.id, url: String(tab.url || ""), title: String(tab.title || ""), favIconUrl: String(tab.favIconUrl || ""),
        audible: tab.audible === true, muted: tab.muted === true, volume: tab.volume === undefined || !(volume >= 0 && volume <= 1) ? 1 : volume })
    }
    windows.push({ id: window.id, type: String(window.type || ""), focused: window.focused === true, tabs: tabs })
  }
  return windows
}

function siteOf(url) {
  var match = /^[a-z]+:\/\/(?:www\.)?([^\/?#:]+)/i.exec(String(url || ""))
  return match ? match[1].toLowerCase() : ""
}

// Which extension window each tile is: `bridges` are the connected
// extensions ({ windows }). A tile keeps the tab it had in `previous` (an
// earlier result's `tiles`, optional) while that tab is still there, since
// a swap in place or the user browsing changes its title and site. Else it
// is the one app window whose tab has the tile's title (Hyprland's title
// is the page's), else the one left on the tile's site. Tiles alike in
// both can only be told apart by focus: `focused` (optional) is the
// address of the window Hyprland has focused, which then takes the one
// window on its site that the browser, in this fresh report, says has
// focus. Returns { total, matched, tiles: { ADDRESS: { bridge, window,
// tab } }, missing: [labels] }.
function matchTiles(tiles, bridges, previous, focused) {
  var candidates = []
  for (var b = 0; b < bridges.length; b++) {
    var windows = bridges[b].windows || []
    for (var w = 0; w < windows.length; w++) {
      if (windows[w].tabs.length === 1)
        candidates.push({ bridge: b, window: windows[w].id, focused: windows[w].focused === true, tab: windows[w].tabs[0] })
    }
  }
  var found = {}
  var taken = []
  function claim(tile, test) {
    if (found[tile.address]) return
    var hits = candidates.filter(function(candidate) { return taken.indexOf(candidate) === -1 && test(candidate) })
    if (hits.length !== 1) return
    taken.push(hits[0])
    found[tile.address] = { bridge: hits[0].bridge, window: hits[0].window, tab: hits[0].tab.id }
  }
  var known = previous || {}
  tiles.forEach(function(tile) {
    var had = known[tile.address]
    if (had) claim(tile, function(candidate) { return candidate.bridge === had.bridge && candidate.tab.id === had.tab })
  })
  tiles.forEach(function(tile) {
    claim(tile, function(candidate) { return tile.title !== "" && candidate.tab.title === tile.title })
  })
  tiles.forEach(function(tile) {
    var site = siteOf(tile.url)
    claim(tile, function(candidate) { return site !== "" && siteOf(candidate.tab.url) === site })
  })
  tiles.forEach(function(tile) {
    if (tile.address !== focused) return
    var site = siteOf(tile.url)
    claim(tile, function(candidate) { return candidate.focused && site !== "" && siteOf(candidate.tab.url) === site })
  })
  var missing = tiles.filter(function(tile) { return !found[tile.address] }).map(tileLabel)
  return { total: tiles.length, matched: tiles.length - missing.length, tiles: found, missing: missing }
}

// Where the extension's setup stands: "connected" once an extension talks
// to the service, "restart" when it is set up but the browser has not
// loaded it yet, "off", or "unknown" before the host's status is in.
// `setup` is `mosaic-native-host status` output.
function extensionState(setup, bridges) {
  if (bridges.length > 0) return "connected"
  if (!setup) return "unknown"
  var registered = setup.browsers.some(function(browser) { return browser.registered })
  var loaded = setup.flags.some(function(flags) { return flags.loaded })
  return registered && loaded ? "restart" : "off"
}

function flagsName(file) {
  return String(file).split("/").pop()
}

function joinNames(names) {
  var unique = names.filter(function(name, index) { return names.indexOf(name) === index })
  if (unique.length <= 1) return unique.join("")
  return unique.slice(0, -1).join(", ") + " and " + unique[unique.length - 1]
}

// Names for a checklist line: up to three, else the first two and a count.
function shortNames(names) {
  return names.length <= 3 ? joinNames(names) : names.slice(0, 2).join(", ") + " and " + (names.length - 2) + " more"
}

function loadedBrowsers(setup) {
  return joinNames(setup.flags.filter(function(flags) { return flags.loaded })
    .map(function(flags) { return browserLabel(flagsName(flags.file)) }))
}

// The Extension tab's summary of `extensionState`.
function extensionNotice(setup, bridges) {
  var state = extensionState(setup, bridges)
  if (state === "connected")
    return "Connected to " + joinNames(bridges.map(function(bridge) { return browserLabel(bridge.browser) })) + ". Your tiles are checked whenever they change; V checks that it still answers."
  if (state === "unknown") return "Checking the browser extension…"
  if (state === "restart")
    return "Set up. Restart " + loadedBrowsers(setup) + " to load the extension, then verify. Closing the browser also closes its tiles."
  if (setup.flags.length === 0)
    return "Audio control needs the Mosaic browser extension. No browser flags file was found, so load it by hand (below)."
  return "Audio control needs the Mosaic browser extension. Enable registers it and loads it every time the browser starts."
}

// The Extension tab's checklist: [{ label, detail, done }]. `check` is the last
// verify ({ error } or matchTiles output), or null.
function extensionSteps(setup, bridges, check) {
  var browsers = setup ? setup.browsers : []
  var flags = setup ? setup.flags : []
  var registered = browsers.filter(function(browser) { return browser.registered })
  var loaded = flags.filter(function(file) { return file.loaded })
  var verified = ""
  if (!check) verified = bridges.length > 0 ? "Checking…" : "Checked on its own once connected"
  else if (check.error) verified = check.error
  else if (check.total === 0) verified = "No tiles are open to look for"
  else verified = check.matched + " of " + check.total + " tiles" + (check.missing.length > 0 ? "  ·  not found: " + check.missing.join(", ") : "")
  return [
    {
      label: "Bridge registered",
      done: registered.length > 0,
      detail: registered.length > 0 ? shortNames(registered.map(function(browser) { return browser.name }))
        : browsers.length > 0 ? "Enable registers it with " + shortNames(browsers.map(function(browser) { return browser.name }))
        : "No Chromium-family browser profile found"
    },
    {
      label: "Loads when the browser starts",
      done: loaded.length > 0,
      detail: loaded.length > 0 ? joinNames(loaded.map(function(file) { return flagsName(file.file) }))
        : flags.length > 0 ? "Enable adds it to " + joinNames(flags.map(function(file) { return flagsName(file.file) }))
        : "No flags file; load it by hand"
    },
    {
      label: "Connected",
      done: bridges.length > 0,
      detail: bridges.length > 0
        ? bridges.map(function(bridge) { return browserLabel(bridge.browser) + " · extension " + (bridge.extension || "?") }).join(", ")
        : "Restart the browser after enabling"
    },
    {
      label: "Finds your tiles",
      done: !!check && !check.error && check.total > 0 && check.matched === check.total,
      detail: verified
    }
  ]
}

// A browser's window class from its desktop id or program path:
// "brave-origin.desktop" and "~/.local/bin/brave-origin" give "brave-origin".
function browserClass(text) {
  return String(text || "").split("/").pop().replace(/\.desktop$/, "")
}

// The browser processes a restart stops, from `hyprctl -j clients` text:
// those of mosaic tiles, and of windows whose class is one of `classes`.
// Returns sorted PIDs, or null for unexpected output.
function browserPids(clientsText, classes) {
  var parsed
  try {
    parsed = JSON.parse(String(clientsText || ""))
  } catch (error) {
    return null
  }
  if (!Array.isArray(parsed)) return null
  var pids = []
  parsed.forEach(function(client) {
    if (!client || !Number.isInteger(client.pid) || client.pid <= 1) return
    var tile = stringList(client.tags).indexOf(TAG) !== -1
    if ((tile || classes.indexOf(String(client.class || "")) !== -1) && pids.indexOf(client.pid) === -1) pids.push(client.pid)
  })
  return pids.sort(function(a, b) { return a - b })
}

// { version, script } from the extension's manifest.json text, or null.
function extensionFromManifest(text) {
  try {
    var manifest = JSON.parse(String(text || ""))
    var script = manifest && manifest.background ? manifest.background.service_worker : ""
    return manifest && typeof manifest.version === "string" && typeof script === "string" && script !== ""
      ? { version: manifest.version, script: script } : null
  } catch (error) {
    return null
  }
}

// Whether a connected extension can do `feature` ("mute", "volume", …).
// Its version can't say: Brave has run an old worker script under a new
// manifest. From background-3.js on, hello lists the features;
// background-2.js had only mute.
function bridgeHas(bridge, feature) {
  if (Array.isArray(bridge.features)) return bridge.features.indexOf(feature) !== -1
  return feature === "mute" && bridge.script === "background-2.js"
}

// A tile volume from 0 to 1 after stepping `current` by `delta`, in 5%
// steps, or from a percentage the user typed ("40", "+10", "-10").
function stepVolume(current, delta) {
  var next = Math.round((Number(current) + Number(delta)) * 20) / 20
  return Math.max(0, Math.min(1, next))
}

function parseVolume(text, current) {
  var match = /^\s*([+-]?)(\d{1,3})\s*%?\s*$/.exec(String(text || ""))
  if (!match) return null
  var amount = Number(match[2]) / 100
  var level = match[1] === "+" ? current + amount : match[1] === "-" ? current - amount : amount
  return Math.max(0, Math.min(1, Math.round(level * 100) / 100))
}

// Each found tile's audio, from a check (matchTiles output) and the bridges
// it was made from: { ADDRESS: { bridge, tab, audible, muted } }.
// Squares the levels the user set (`volumes`, by address) with what the
// extension reports (`audio`, from tileAudio). A browser whose extension
// can `follow` reports the tab's real level, including changes made with
// the page's own controls, so its report wins, except for a tile set in
// the last moments (`recent`), whose report may still be on its way. An
// older extension forgets levels when its worker stops, so those tiles
// are set again (`resend`). Tiles no longer in `live` are dropped.
// Returns { volumes, resend }.
function reconcileVolumes(volumes, audio, live, follows, recent) {
  var next = {}
  var resend = []
  Object.keys(volumes).forEach(function(address) {
    if (live.indexOf(address) === -1) return
    var level = volumes[address]
    var entry = audio[address]
    if (entry && Math.abs(entry.volume - level) > 0.001) {
      if (!follows(entry.bridge)) resend.push(address)
      else if (!recent(address)) level = entry.volume
    }
    next[address] = level
  })
  return { volumes: next, resend: resend }
}

// The tile-to-tab pairings worth keeping (see matchTiles' `previous`):
// `saved` ones, updated by the latest `check`, for the tiles at
// `addresses` only. Saved across shell restarts, since a restart forgets
// them and the browser's tab ids outlive it.
function keepTabs(saved, check, addresses) {
  var merged = Object.assign({}, saved || {}, check && check.tiles ? check.tiles : {})
  var kept = {}
  addresses.forEach(function(address) {
    var entry = merged[address]
    if (entry && Number.isInteger(entry.bridge) && Number.isInteger(entry.tab)) kept[address] = entry
  })
  return kept
}

// The extension's report of a tile's tab ({ url, title, … }), or null.
function tileTab(check, bridges, address) {
  var found = check && check.tiles ? check.tiles[address] : null
  var bridge = found ? bridges[found.bridge] : null
  if (!bridge) return null
  for (var w = 0; w < bridge.windows.length; w++) {
    var tabs = bridge.windows[w].tabs
    for (var t = 0; t < tabs.length; t++) if (tabs[t].id === found.tab) return tabs[t]
  }
  return null
}

// Whether a tab sent to `url` has arrived: it is on that site and shows a
// title of its own, other than `oldTitle`, the page it left.
function navigationSettled(tab, url, oldTitle) {
  if (!tab || siteOf(tab.url) !== siteOf(url)) return false
  var title = String(tab.title || "")
  // Before the page sets one, Chromium shows the address as the title.
  var bare = title.toLowerCase().replace(/^[a-z]+:\/\//, "").replace(/^www\./, "").split("/")[0]
  return title !== "" && title !== String(oldTitle || "") && bare !== siteOf(url)
}

function tileAudio(check, bridges) {
  var audio = {}
  if (!check || !check.tiles) return audio
  Object.keys(check.tiles).forEach(function(address) {
    var found = check.tiles[address]
    var bridge = bridges[found.bridge]
    if (!bridge) return
    bridge.windows.forEach(function(window) {
      window.tabs.forEach(function(tab) {
        if (tab.id === found.tab) audio[address] = { bridge: found.bridge, tab: tab.id, audible: tab.audible, muted: tab.muted, volume: tab.volume }
      })
    })
  })
  return audio
}

// The mute changes that leave only the tile at `focused` unmuted, as
// [{ bridge, tab, muted }]; none when that tile has no audio entry.
function focusMutes(audio, focused) {
  if (!audio[focused]) return []
  return Object.keys(audio).filter(function(address) {
    return audio[address].muted !== (address !== focused)
  }).map(function(address) {
    return { bridge: audio[address].bridge, tab: audio[address].tab, muted: address !== focused }
  })
}

// The icon for a tile's audio: muted, playing (loud or turned down), or
// silent.
function audioIcon(entry) {
  if (!entry) return ""
  if (entry.muted) return "󰖁"
  if (!entry.audible) return "󰕿"
  return entry.volume !== undefined && entry.volume < 0.5 ? "󰖀" : "󰕾"
}
