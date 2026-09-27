import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"

const source = fs.readFileSync(new URL("../Model.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*/m, "")
const model = {}
vm.runInNewContext(source + "\nObject.assign(model, { parseList, tileLabel, tileMeta, normalizeUrl, sessionName, summary, anyUncontained, errorLine });", { model })

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

console.log("model tests passed")
