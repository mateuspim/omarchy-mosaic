import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"

const source = fs.readFileSync(new URL("../Model.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*/m, "")
const model = {}
vm.runInNewContext(source + "\nObject.assign(model, { hiddenEntries, showWebapp, nameList, visibleWebapps, hideWebapp, sessionOf, clientFromIpc, parseStore, tileState, buildList, shapeList, parseWebapps, findWebapp, resolveTarget, parseList, tileLabel, tileMeta, normalizeUrl, sessionName, summary, anyUncontained, errorLine });", { model })

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

const webapps = model.parseWebapps(JSON.stringify({ version: 1, webapps: [
  { id: "Twitch", name: "Twitch", url: "https://twitch.tv", icon: "twitch" },
  { id: "chat", name: "Team Chat", url: "https://chat.example", icon: "/icons/chat.png" },
  { id: "broken", name: "No URL" }
] }))
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
assert.equal(model.parseWebapps("error").apps.length, 0)
assert.equal(model.parseWebapps('{"version":9,"webapps":[]}').error.includes("not supported"), true)

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

console.log("model tests passed")
