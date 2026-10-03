import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"

const source = fs.readFileSync(new URL("../Model.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*/m, "")
const model = {}
vm.runInNewContext(source + "\nObject.assign(model, {  zoneCount, newCustom, zoneDividers, withDivider, withoutZone, withSplit, ordinal, reconcileVolumes, layoutWorkspaceRows, shownWorkspaceRows, windowCounts, customRows, freeLayoutName, layoutChoices, layoutLabel, nextLayout, parseLayoutName, hyprLayoutName, layoutSlug, normalizeCustom, visualZones, defineLua, withZoneSize, withMain, withName, customSummary, parseLayouts, serializeLayouts, layoutsLoadLua, layoutsLoaded, layoutRuleLua, sessionWorkspace, tileStates, planWorkspaceLayout, planSyncLayouts, planSaveCustom, planDeleteCustom, workspaceChoice, layoutsText, hiddenEntries, showWebapp, nameList, visibleWebapps, hideWebapp, sessionOf, clientFromIpc, parseStore, tileState, buildList, shapeList, parseClients, validAddress, dispatchExpression, listTiles, findTile, planFocus, planRemove, planClose, planContain, planAutoContain, restoreAfterMove, monitorFromIpc, parseMonitors, resolveAddTargets, chooseWorkspace, desktopId, isChromiumFamily, isAppWindow, parseOpenWindow, tileDispatches, pruneRecords, serializeStore, planReplace, replaceRecord, parseCursorPos, cursorMoveExpression, parseKeySpec, bindConflict, tileRect, listText, webappsText, monitorsText, splitLines, parseBridgeMessage, browserLabel, bridgeWindows, siteOf, matchTiles, keepTabs, tileTab, navigationSettled, extensionState, extensionNotice, extensionSteps, browserClass, browserPids, tileAudio, focusMutes, audioIcon, extensionFromManifest, bridgeHas, stepVolume, parseVolume, swapBindLua, unbindLua, webappUrl, webappFromEntry, buildWebapps, shapeWebapps, findWebapp, resolveTarget, parseList, tileLabel, tileMeta, sessionPlace, tileApp, tileName, tileSubtitle, tileInitial, layoutBoxes, keyHints, normalizeUrl, sessionName, summary, anyUncontained, parseManifest });", { model })

// Values built inside the VM belong to another realm, so compare copies.
const plain = value => JSON.parse(JSON.stringify(value))

const fixture = fs.readFileSync(new URL("fixtures/list.json", import.meta.url), "utf8")
const list = model.parseList(fixture)
assert.equal(list.error, "")
assert.deepEqual(plain(list.sessions.map(session => [session.name, session.tiles.length])), [["news", 1], ["streams", 2]])
assert.deepEqual(plain(list.tiles.map(tile => [tile.index, tile.session, tile.position])), [[1, "news", 0], [2, "streams", 1], [3, "streams", 2]])
assert.equal(model.summary(list.sessions, list.tiles), "3 tiles  ·  2 sessions")
assert.equal(model.summary([], []), "No tiles open")
assert.equal(model.anyUncontained(list.tiles), true)

assert.equal(model.parseList('{"sessions":[]}').error.includes("not supported"), true)
assert.equal(model.parseList('{"version":2,"sessions":[]}').error.includes("not supported"), true)
assert.equal(model.parseList("mosaic: oops").error, "Unexpected output from mosaic list")
assert.equal(model.parseList('{"version":1,"sessions":[]}').tiles.length, 0)

assert.equal(model.tileLabel(list.tiles[1]), "twitch.tv/somechannel")
assert.equal(model.tileLabel({ url: "https://www.youtube.com/", title: "x", index: 1 }), "youtube.com")
assert.equal(model.tileLabel({ url: "", title: "Some page", index: 4 }), "Some page")
assert.equal(model.tileLabel({ url: "", title: "", index: 4 }), "Tile 4")
assert.equal(model.tileMeta(list.tiles[0]), "DP-4 · workspace 10")
assert.equal(model.tileMeta(list.tiles[2]), "fullscreen not contained  ·  DP-5 · workspace 1")
assert.equal(model.sessionPlace(list.sessions[1].tiles), "DP-5 · workspace 1")
assert.equal(model.sessionPlace([list.tiles[0], list.tiles[1]]), "")
assert.equal(model.tileMeta(list.tiles[1], "DP-5 · workspace 1"), "twitch.tv/somechannel")
assert.equal(model.tileMeta(list.tiles[2], "DP-5 · workspace 1"), "fullscreen not contained")
const twitchApp = { name: "Twitch", url: "https://twitch.tv" }
assert.equal(model.tileSubtitle({ url: "https://x.com/", title: "Home / X", index: 1 }), "Home")
assert.equal(model.tileSubtitle({ url: "https://x.com/", title: "x.com", index: 1 }), "")
assert.equal(model.tileSubtitle({ url: "https://x.com/", title: "(3) Home / X", index: 1 }, { name: "X" }), "Home")
assert.equal(model.tileSubtitle({ url: "https://twitch.tv", title: "(5) Richellyna - Twitch", index: 1 }, twitchApp), "Richellyna")
assert.equal(model.tileSubtitle({ url: "https://youtube.com/", title: "YouTube", index: 1 }, { name: "YouTube" }), "")
assert.equal(model.tileSubtitle({ url: "https://kick.com/", title: "Kick: live - Kick", index: 1 }), "Kick: live")
assert.equal(model.tileApp([twitchApp], list.tiles[1]).name, "Twitch")
assert.equal(model.tileApp([twitchApp], list.tiles[0]), null)
assert.equal(model.tileName(list.tiles[1], twitchApp), "Twitch")
assert.equal(model.tileName(list.tiles[0], null), "bbc.com")
assert.equal(model.tileName({ url: "", title: "Some page", index: 2 }, null), "Some page")
assert.equal(model.tileInitial(list.tiles[0], null), "B")
assert.equal(model.tileInitial({ url: "", title: "", index: 4 }, null), "T")

// The panel's picture of a layout: fractions in fill order.
const rounded = boxes => plain(boxes).map(b => [b.x, b.y, b.w, b.h].map(v => Math.round(v * 1000) / 1000))
assert.deepEqual(rounded(model.layoutBoxes("stack", {}, 2, 16 / 9)), [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1]])
assert.deepEqual(rounded(model.layoutBoxes("grid", {}, 3, 16 / 9)), [[0, 0, 0.5, 0.5], [0.5, 0, 0.5, 0.5], [0, 0.5, 1, 0.5]])
assert.deepEqual(rounded(model.layoutBoxes("main", {}, 3, 16 / 9)), [[0, 0, 0.7, 1], [0.7, 0, 0.3, 0.5], [0.7, 0.5, 0.3, 0.5]])
assert.deepEqual(rounded(model.layoutBoxes("fit", {}, 1, 16 / 9)), [[0, 0, 1, 1]])
assert.deepEqual(rounded(model.layoutBoxes("default", {}, 3, 16 / 9)), [[0, 0, 0.5, 1], [0.5, 0, 0.5, 0.5], [0.5, 0.5, 0.5, 0.5]])
assert.deepEqual(rounded(model.layoutBoxes("custom:gone", {}, 2, 16 / 9)), [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1]])
const threeCols = model.newCustom("Three", "columns")
assert.deepEqual(rounded(model.layoutBoxes("custom:three", { three: threeCols }, 4, 16 / 9)),
  [[0.25, 0, 0.5, 1], [0, 0, 0.25, 1], [0.75, 0, 0.25, 0.5], [0.75, 0.5, 0.25, 0.5]])
assert.equal(model.layoutBoxes("grid", {}, 0, 1).length, 0)
assert.deepEqual(rounded(model.layoutBoxes("stack", {}, 2, 9 / 16)), [[0, 0, 1, 0.5], [0, 0.5, 1, 0.5]])
assert.deepEqual(rounded(model.layoutBoxes("main", {}, 3, 9 / 16)), [[0, 0, 1, 0.7], [0, 0.7, 0.5, 0.3], [0.5, 0.7, 0.5, 0.3]])

assert.equal(model.normalizeUrl(" twitch.tv/foo "), "https://twitch.tv/foo")
assert.equal(model.normalizeUrl("https://kick.com"), "https://kick.com")
assert.equal(model.normalizeUrl("localhost:8080/x"), "https://localhost:8080/x")
assert.equal(model.normalizeUrl("javascript:alert(1)"), "")
assert.equal(model.normalizeUrl("two words"), "")
assert.equal(model.normalizeUrl(""), "")

assert.equal(model.sessionName(""), "default")
assert.equal(model.sessionName(" streams "), "streams")
assert.equal(model.sessionName("Streams"), "")
assert.equal(model.sessionName("a\"b"), "")

const manifest = JSON.parse(fs.readFileSync(new URL("../manifest.json", import.meta.url), "utf8"))
assert.deepEqual(plain(model.parseManifest(JSON.stringify(manifest))), { name: manifest.name, version: manifest.version })
assert.equal(model.parseManifest("{"), null)
assert.equal(model.parseManifest("{}"), null)

const webapps = model.shapeWebapps({ version: 1, webapps: [
  { id: "Twitch", name: "Twitch", url: "https://twitch.tv", icon: "twitch" },
  { id: "chat", name: "Team Chat", url: "https://chat.example", icon: "/icons/chat.png" },
  { id: "broken", name: "No URL" }
] })
assert.equal(webapps.error, "")
assert.deepEqual(plain(webapps.apps.map(app => app.name)), ["Twitch", "Team Chat"])
assert.equal(model.findWebapp(webapps.apps, " twitch ").url, "https://twitch.tv")
assert.equal(model.findWebapp(webapps.apps, "CHAT").name, "Team Chat")
assert.equal(model.findWebapp(webapps.apps, "kick"), null)
assert.equal(model.resolveTarget("team chat", webapps.apps), "https://chat.example")
assert.equal(model.resolveTarget("kick.com", webapps.apps), "https://kick.com")
assert.deepEqual(plain(model.nameList(" Twitch, team chat,,TWITCH ")), ["twitch", "team chat"])
assert.deepEqual(plain(model.nameList("")), [])
assert.deepEqual(plain(model.visibleWebapps(webapps.apps, "twitch").map(app => app.name)), ["Team Chat"])
assert.deepEqual(plain(model.visibleWebapps(webapps.apps, "CHAT").map(app => app.name)), ["Twitch"])
assert.equal(model.visibleWebapps(webapps.apps, "").length, 2)
assert.equal(model.hideWebapp("", webapps.apps[0]), "Twitch")
assert.equal(model.hideWebapp("Kick,", webapps.apps[1]), "Kick, Team Chat")
assert.equal(model.hideWebapp("twitch", webapps.apps[0]), "twitch")
const hiddenRows = model.hiddenEntries(webapps.apps, "kick, chat, Team Chat, twitch")
assert.deepEqual(plain(hiddenRows.map(row => [row.key, row.label, row.app ? row.app.id : null])),
  [["kick", "kick", null], ["chat", "Team Chat", "chat"], ["twitch", "Twitch", "Twitch"]])
assert.equal(model.showWebapp("Kick, chat, Team Chat, Twitch", hiddenRows[1]), "Kick, Twitch")
assert.equal(model.showWebapp("Kick, Twitch", hiddenRows[0]), "Twitch")
assert.equal(model.showWebapp("Twitch", hiddenRows[2]), "")
assert.equal(model.hiddenEntries(webapps.apps, "").length, 0)
// A hidden web app can still be added by typing its name.
assert.equal(model.resolveTarget("twitch", webapps.apps), "https://twitch.tv")
assert.equal(model.shapeWebapps(null).apps.length, 0)
assert.equal(model.shapeWebapps({ version: 9, webapps: [] }).error.includes("not supported"), true)

// Ported from webapps::tests. DesktopEntries has already split Exec into
// argv, removing quotes and escapes, and dropped Hidden and NoDisplay entries.
const entry = (id, name, command, extra = {}) => ({ id, name, icon: "", noDisplay: false, command, ...extra })
assert.deepEqual(plain(model.webappFromEntry(entry("Twitch", "Twitch", ["omarchy-launch-webapp", "https://twitch.tv", "--disable-gpu"], { icon: "twitch" }))),
  { icon: "twitch", id: "Twitch", name: "Twitch", url: "https://twitch.tv" })
assert.equal(model.webappUrl(["/usr/bin/omarchy-launch-webapp", "https://x.com/"]), "https://x.com/")
assert.equal(model.webappUrl(["brave", "--profile-directory=Default", "--app=https://chat.example"]), "https://chat.example")
assert.equal(model.webappUrl(["brave"]), "")
assert.equal(model.webappUrl(["omarchy-launch-webapp", "file:///etc/passwd"]), "")
assert.equal(model.webappUrl(["brave", "--app=javascript:alert(1)"]), "")
assert.equal(model.webappUrl(["omarchy-launch-webapp"]), "")
assert.equal(model.webappUrl(undefined), "")
assert.equal(model.webappFromEntry(entry("brave", "Brave", ["brave"])), null)
assert.equal(model.webappFromEntry(entry("quiet", "Quiet", ["omarchy-launch-webapp", "https://a"], { noDisplay: true })), null)
assert.equal(model.webappFromEntry(entry("", "No id", ["omarchy-launch-webapp", "https://a"])), null)
assert.equal(model.webappFromEntry(null), null)

const installed = plain(model.buildWebapps([
  entry("YouTube", "YouTube", ["omarchy-launch-webapp", "https://youtube.com/"], { icon: "youtube" }),
  entry("brave-browser", "Brave", ["brave", "%U"]),
  entry("Kick", "Kick", ["omarchy-launch-webapp", "https://kick.com"], { icon: "kick" }),
  entry("chat", "team chat", ["brave", "--app=https://chat.example"])
]))
assert.deepEqual(installed, { version: 1, webapps: [
  { icon: "kick", id: "Kick", name: "Kick", url: "https://kick.com" },
  { icon: "", id: "chat", name: "team chat", url: "https://chat.example" },
  { icon: "youtube", id: "YouTube", name: "YouTube", url: "https://youtube.com/" }
] })
assert.deepEqual(plain(model.buildWebapps([])), { version: 1, webapps: [] })
// What the service builds is what the panel reads.
assert.deepEqual(plain(model.shapeWebapps(model.buildWebapps([entry("Kick", "Kick", ["omarchy-launch-webapp", "https://kick.com"])])).apps),
  [{ id: "Kick", name: "Kick", url: "https://kick.com", icon: "" }])

// Ported from session::tests::groups_tiles_by_session_in_added_order.
const client = (address, tags, extra = {}) => ({ address, title: "", workspace: 1, monitor: 0, tags, floating: false, fullscreen: 0, fullscreenClient: 2, ...extra })
const clients = [
  client("0xa", ["mosaic", "mosaic-news"]),
  client("0xb", ["default-opacity*"]),
  client("0xc", ["mosaic", "mosaic-streams"]),
  client("0xd", ["mosaic", "mosaic-streams"]),
  client("0xe", ["mosaic"])
]
const records = [
  { address: "0xd", session: "streams", url: "https://d" },
  { address: "0xc", session: "streams", url: "https://c" },
  { address: "0xgone", session: "streams", url: "https://x" }
]
const built = plain(model.buildList(clients, [], records))
assert.equal(built.version, 1)
assert.deepEqual(built.sessions.flatMap(s => s.tiles.map(t => [t.index, s.name, t.address])),
  [[1, "default", "0xe"], [2, "news", "0xa"], [3, "streams", "0xd"], [4, "streams", "0xc"]])
assert.equal(built.sessions[2].tiles[0].url, "https://d")
assert.equal(built.sessions[0].tiles[0].url, null)
assert.equal(built.sessions[0].tiles[0].monitor, "?")

// Tiles missing from the store sort after recorded ones, then by address.
const unordered = plain(model.buildList([client("0x2", ["mosaic"]), client("0x9", ["mosaic"]), client("0x1", ["mosaic"])], [],
  [{ address: "0x9", session: "default", url: "https://9" }]))
assert.deepEqual(unordered.sessions[0].tiles.map(t => t.address), ["0x9", "0x1", "0x2"])

// The built object is what `mosaic list --json` prints, so it shapes the same way.
const monitors = [{ id: 0, name: "DP-5" }, { id: 1, name: "DP-4" }]
const live = model.buildList([
  client("0x3", ["mosaic", "mosaic-streams"], { monitor: 0, workspace: 1, title: "Kick", fullscreenClient: 0 }),
  client("0x1", ["mosaic", "mosaic-news"], { monitor: 1, workspace: 10, title: "BBC News" }),
  client("0x2", ["mosaic", "mosaic-streams"], { monitor: 0, workspace: 1, title: "somechannel - Twitch" })
], monitors, [
  { address: "0x1", session: "news", url: "https://www.bbc.com/news" },
  { address: "0x2", session: "streams", url: "https://www.twitch.tv/somechannel/" }
])
assert.deepEqual(plain(live), JSON.parse(fixture))
assert.deepEqual(plain(model.shapeList(live)), plain(list))
assert.equal(model.shapeList(null).error.includes("not supported"), true)

assert.equal(model.sessionOf(["mosaic", "mosaic-streams"]), "streams")
assert.equal(model.sessionOf(["mosaic"]), "default")
assert.equal(model.sessionOf(["mosaic-streams"]), null)
assert.equal(model.sessionOf(undefined), null)

assert.equal(model.tileState(client("0x1", [], { floating: true, fullscreen: 1 })), "floating")
assert.equal(model.tileState(client("0x1", [], { fullscreen: 2 })), "fullscreen")
assert.equal(model.tileState(client("0x1", [])), "contained")
assert.equal(model.tileState(client("0x1", [], { fullscreenClient: 0 })), "uncontained")

// Shaped like a real lastIpcObject from Hyprland 0.56.
assert.deepEqual(plain(model.clientFromIpc({ address: "0x5f4cce94d400", class: "foot", title: "~", workspace: { id: 1, name: "1" },
  monitor: 0, tags: ["default-opacity*", "terminal*"], floating: false, fullscreen: 0, fullscreenClient: 0 })),
  { address: "0x5f4cce94d400", title: "~", workspace: 1, monitor: 0, tags: ["default-opacity*", "terminal*"], floating: false, fullscreen: 0, fullscreenClient: 0 })
assert.equal(model.clientFromIpc({}), null)
assert.equal(model.clientFromIpc(undefined), null)
assert.deepEqual(plain(model.clientFromIpc({ address: "0x1" }).tags), [])

assert.deepEqual(plain(model.parseStore('{"tiles":[{"address":"0x1","session":"s","url":"https://a"},{"address":"0x2"},null]}')),
  [{ address: "0x1", session: "s", url: "https://a" }])
assert.deepEqual(plain(model.parseStore("")), [])
assert.deepEqual(plain(model.parseStore('{"tiles":5}')), [])

// Ported from platform::tests::rejects_non_hex_addresses.
assert.equal(model.validAddress("0x5f4ccce343a0"), true)
assert.equal(model.validAddress('0x5f" }) os.exit() --'), false)
assert.equal(model.validAddress(""), false)
assert.equal(model.validAddress("0x"), false)
assert.equal(model.validAddress("5f4c"), false)
assert.equal(model.dispatchExpression("focus", "0x1a"), 'hl.dsp.focus({ window = "address:0x1a" })')
assert.equal(model.dispatchExpression("close", "0x1a"), 'hl.dsp.window.close({ window = "address:0x1a" })')
assert.equal(model.dispatchExpression("contain", "0x1a"), 'hl.dsp.window.fullscreen_state({ internal = 0, client = 2, window = "address:0x1a" })')
assert.equal(model.dispatchExpression("close", '0x1" })'), "")
assert.equal(model.dispatchExpression("explode", "0x1a"), "")

assert.deepEqual(plain(model.parseClients('[{"address":"0xa","tags":["mosaic"]},{"title":"no address"}]').map(c => c.address)), ["0xa"])
assert.equal(model.parseClients("hyprctl: oops"), null)
assert.equal(model.parseClients('{"address":"0xa"}'), null)

// `live` above: 1 news 0x1 (contained), 2 streams 0x2 (contained), 3 streams 0x3 (uncontained).
assert.deepEqual(plain(model.listTiles(live).map(t => [t.index, t.session, t.address, t.state])),
  [[1, "news", "0x1", "contained"], [2, "streams", "0x2", "contained"], [3, "streams", "0x3", "uncontained"]])
assert.equal(model.findTile(model.listTiles(live), "2").address, "0x2")
assert.equal(model.findTile(model.listTiles(live), 3).address, "0x3")
assert.equal(model.findTile(model.listTiles(live), "0x1").index, 1)
assert.equal(model.findTile(model.listTiles(live), "4"), null)
assert.equal(model.findTile(model.listTiles(live), "1.0"), null)

assert.deepEqual(plain(model.planFocus(live, "0x2")), { error: "", expressions: ['hl.dsp.focus({ window = "address:0x2" })'], message: "" })
assert.equal(model.planFocus(live, "9").error, 'No mosaic tile "9"; see `mosaic list`')
const removal = plain(model.planRemove(live, ["3", "0x1", "1"]))
assert.equal(removal.error, "")
assert.deepEqual(removal.expressions, ['hl.dsp.window.close({ window = "address:0x3" })', 'hl.dsp.window.close({ window = "address:0x1" })'])
assert.equal(removal.message, "Removed 2 tile(s).")
// A typo anywhere closes nothing.
assert.deepEqual(plain(model.planRemove(live, ["1", "7"])), { error: 'No mosaic tile "7"; see `mosaic list`' })
assert.equal(model.planRemove(live, []).error, "Name at least one tile to remove")
assert.equal(model.planClose(live, "streams").expressions.length, 2)
assert.equal(model.planClose(live, "").message, "Closed 3 tile(s).")
assert.equal(model.planClose(live, "nothing").message, "Closed 0 tile(s).")
assert.equal(model.planClose(live, "Streams").error.startsWith('Invalid session name "Streams"'), true)
assert.deepEqual(plain(model.planContain(live, null)), { error: "",
  expressions: ['hl.dsp.window.fullscreen_state({ internal = 0, client = 2, window = "address:0x3" })'],
  message: "Contained fullscreen in 1 tile(s)." })
assert.equal(model.planContain(live, "news").expressions.length, 0)
// An address that is not hex never reaches a dispatch.
const forged = { version: 1, sessions: [{ name: "x", tiles: [{ index: 1, address: '0x1" }) os.exit() --', state: "uncontained" }] }] }
assert.equal(model.planClose(forged, "").error.startsWith("Unexpected Hyprland window address"), true)
assert.equal(model.planContain(forged, "").error.startsWith("Unexpected Hyprland window address"), true)
// Keep fullscreen in tiles: lost containment always, true fullscreen once
// another window has focus, never floating tiles or forged addresses.
const states = { version: 1, sessions: [{ name: "x", tiles: [
  { index: 1, address: "0xa", state: "contained" },
  { index: 2, address: "0xb", state: "uncontained" },
  { index: 3, address: "0xc", state: "fullscreen" },
  { index: 4, address: "0xd", state: "floating" }] }] }
const containOf = address => 'hl.dsp.window.fullscreen_state({ internal = 0, client = 2, window = "address:' + address + '" })'
assert.deepEqual(plain(model.planAutoContain(states, "0xc")), [containOf("0xb")])
assert.deepEqual(plain(model.planAutoContain(states, "0xb")), [containOf("0xb"), containOf("0xc")])
assert.deepEqual(plain(model.planAutoContain(forged, "")), [])

// `live`: 0x1 and 0x2 contained, 0x3 uncontained.
assert.equal(model.restoreAfterMove(live, "1,10,10"), 'hl.dsp.window.fullscreen_state({ internal = 0, client = 2, window = "address:0x1" })')
assert.equal(model.restoreAfterMove(live, "0x2,4,4"), 'hl.dsp.window.fullscreen_state({ internal = 0, client = 2, window = "address:0x2" })')
assert.equal(model.restoreAfterMove(live, "3,4,4"), 'hl.dsp.window.fullscreen_state({ internal = 0, client = 0, window = "address:0x3" })')
assert.equal(model.restoreAfterMove(live, "ff,4,4"), "")
assert.equal(model.restoreAfterMove(live, ""), "")
assert.equal(model.restoreAfterMove(model.buildList([client("0x7", ["mosaic"], { floating: true })], [], []), "7,1,1"), "")
assert.equal(model.restoreAfterMove(model.buildList([client("0x8", ["mosaic"], { fullscreen: 2 })], [], []), "8,1,1"), "")
assert.equal(model.dispatchExpression("release", "0x1a"), 'hl.dsp.window.fullscreen_state({ internal = 0, client = 0, window = "address:0x1a" })')

// Ported from platform::tests::rotated_scaled_monitor_uses_logical_portrait_size.
assert.deepEqual(plain(model.monitorFromIpc({ id: 0, name: "DP-1", activeWorkspace: { id: 3 }, x: 0, y: 0, width: 2560, height: 1440,
  scale: 1.25, transform: 1, reserved: [0, 26, 0, 0] })),
  { id: 0, name: "DP-1", focused: false, activeWorkspace: 3, origin: [0, 0], size: [1152, 2048], workArea: { x: 0, y: 26, width: 1152, height: 2022 } })
const monitorsJson = JSON.stringify([
  { id: 1, name: "DP-4", focused: false, activeWorkspace: { id: 10 }, x: 0, y: 0, width: 1920, height: 1080, scale: 1, transform: 0, reserved: [0, 0, 0, 0] },
  { id: 0, name: "DP-5", focused: true, activeWorkspace: { id: 1 }, x: 1920, y: 0, width: 2560, height: 1440, scale: 1.25, transform: 0, reserved: [0, 26, 0, 0] },
  { id: 2, name: "HDMI-A-1", disabled: true, activeWorkspace: { id: 5 }, width: 1, height: 1 }
])
const screens = model.parseMonitors(monitorsJson)
assert.deepEqual(plain(screens.map(m => [m.name, m.activeWorkspace, m.focused, m.size])), [["DP-4", 10, false, [1920, 1080]], ["DP-5", 1, true, [2048, 1152]]])
assert.equal(model.parseMonitors("nope"), null)

const apps = model.shapeWebapps({ version: 1, webapps: [{ id: "Twitch", name: "Twitch", url: "https://twitch.tv" }] }).apps
assert.deepEqual(plain(model.resolveAddTargets(["https://kick.com", "twitch", "file:///tmp/a.html"], apps)),
  { urls: ["https://kick.com", "https://twitch.tv", "file:///tmp/a.html"] })
assert.deepEqual(plain(model.resolveAddTargets(["twitch", "twich"], apps)),
  { error: '"twich" is neither a URL (http, https, or file) nor a web app; see `mosaic webapps`' })
assert.equal(model.resolveAddTargets(["javascript:alert(1)"], apps).error.includes("neither a URL"), true)
assert.equal(model.resolveAddTargets([], apps).error, "Pass 1 to 9 URLs or web apps")
assert.equal(model.resolveAddTargets(Array(10).fill("twitch"), apps).error, "Pass 1 to 9 URLs or web apps")

// `live`: news on workspace 10, streams on workspace 1.
assert.deepEqual(plain(model.chooseWorkspace(live, screens, "news", "")), { workspace: 10 })
assert.deepEqual(plain(model.chooseWorkspace(live, screens, "fresh", "")), { workspace: 1 })
assert.deepEqual(plain(model.chooseWorkspace(live, screens, "news", "DP-4")), { workspace: 10 })
assert.deepEqual(plain(model.chooseWorkspace(live, screens, "fresh", "DP-9")), { error: 'Monitor "DP-9" is not active' })
assert.equal(model.chooseWorkspace(live, [], "fresh", "").error, "No active Hyprland monitors")
const floatingFirst = model.buildList([client("0x1", ["mosaic", "mosaic-x"], { floating: true, workspace: 7 }),
  client("0x2", ["mosaic", "mosaic-x"], { workspace: 8 })], [], [])
assert.deepEqual(plain(model.chooseWorkspace(floatingFirst, screens, "x", "")), { workspace: 8 })

assert.equal(model.desktopId("brave-origin.desktop\n"), "brave-origin")
assert.equal(model.desktopId(""), "")
assert.equal(model.isChromiumFamily("brave-origin"), true)
assert.equal(model.isChromiumFamily("google-chrome"), true)
assert.equal(model.isChromiumFamily("firefox"), false)
assert.equal(model.isAppWindow("brave-youtube.com__-Default"), true)
assert.equal(model.isAppWindow("brave-origin"), false)
assert.deepEqual(plain(model.parseOpenWindow("5f4ccef35180,10,brave-youtube.com__-Default,YouTube, the site")),
  { address: "0x5f4ccef35180", windowClass: "brave-youtube.com__-Default" })
assert.equal(model.parseOpenWindow("zz,1,a__b,t"), null)
assert.equal(model.parseOpenWindow("5f4c"), null)

assert.deepEqual(plain(model.tileDispatches("0x1a", "streams", 4)), {
  tags: ['hl.dsp.window.tag({ window = "address:0x1a", tag = "+mosaic" })',
    'hl.dsp.window.tag({ window = "address:0x1a", tag = "+mosaic-streams" })'],
  place: ['hl.dsp.window.move({ window = "address:0x1a", workspace = "4", follow = false })',
    'hl.dsp.window.float({ window = "address:0x1a", action = "disable" })',
    'hl.dsp.window.set_prop({ window = "address:0x1a", prop = "opaque", value = "1" })',
    'hl.dsp.window.fullscreen_state({ internal = 0, client = 2, window = "address:0x1a" })']
})
assert.equal(model.tileDispatches("0x1a", 'x" })', 4).error.startsWith("Invalid session name"), true)
assert.equal(model.tileDispatches("0x1a", "", 4).error.startsWith("Invalid session name"), true)
assert.equal(model.tileDispatches("zz", "x", 4).error.startsWith("Unexpected Hyprland window address"), true)
assert.equal(model.tileDispatches("0x1a", "x", "4").error.startsWith("Unexpected workspace"), true)

// Ported from session::tests::prunes_records_for_closed_windows.
const record = address => ({ address, session: "x", url: "" })
assert.deepEqual(plain(model.pruneRecords([record("0xa"), record("0xb"), record("0xc")],
  [client("0xa", ["mosaic", "mosaic-x"]), client("0xb", [])]).map(r => r.address)), ["0xa"])
// Written the way the Rust CLI writes it, so either can read the other's file.
assert.equal(model.serializeStore([{ address: "0x5f4ccef35180", session: "default", url: "https://youtube.com/" }]),
  '{\n  "tiles": [\n    {\n      "address": "0x5f4ccef35180",\n      "session": "default",\n      "url": "https://youtube.com/"\n    }\n  ]\n}')
assert.equal(model.serializeStore([]), '{\n  "tiles": []\n}')

// Replacing: `live` has 0x1 (news, workspace 10), 0x2 and 0x3 (streams, workspace 1).
const old = model.planReplace(live, "2").tile
assert.deepEqual(plain(old), { session: "streams", index: 2, address: "0x2", state: "contained", workspace: 1, url: "https://www.twitch.tv/somechannel/" })
assert.equal(model.planReplace(live, "0x3").tile.index, 3)
assert.equal(model.planReplace(live, "9").error, 'No mosaic tile "9"; see `mosaic list`')
assert.equal(model.planReplace(model.buildList([client("0x8", ["mosaic"], { fullscreen: 1 })], [], []), "0x8").error,
  "Leave fullscreen on that tile before replacing it")
assert.deepEqual(plain(model.tileDispatches("0x1b", "streams", 1, old).place), [
  'hl.dsp.window.move({ window = "address:0x1b", workspace = "1", follow = false })',
  'hl.dsp.window.float({ window = "address:0x1b", action = "disable" })',
  'hl.dsp.window.set_prop({ window = "address:0x1b", prop = "opaque", value = "1" })',
  'hl.dsp.window.swap({ window = "address:0x1b", target = "address:0x2" })',
  'hl.dsp.window.close({ window = "address:0x2" })',
  'hl.dsp.window.fullscreen_state({ internal = 0, client = 2, window = "address:0x1b" })'])
// A floating tile has no slot to swap into.
assert.deepEqual(plain(model.tileDispatches("0x1b", "x", 1, { address: "0x2", state: "floating" }).place.slice(3)), [
  'hl.dsp.window.close({ window = "address:0x2" })',
  'hl.dsp.window.fullscreen_state({ internal = 0, client = 2, window = "address:0x1b" })'])
assert.equal(model.tileDispatches("0x1b", "x", 1, { address: '0x2" })', state: "contained" }).error.startsWith("Unexpected Hyprland window address"), true)
assert.equal(model.tileDispatches("0x1b", "x", 1, { address: "0x1b", state: "contained" }).error.startsWith("Unexpected Hyprland window address"), true)
const rec = (address, url) => ({ address, session: "s", url })
assert.deepEqual(plain(model.replaceRecord([rec("0x1", "a"), rec("0x2", "b"), rec("0x3", "c")], "0x2", rec("0x9", "z")).map(r => r.address)), ["0x1", "0x9", "0x3"])
assert.deepEqual(plain(model.replaceRecord([rec("0x1", "a")], "0x7", rec("0x9", "z")).map(r => r.address)), ["0x1", "0x9"])

assert.deepEqual(plain(model.parseCursorPos("2536, 791\n")), { x: 2536, y: 791 })
assert.deepEqual(plain(model.parseCursorPos("-20, 5.6")), { x: -20, y: 6 })
assert.equal(model.parseCursorPos("error"), null)
assert.equal(model.parseCursorPos("1, 2) os.exit("), null)
assert.equal(model.cursorMoveExpression({ x: 2536, y: 791 }), "hl.dsp.cursor.move({ x = 2536, y = 791 })")
assert.equal(model.cursorMoveExpression(null), "")
assert.equal(model.cursorMoveExpression({ x: "1) os.exit(", y: 2 }), "")
assert.equal(model.cursorMoveExpression({ x: 1.5, y: 2 }), "")

assert.deepEqual(plain(model.parseKeySpec(" super + shift + s ")), { spec: "SUPER + SHIFT + S", modmask: 65, key: "S" })
assert.deepEqual(plain(model.parseKeySpec("SUPER+ALT+F12")), { spec: "SUPER + ALT + F12", modmask: 72, key: "F12" })
assert.deepEqual(plain(model.parseKeySpec("CTRL + code:39")), { spec: "CTRL + code:39", modmask: 4, key: "code:39" })
assert.deepEqual(plain(model.parseKeySpec("")), { spec: "", modmask: 0, key: "" })
assert.equal(model.parseKeySpec("HYPER + S"), null)
assert.equal(model.parseKeySpec('SUPER + S") os.exit("'), null)
assert.equal(model.parseKeySpec("SUPER + "), null)
const binds = JSON.stringify([
  { modmask: 72, key: "S", submap: "", description: "Move window to scratchpad" },
  { modmask: 65, key: "s", submap: "", description: "Mosaic: swap the focused tile's web app" },
  { modmask: 64, key: "M", submap: "resize", description: "In a submap" }
])
assert.equal(model.bindConflict(binds, model.parseKeySpec("SUPER + ALT + S")), "Move window to scratchpad")
assert.equal(model.bindConflict(binds, model.parseKeySpec("SUPER + SHIFT + S")), "")
assert.equal(model.bindConflict(binds, model.parseKeySpec("SUPER + M")), "")
assert.equal(model.bindConflict("oops", model.parseKeySpec("SUPER + ALT + S")), "")
assert.equal(model.swapBindLua("SUPER + SHIFT + S"),
  'hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("omarchy-shell pym.mosaic swap"), { description = "Mosaic: swap the focused tile\'s web app" })')
assert.equal(model.unbindLua("SUPER + SHIFT + S"), 'hl.unbind("SUPER + SHIFT + S")')

// monitorsJson: DP-4 (id 1) at 0,0 and DP-5 (id 0) at 1920,0.
const clientsJson = JSON.stringify([{ address: "0x1", monitor: 0, at: [1932, 38], size: [1005, 544] }, { address: "0x2", monitor: 1, at: [12, 1173], size: [1056, 735] }])
assert.deepEqual(plain(model.tileRect(clientsJson, monitorsJson, "0x1")), { monitor: "DP-5", x: 12, y: 38, width: 1005, height: 544 })
assert.deepEqual(plain(model.tileRect(clientsJson, monitorsJson, "0x2")), { monitor: "DP-4", x: 12, y: 1173, width: 1056, height: 735 })
assert.equal(model.tileRect(clientsJson, monitorsJson, "0x9"), null)
assert.equal(model.tileRect("nope", monitorsJson, "0x1"), null)

// Written the way the Rust CLI prints them.
assert.equal(model.listText(live), [
  "news",
  "   1  DP-4:10  https://www.bbc.com/news",
  "streams",
  "   2  DP-5:1  https://www.twitch.tv/somechannel/",
  "   3  DP-5:1  Kick  (uncontained)"
].join("\n"))
assert.equal(model.listText({ version: 1, sessions: [] }), "No mosaic tiles are open.")
assert.equal(model.webappsText({ version: 1, webapps: [{ name: "Kick", url: "https://kick.com" }, { name: "YouTube", url: "https://youtube.com/" }] }),
  "Kick     https://kick.com\nYouTube  https://youtube.com/")
assert.equal(model.webappsText({ version: 1, webapps: [] }), "No web apps are installed.")
assert.equal(model.monitorsText(screens), [
  "  DP-4: 1920x1080 logical, work area 1920x1080 at 0,0",
  "* DP-5: 2048x1152 logical, work area 2048x1126 at 1920,26"
].join("\n"))
assert.deepEqual(plain(model.splitLines(" twitch \n\nTeam Chat\n")), ["twitch", "Team Chat"])
assert.deepEqual(plain(model.splitLines("")), [])

// The browser extension.
assert.deepEqual(plain(model.parseBridgeMessage('{"type":"hello","extension":"0.1.0"}')), { type: "hello", extension: "0.1.0" })
assert.equal(model.parseBridgeMessage("[1]"), null)
assert.equal(model.parseBridgeMessage('{"id":1}'), null)
assert.equal(model.parseBridgeMessage("nope"), null)
assert.equal(model.browserLabel("/opt/brave-origin-bin/brave"), "Brave Origin")
assert.equal(model.browserLabel("/opt/brave-bin/brave"), "Brave")
assert.equal(model.browserLabel("/usr/lib/chromium/chromium"), "Chromium")
assert.equal(model.browserLabel("chrome-flags.conf"), "Google Chrome")
assert.equal(model.browserLabel("/usr/bin/odd"), "odd")
assert.equal(model.browserLabel(""), "the browser")
assert.deepEqual(plain(model.bridgeWindows([
  { id: 1, type: "app", focused: true, tabs: [{ id: 2, url: "https://twitch.tv/a", title: "a", audible: true, muted: false }, { url: "x" }] },
  { id: "3", tabs: [] }, null
])), [{ id: 1, type: "app", focused: true, tabs: [{ id: 2, url: "https://twitch.tv/a", title: "a", favIconUrl: "", audible: true, muted: false, volume: 1 }] }])
assert.equal(model.bridgeWindows([{ id: 1, tabs: [{ id: 2, volume: 0.25 }, { id: 3, volume: 7 }] }])[0].tabs.map(tab => tab.volume).join(), "0.25,1")
assert.deepEqual(plain(model.bridgeWindows("nope")), [])

const extensionTiles = [
  { address: "0xa", url: "https://twitch.tv", title: "(4) chan - Twitch", index: 1 },
  { address: "0xb", url: "https://www.youtube.com/", title: "Old title", index: 2 },
  { address: "0xc", url: "https://kick.com", title: "Kick", index: 3 }
]
const tab = (id, url, title) => ({ id, type: "app", focused: false, tabs: [{ id: id + 100, url, title, audible: false, muted: false }] })
const matched = model.matchTiles(extensionTiles, [
  { windows: [tab(1, "https://www.twitch.tv/chan", "(4) chan - Twitch"), tab(2, "https://youtube.com/watch?v=1", "New title")] },
  { windows: [{ id: 3, type: "app", focused: false, tabs: [] }] }
])
assert.deepEqual(plain(matched), {
  total: 3, matched: 2,
  tiles: { "0xa": { bridge: 0, window: 1, tab: 101 }, "0xb": { bridge: 0, window: 2, tab: 102 } },
  missing: ["kick.com"]
})
// Two windows with one title fall back to the site, and a site shared by
// two leftover windows matches nothing.
const twins = model.matchTiles(
  [{ address: "0xa", url: "https://twitch.tv/a", title: "Twitch", index: 1 }, { address: "0xb", url: "https://kick.com", title: "Twitch", index: 2 }],
  [{ windows: [tab(1, "https://twitch.tv/a", "Twitch"), tab(2, "https://kick.com/b", "Twitch")] }])
assert.deepEqual(plain(twins.tiles), { "0xa": { bridge: 0, window: 1, tab: 101 }, "0xb": { bridge: 0, window: 2, tab: 102 } })
assert.equal(model.matchTiles([extensionTiles[0]], [{ windows: [tab(1, "https://twitch.tv/x", "x"), tab(2, "https://twitch.tv/y", "y")] }]).matched, 0)
// Two tiles on one site after a swap in place: each keeps its earlier tab,
// which neither title nor site could tell apart.
const sameSite = [{ address: "0xa", url: "https://youtube.com", title: "YouTube", index: 1 }, { address: "0xb", url: "https://youtube.com/", title: "YouTube", index: 2 }]
const sameTabs = [{ windows: [tab(1, "https://youtube.com/", "YouTube"), tab(2, "https://youtube.com/", "YouTube")] }]
assert.equal(model.matchTiles(sameSite, sameTabs).matched, 0)
assert.deepEqual(plain(model.matchTiles(sameSite, sameTabs, { "0xa": { bridge: 0, window: 2, tab: 102 }, "0xb": { bridge: 0, window: 1, tab: 101 } }).tiles),
  { "0xa": { bridge: 0, window: 2, tab: 102 }, "0xb": { bridge: 0, window: 1, tab: 101 } })
// Focus tells look-alikes apart: only the focused tile, and only on its site.
const focusTabs = [{ windows: [tab(1, "https://kick.com/", "Kick"), Object.assign(tab(2, "https://kick.com/", "Kick"), { focused: true })] }]
const kicks = [{ address: "0xa", url: "https://kick.com", title: "Kick", index: 1 }, { address: "0xb", url: "https://kick.com", title: "Kick", index: 2 }]
assert.deepEqual(plain(model.matchTiles(kicks, focusTabs, null, "0xb").tiles), { "0xb": { bridge: 0, window: 2, tab: 102 } })
assert.equal(model.matchTiles(kicks, focusTabs, null, "0xother").matched, 0)
assert.equal(model.matchTiles([{ address: "0xa", url: "https://twitch.tv", title: "Kick", index: 1 }, kicks[1]], focusTabs, null, "0xa").tiles["0xa"], undefined)
// A tab that is gone, or now another bridge's, is matched afresh.
assert.deepEqual(plain(model.matchTiles([extensionTiles[0]], [{ windows: [tab(1, "https://www.twitch.tv/chan", "(4) chan - Twitch")] }], { "0xa": { bridge: 1, window: 1, tab: 101 } }).tiles),
  { "0xa": { bridge: 0, window: 1, tab: 101 } })

// Saved pairings are updated by a check, and dropped with their tiles.
assert.deepEqual(plain(model.keepTabs({ "0xa": { bridge: 0, window: 1, tab: 101 }, "0xgone": { bridge: 0, window: 9, tab: 109 } },
  { tiles: { "0xb": { bridge: 0, window: 2, tab: 102 } } }, ["0xa", "0xb"])),
  { "0xa": { bridge: 0, window: 1, tab: 101 }, "0xb": { bridge: 0, window: 2, tab: 102 } })
assert.deepEqual(plain(model.keepTabs({ "0xa": { bridge: 0, window: 1, tab: 101 } }, { tiles: { "0xa": { bridge: 0, window: 3, tab: 103 } } }, ["0xa"])),
  { "0xa": { bridge: 0, window: 3, tab: 103 } })
assert.deepEqual(plain(model.keepTabs({ "0xa": { bridge: "x", tab: 1 } }, null, ["0xa"])), {})

const navBridges = [{ windows: [tab(1, "https://kick.com/", "Kick")] }]
assert.equal(model.tileTab({ tiles: { "0xa": { bridge: 0, window: 1, tab: 101 } } }, navBridges, "0xa").title, "Kick")
assert.equal(model.tileTab({ tiles: {} }, navBridges, "0xa"), null)
assert.equal(model.tileTab(null, navBridges, "0xa"), null)
assert.equal(model.navigationSettled({ url: "https://kick.com/", title: "Kick" }, "https://kick.com", "YouTube"), true)
// Still on the old site, still the old title, or only the address as title.
assert.equal(model.navigationSettled({ url: "https://youtube.com/", title: "Kick" }, "https://kick.com", "YouTube"), false)
assert.equal(model.navigationSettled({ url: "https://kick.com/", title: "YouTube" }, "https://kick.com", "YouTube"), false)
assert.equal(model.navigationSettled({ url: "https://kick.com/", title: "kick.com" }, "https://kick.com", "YouTube"), false)
assert.equal(model.navigationSettled(null, "https://kick.com", "YouTube"), false)

const setupOff = { browsers: [{ name: "Brave Origin", registered: false }, { name: "Chromium", registered: false }], flags: [{ file: "/h/.config/brave-origin-flags.conf", loaded: false }] }
const setupOn = { browsers: [{ name: "Brave Origin", registered: true }, { name: "Chromium", registered: true }], flags: [{ file: "/h/.config/brave-origin-flags.conf", loaded: true }, { file: "/h/.config/chromium-flags.conf", loaded: true }] }
const bridge = { browser: "/opt/brave-origin-bin/brave", extension: "0.1.0", windows: [] }
assert.equal(model.extensionState(null, []), "unknown")
assert.equal(model.extensionState(setupOff, []), "off")
assert.equal(model.extensionState(setupOn, []), "restart")
assert.equal(model.extensionState(null, [bridge]), "connected")
assert.equal(model.extensionNotice(setupOn, []), "Set up. Restart Brave Origin and Chromium to load the extension, then verify. Closing the browser also closes its tiles.")
assert.equal(model.extensionNotice(setupOn, [bridge]), "Connected to Brave Origin. Your tiles are checked whenever they change; V checks that it still answers.")
assert.equal(model.extensionNotice({ browsers: [], flags: [] }, []).includes("load it by hand"), true)
assert.deepEqual(plain(model.extensionSteps(setupOff, [], null)), [
  { label: "Bridge registered", done: false, detail: "Enable registers it with Brave Origin and Chromium" },
  { label: "Loads when the browser starts", done: false, detail: "Enable adds it to brave-origin-flags.conf" },
  { label: "Connected", done: false, detail: "Restart the browser after enabling" },
  { label: "Finds your tiles", done: false, detail: "Checked on its own once connected" }
])
assert.deepEqual(plain(model.extensionSteps(setupOn, [bridge], matched).map(step => [step.done, step.detail])), [
  [true, "Brave Origin and Chromium"],
  [true, "brave-origin-flags.conf and chromium-flags.conf"],
  [true, "Brave Origin · extension 0.1.0"],
  [false, "2 of 3 tiles  ·  not found: kick.com"]
])
assert.equal(model.extensionSteps(setupOn, [bridge], null)[3].detail, "Checking…")
assert.equal(model.extensionSteps(setupOn, [bridge], { total: 1, matched: 1, tiles: {}, missing: [] })[3].done, true)
assert.equal(model.extensionSteps(setupOn, [], { error: "No browser extension answered" })[3].detail, "No browser extension answered")
const many = { browsers: ["A", "B", "C", "D", "E"].map(name => ({ name, registered: true })), flags: [] }
assert.equal(model.extensionSteps(many, [], null)[0].detail, "A, B and 3 more")
assert.equal(model.extensionSteps(null, [], null)[0].detail, "No Chromium-family browser profile found")

assert.equal(model.browserClass("brave-origin.desktop"), "brave-origin")
assert.equal(model.browserClass("/home/u/.local/bin/brave-origin"), "brave-origin")
assert.equal(model.browserClass(""), "")
assert.deepEqual(plain(model.browserPids(JSON.stringify([
  { pid: 62992, class: "brave-twitch.tv__-Default", tags: ["mosaic", "mosaic-default"] },
  { pid: 62992, class: "brave-origin", tags: [] },
  { pid: 700, class: "chromium", tags: [] },
  { pid: 12, class: "foot", tags: [] },
  { pid: 1, class: "brave-origin", tags: [] },
  { pid: "9", class: "brave-origin", tags: ["mosaic"] }
]), ["brave-origin", "chromium"])), [700, 62992])
assert.deepEqual(plain(model.browserPids("[]", ["brave-origin"])), [])
assert.equal(model.browserPids("nope", []), null)

const audioBridges = [{ windows: [
  { id: 1, type: "app", focused: false, tabs: [{ id: 101, url: "", title: "", audible: true, muted: false, volume: 1 }] },
  { id: 2, type: "app", focused: false, tabs: [{ id: 102, url: "", title: "", audible: false, muted: true, volume: 0.5 }] }
] }]
const audioCheck = { total: 3, matched: 2, tiles: { "0xa": { bridge: 0, window: 1, tab: 101 }, "0xb": { bridge: 0, window: 2, tab: 102 }, "0xc": { bridge: 3, window: 9, tab: 9 } }, missing: [] }
const audio = model.tileAudio(audioCheck, audioBridges)
assert.deepEqual(plain(audio), {
  "0xa": { bridge: 0, tab: 101, audible: true, muted: false, volume: 1 },
  "0xb": { bridge: 0, tab: 102, audible: false, muted: true, volume: 0.5 }
})
assert.deepEqual(plain(model.tileAudio(null, audioBridges)), {})
assert.deepEqual(plain(model.focusMutes(audio, "0xb")), [{ bridge: 0, tab: 101, muted: true }, { bridge: 0, tab: 102, muted: false }])
assert.deepEqual(plain(model.focusMutes(audio, "0xa")), [])
assert.deepEqual(plain(model.focusMutes(audio, "0xz")), [])
assert.equal(model.audioIcon({ audible: true, muted: false }), "󰕾")
assert.equal(model.audioIcon({ audible: true, muted: true }), "󰖁")
assert.equal(model.audioIcon({ audible: false, muted: false }), "󰕿")
assert.equal(model.audioIcon(undefined), "")

assert.deepEqual(plain(model.extensionFromManifest('{"version":"0.2.0","background":{"service_worker":"background-2.js"}}')), { version: "0.2.0", script: "background-2.js" })
assert.equal(model.extensionFromManifest('{"version":"0.2.0"}'), null)
assert.equal(model.extensionFromManifest("nope"), null)
assert.equal(model.bridgeHas({ script: "background-2.js" }, "mute"), true)
assert.equal(model.bridgeHas({ script: "background-2.js" }, "volume"), false)
assert.equal(model.bridgeHas({ script: "" }, "mute"), false)
assert.equal(model.bridgeHas({ script: "background-3.js", features: ["mute", "volume"] }, "volume"), true)
assert.equal(model.bridgeHas({ script: "background-3.js", features: ["mute"] }, "media"), false)
assert.equal(model.stepVolume(1, -0.1), 0.9)
assert.equal(model.stepVolume(0.05, -0.1), 0)
assert.equal(model.stepVolume(0.97, 0.1), 1)
assert.equal(model.parseVolume("40", 1), 0.4)
assert.equal(model.parseVolume("40%", 1), 0.4)
assert.equal(model.parseVolume("+10", 0.5), 0.6)
assert.equal(model.parseVolume("-80", 0.5), 0)
assert.equal(model.parseVolume("250", 0.5), 1)
assert.equal(model.parseVolume("loud", 0.5), null)
assert.equal(model.audioIcon({ audible: true, muted: false, volume: 0.3 }), "󰖀")

// Layouts. `live`: streams (0x2 contained, 0x3 uncontained) on workspace
// 1, news (0x1 contained) on workspace 10.
{
  const three = { name: "Three", tree: { split: "row", sizes: [25, 50, 25], children: [{}, {}, {}] }, main: 2 }
  const custom = { three }
  assert.deepEqual(plain(model.layoutChoices(custom)), ["default", "grid", "stack", "main", "fit", "custom:three"])
  assert.equal(model.nextLayout("fit", custom), "custom:three")
  assert.equal(model.nextLayout("custom:three", custom), "default")
  assert.equal(model.layoutLabel("main", custom), "Main + small")
  assert.equal(model.layoutLabel("custom:three", custom), "Three")
  assert.equal(model.layoutLabel("custom:gone", custom), "Missing layout")
  assert.equal(model.parseLayoutName(" Grid ", custom), "grid")
  assert.equal(model.parseLayoutName("16:9", custom), "fit")
  assert.equal(model.parseLayoutName("off", custom), "default")
  assert.equal(model.parseLayoutName("THREE", custom), "custom:three")
  assert.equal(model.parseLayoutName("spiral", custom), "")
  assert.equal(model.hyprLayoutName("grid"), "lua:mosaic-grid")
  assert.equal(model.hyprLayoutName("custom:three"), "lua:mosaic-c-three")
  assert.equal(model.hyprLayoutName("custom:Bad Name"), "")
  assert.equal(model.hyprLayoutName("dwindle"), "dwindle")
  assert.equal(model.layoutSlug("  My Streams! 2 "), "my-streams-2")

  // Definitions: trees, and the earlier template form read as one.
  assert.deepEqual(plain(model.normalizeCustom({ name: " Three ", template: "columns", sizes: [25, 50, 25], main: 2 })), three)
  assert.deepEqual(plain(model.normalizeCustom({ name: "g", template: "grid", cols: 2, rows: 1 })).tree, { split: "row", sizes: [50, 50], children: [{}, {}] })
  assert.equal(model.normalizeCustom({ name: "x", tree: { split: "row", sizes: [50, 40], children: [{}, {}] } }), null)
  assert.equal(model.normalizeCustom({ name: "x", tree: { split: "row", sizes: [97, 3], children: [{}, {}] } }), null)
  assert.equal(model.normalizeCustom({ name: "x", tree: { split: "diagonal", sizes: [50, 50], children: [{}, {}] } }), null)
  assert.equal(model.normalizeCustom({ name: "!!", tree: {} }), null)
  assert.deepEqual(plain(model.normalizeCustom({ name: "one", tree: { split: "row", sizes: [100], children: [{}] }, main: 3 })), { name: "one", tree: {}, main: 1 })
  const side = model.newCustom("Side", "side")
  assert.deepEqual(plain(model.visualZones(side)).map(z => [z.x, z.y, z.w, z.h, z.fill, z.path]),
    [[0, 0, 0.7, 1, 1, [0]], [0.7, 0, 0.3, 0.5, 2, [1, 0]], [0.7, 0.5, 0.3, 0.5, 3, [1, 1]]])
  assert.deepEqual(plain(model.visualZones(three)).map(z => [z.x, z.w, z.fill, z.main]), [[0, 0.25, 2, false], [0.25, 0.5, 1, true], [0.75, 0.25, 3, false]])
  assert.deepEqual(plain(model.visualZones(model.newCustom("g", "grid"))).map(z => z.fill), [1, 2, 3, 4])
  assert.equal(model.defineLua("three", three),
    'MosaicLayouts.define("three", { { x = 0.25, y = 0, w = 0.5, h = 1 }, { x = 0, y = 0, w = 0.25, h = 1 }, { x = 0.75, y = 0, w = 0.25, h = 1 } })')
  assert.equal(model.defineLua('x") os.exit() --', three), "")
  assert.deepEqual(plain(model.zoneDividers(side)), [
    { path: [], index: 0, vertical: true, x: 0.7, y: 0, length: 1, from: 0, span: 1 },
    { path: [1], index: 0, vertical: false, x: 0.7, y: 0.5, length: 0.3, from: 0, span: 1 }])

  // Editing.
  assert.deepEqual(plain(model.withDivider(three, [], 0, 0.4, 0, 1).tree.sizes), [40, 35, 25])
  assert.deepEqual(plain(model.withDivider(three, [], 1, 0.99, 0, 1).tree.sizes), [25, 70, 5])
  assert.deepEqual(plain(model.withDivider(side, [1], 0, 0.8, 0, 1).tree.children[1].sizes), [80, 20])
  // Splitting beside in a row adds a sibling; below nests a split.
  const beside = model.withSplit(three, 0, "row")
  assert.deepEqual(plain(beside.tree.sizes), [13, 12, 50, 25])
  assert.equal(beside.main, 3)
  const below = model.withSplit(three, 1, "column")
  assert.deepEqual(plain(below.tree.children[1]), { split: "column", sizes: [50, 50], children: [{}, {}] })
  assert.equal(below.main, 2)
  assert.deepEqual(plain(model.withSplit({ name: "o", tree: {}, main: 1 }, 0, "row").tree), { split: "row", sizes: [50, 50], children: [{}, {}] })
  // Removing gives the share to the neighbour and collapses one-zone splits.
  assert.deepEqual(plain(model.withoutZone(three, 0)), { name: "Three", tree: { split: "row", sizes: [75, 25], children: [{}, {}] }, main: 1 })
  assert.deepEqual(plain(model.withoutZone(side, 2)), { name: "Side", tree: { split: "row", sizes: [70, 30], children: [{}, {}] }, main: 1 })
  assert.deepEqual(plain(model.withoutZone(model.withoutZone(three, 0), 0).tree), {})
  assert.equal(model.withoutZone({ name: "o", tree: {}, main: 1 }, 0).tree.split, undefined)
  assert.deepEqual(plain(model.withZoneSize(three, 1, 10).tree.sizes), [25, 60, 15])
  assert.deepEqual(plain(model.withZoneSize(three, 2, 10).tree.sizes), [25, 40, 35])
  assert.deepEqual(plain(model.withZoneSize(three, 0, -30).tree.sizes), [5, 70, 25])
  assert.equal(model.withMain(three, 0).main, 1)
  assert.equal(model.zoneCount(side), 3)
  assert.deepEqual([1, 2, 3, 4, 11, 12, 22].map(model.ordinal), ["1st", "2nd", "3rd", "4th", "11th", "12th", "22nd"])
  assert.equal(model.customSummary(three), "3 zones  ·  main 50%")

  // The file: version 2, and version 1's sessions as legacy.
  const text = model.serializeLayouts({ workspaces: { "10": { layout: "custom:three", before: "dwindle" }, "8": { layout: "grid", before: "" } }, custom })
  assert.deepEqual(plain(model.parseLayouts(text)), { workspaces: { "8": { layout: "grid", before: "" }, "10": { layout: "custom:three", before: "dwindle" } }, custom, legacy: {} })
  assert.deepEqual(plain(model.parseLayouts('{"version":2,"workspaces":{"0":{"layout":"grid"},"x":{"layout":"grid"},"3":{"layout":"custom:gone"},"4":{"layout":"fit","before":"a\\"b"}},'
    + '"custom":{"Bad":' + JSON.stringify(three) + ',"ok":{"name":"Ok","tree":{"split":"row","sizes":[60,50],"children":[{},{}]}}}}')),
    { workspaces: { "4": { layout: "fit", before: "" } }, custom: {}, legacy: {} })
  assert.deepEqual(plain(model.parseLayouts('{"version":1,"sessions":{"streams":{"layout":"stack","before":"dwindle"},"x":{"layout":"spiral"}}}')).legacy,
    { streams: { layout: "stack", before: "dwindle" } })
  assert.deepEqual(plain(model.parseLayouts("oops")), { workspaces: {}, custom: {}, legacy: {} })

  // Lua text.
  assert.equal(model.layoutsLoadLua("/home/u/omarchy-mosaic/layouts.lua"), 'dofile("/home/u/omarchy-mosaic/layouts.lua")')
  assert.equal(model.layoutsLoadLua('/home/u/x") os.exit() --.lua'), "")
  assert.equal(model.layoutsLoaded("ok\n"), true)
  assert.equal(model.layoutsLoaded("error: x.lua:130: hl.layout.register: layout 'lua:mosaic-grid' is already registered\n"), true)
  assert.equal(model.layoutsLoaded("error: x.lua:3: syntax error"), false)
  assert.equal(model.layoutsLoaded(""), false)
  assert.equal(model.layoutRuleLua(9, "grid"), 'hl.workspace_rule({ workspace = "9", layout = "lua:mosaic-grid" })')
  assert.equal(model.layoutRuleLua("9", "dwindle"), 'hl.workspace_rule({ workspace = "9", layout = "dwindle" })')
  assert.equal(model.layoutRuleLua(-98, "grid"), "")
  assert.equal(model.layoutRuleLua(9, 'x" })'), "")
  assert.equal(model.sessionWorkspace(live, "news"), 10)
  assert.equal(model.sessionWorkspace(live, "gone"), null)
  assert.deepEqual(plain(model.tileStates(live)), { "0x1": "contained", "0x2": "contained", "0x3": "uncontained" })

  // Plans.
  const load = 'dofile("/p/layouts.lua")'
  const containOn = address => model.dispatchExpression("contain", address)
  const empty = { workspaces: {}, custom, legacy: {} }
  const set = model.planWorkspaceLayout(live, empty, 1, "grid", "dwindle", load)
  assert.deepEqual(plain(set), {
    state: { workspaces: { "1": { layout: "grid", before: "dwindle" } }, custom, legacy: {} },
    expressions: [{ eval: load }, { eval: model.layoutRuleLua(1, "grid") }, containOn("0x2"), model.dispatchExpression("release", "0x3")],
    message: "Workspace 1: Grid." })
  // A custom choice defines its zones first; `before` stays from the first
  // change; default puts it back.
  const onCustom = model.planWorkspaceLayout(live, set.state, 1, "three", "lua:mosaic-grid", load)
  assert.deepEqual(plain(onCustom.state.workspaces), { "1": { layout: "custom:three", before: "dwindle" } })
  assert.deepEqual(plain(onCustom.expressions.slice(0, 3)), [{ eval: load }, { eval: model.defineLua("three", three) }, { eval: model.layoutRuleLua(1, "custom:three") }])
  const back = model.planWorkspaceLayout(live, onCustom.state, 1, "default", "lua:mosaic-grid", load)
  assert.deepEqual(plain(back.state.workspaces), {})
  assert.deepEqual(plain(back.expressions[1]), { eval: model.layoutRuleLua(1, "dwindle") })
  assert.equal(model.planWorkspaceLayout(live, empty, 1, "grid", "lua:mosaicprobe", load).state.workspaces["1"].before, "")
  assert.equal(model.planWorkspaceLayout(live, empty, 8, "grid", "", load).expressions.length, 2)
  assert.equal(model.planWorkspaceLayout(live, empty, 1, "spiral", "dwindle", load).error.startsWith("Unknown layout"), true)
  assert.equal(model.planWorkspaceLayout(live, empty, "x", "grid", "dwindle", load).error.startsWith("Unexpected workspace"), true)
  assert.equal(model.planWorkspaceLayout(live, empty, 1, "grid", "dwindle", "").error.startsWith("Cannot load"), true)

  // Sync: every custom layout defined, every workspace set, containment
  // from before a reload; legacy session layouts move to their workspaces.
  const saved = { workspaces: { "10": { layout: "custom:three", before: "" } }, custom, legacy: { streams: { layout: "stack", before: "dwindle" }, gone: { layout: "grid", before: "" } } }
  const sync = model.planSyncLayouts(live, saved, load, { "0x3": "contained" })
  assert.deepEqual(plain(sync.state.workspaces), { "1": { layout: "stack", before: "dwindle" }, "10": { layout: "custom:three", before: "" } })
  assert.deepEqual(plain(sync.expressions), [{ eval: load }, { eval: model.defineLua("three", three) },
    { eval: model.layoutRuleLua(1, "stack") }, containOn("0x2"), containOn("0x3"),
    { eval: model.layoutRuleLua(10, "custom:three") }, containOn("0x1")])
  assert.deepEqual(plain(model.planSyncLayouts(live, { workspaces: {}, custom: {}, legacy: {} }, load).expressions), [])

  // Saving: a new layout is defined; editing one in use lays its
  // workspaces out again (switching away first); renaming moves them.
  const saveNew = model.planSaveCustom(live, empty, "", { name: "Two", tree: { split: "column", sizes: [70, 30], children: [{}, {}] }, main: 1 }, load)
  assert.equal(saveNew.slug, "two")
  assert.deepEqual(plain(saveNew.expressions.map(e => e.eval.slice(0, 20))), [load.slice(0, 20), 'MosaicLayouts.define'])
  const inUse = { workspaces: { "10": { layout: "custom:three", before: "" } }, custom, legacy: {} }
  const edit = model.planSaveCustom(live, inUse, "three", model.withZoneSize(three, 1, 10), load)
  assert.deepEqual(plain(edit.expressions.slice(2)), [{ eval: model.layoutRuleLua(10, "dwindle") }, { eval: model.layoutRuleLua(10, "custom:three") }, containOn("0x1")])
  const renamed = model.planSaveCustom(live, inUse, "three", model.withName(three, "Wide"), load)
  assert.deepEqual(plain(renamed.state), { workspaces: { "10": { layout: "custom:wide", before: "" } }, custom: { wide: plain(model.withName(three, "Wide")) }, legacy: {} })
  assert.equal(renamed.expressions.length, 4)
  assert.equal(model.planSaveCustom(live, { workspaces: {}, custom: { three, two: saveNew.state.custom.two }, legacy: {} }, "two", model.withName(three, "three"), load).error, "There is already a layout called Three")
  assert.equal(model.planSaveCustom(live, empty, "", { name: "", tree: {} }, load).error.startsWith("Give the layout a name"), true)
  // Deleting hands its workspaces back.
  const deleted = model.planDeleteCustom(live, { workspaces: { "10": { layout: "custom:three", before: "master" } }, custom, legacy: {} }, "three", load)
  assert.deepEqual(plain(deleted.state), { workspaces: {}, custom: {}, legacy: {} })
  assert.deepEqual(plain(deleted.expressions), [{ eval: load }, { eval: model.layoutRuleLua(10, "master") }, containOn("0x1")])
  assert.equal(model.planDeleteCustom(live, empty, "gone", load).error, 'No custom layout "gone"')

  const rows = model.layoutWorkspaceRows([{ id: 3, monitor: "DP-5", windows: 2 }, { id: -98, monitor: "DP-5", windows: 1 }, { id: 1, monitor: "DP-4" }], inUse)
  assert.deepEqual(plain(rows),
    [{ id: 1, monitor: "DP-4", windows: 0, choice: "default" }, { id: 3, monitor: "DP-5", windows: 2, choice: "default" }, { id: 10, monitor: "", windows: 0, choice: "custom:three" }])
  // Empty workspaces with no layout of their own hide, unless asked for or
  // under the cursor.
  assert.deepEqual(plain(model.shownWorkspaceRows(rows, false, 0)).map(row => row.id), [3, 10])
  assert.deepEqual(plain(model.shownWorkspaceRows(rows, false, 1)).map(row => row.id), [1, 3, 10])
  assert.deepEqual(plain(model.shownWorkspaceRows(rows, true, 0)).map(row => row.id), [1, 3, 10])
  assert.deepEqual(plain(model.windowCounts([{ workspace: 3 }, { workspace: 3 }, { workspace: -98 }, { workspace: 1 }])), { 1: 1, 3: 2 })
  assert.deepEqual(plain(model.customRows({ b: { name: "beta" }, a: { name: "Zed" } })).map(row => row.slug), ["b", "a"])
  assert.equal(model.freeLayoutName({ "layout-1": three }), "Layout 2")
  assert.equal(model.workspaceChoice(inUse, 10), "custom:three")
  assert.equal(model.workspaceChoice(inUse, "8"), "default")
  assert.equal(model.layoutsText(inUse), "workspace 10  Three\n\nCustom layouts:\n  Three  (3 zones  ·  main 50%)")
  assert.equal(model.layoutsText({ workspaces: {}, custom: {} }), "No workspace has a Mosaic layout.")
}

// Volumes: a following extension's report wins unless the tile was just
// set; an older one gets the level again; gone tiles are dropped.
{
  const audio = { "0x1": { bridge: 0, volume: 0.1 }, "0x2": { bridge: 1, volume: 1 }, "0x3": { bridge: 0, volume: 0.5 } }
  const follows = index => index === 0
  const set = { "0x1": 0.8, "0x2": 0.4, "0x3": 0.5, "0x9": 0.2 }
  assert.deepEqual(plain(model.reconcileVolumes(set, audio, ["0x1", "0x2", "0x3"], follows, () => false)),
    { volumes: { "0x1": 0.1, "0x2": 0.4, "0x3": 0.5 }, resend: ["0x2"] })
  assert.deepEqual(plain(model.reconcileVolumes(set, audio, ["0x1"], follows, address => address === "0x1")),
    { volumes: { "0x1": 0.8 }, resend: [] })
}

console.log("model tests passed")

// The key bar: a few keys per context, the rest behind "?".
assert.deepEqual(plain(model.keyHints("tiles", false, 6)), [["↑↓", "select"], ["Enter", "focus"], ["S", "swap"], ["A", "add"], ["?", "more"]])
assert.equal(model.keyHints("tiles", true, 6).length, 15)
assert.deepEqual(plain(model.keyHints("swap", false, 12))[0], ["1–9", "web app"])
assert.deepEqual(plain(model.keyHints("adding", false, 0)), [["Enter", "add"], ["Esc", "close"]])
assert.deepEqual(plain(model.keyHints("extension", false, 3)), [["V", "verify"], ["H/L", "tabs"]])
assert.deepEqual(plain(model.keyHints("nonsense", false, 0)).at(-1), ["?", "more"])
