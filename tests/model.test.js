import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"

const source = fs.readFileSync(new URL("../Model.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*/m, "")
const model = {}
vm.runInNewContext(source + "\nObject.assign(model, { hiddenEntries, showWebapp, nameList, visibleWebapps, hideWebapp, sessionOf, clientFromIpc, parseStore, tileState, buildList, shapeList, parseClients, validAddress, dispatchExpression, listTiles, findTile, planFocus, planRemove, planClose, planContain, restoreAfterMove, monitorFromIpc, parseMonitors, resolveAddTargets, chooseWorkspace, desktopId, isChromiumFamily, isAppWindow, parseOpenWindow, tileDispatches, pruneRecords, serializeStore, planReplace, replaceRecord, parseCursorPos, cursorMoveExpression, parseKeySpec, bindConflict, tileRect, swapBindLua, unbindLua, webappUrl, webappFromEntry, buildWebapps, shapeWebapps, findWebapp, resolveTarget, parseList, tileLabel, tileMeta, normalizeUrl, sessionName, summary, anyUncontained, parseManifest });", { model })

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
assert.equal(model.tileMeta(list.tiles[2]), "DP-5 · workspace 1  ·  fullscreen not contained")

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
assert.deepEqual(plain(model.clientFromIpc({ address: "0x5f4cce94d400", class: "foot", title: "odin", workspace: { id: 1, name: "1" },
  monitor: 0, tags: ["default-opacity*", "terminal*"], floating: false, fullscreen: 0, fullscreenClient: 0 })),
  { address: "0x5f4cce94d400", title: "odin", workspace: 1, monitor: 0, tags: ["default-opacity*", "terminal*"], floating: false, fullscreen: 0, fullscreenClient: 0 })
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

console.log("model tests passed")
