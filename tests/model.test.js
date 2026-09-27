import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"

const source = fs.readFileSync(new URL("../Model.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*/m, "")
const model = {}
vm.runInNewContext(source + "\nObject.assign(model, { hiddenEntries, showWebapp, nameList, visibleWebapps, hideWebapp, sessionOf, clientFromIpc, parseStore, tileState, buildList, shapeList, parseClients, validAddress, dispatchExpression, listTiles, findTile, planFocus, planRemove, planClose, planContain, webappUrl, webappFromEntry, buildWebapps, shapeWebapps, findWebapp, resolveTarget, parseList, tileLabel, tileMeta, normalizeUrl, sessionName, summary, anyUncontained, errorLine });", { model })

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

assert.equal(model.errorLine("mosaic: Monitor \"X\" is not active\n", "failed"), "Monitor \"X\" is not active")
assert.equal(model.errorLine("mosaic: bad\nRun `mosaic --help` for usage.\n", "failed"), "bad")
assert.equal(model.errorLine("", "failed"), "failed")

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

console.log("model tests passed")
