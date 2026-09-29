// Omarchy Mosaic's browser side. It connects to the plugin's native host,
// `pym.mosaic` (bin/mosaic-native-host), which relays messages to and from
// the Mosaic service in the Omarchy shell, and it reports the browser's app
// windows, which is how the service finds its tiles in this browser.
//
// Messages are JSON objects with a `type`:
//   to the service:   hello { extension, script, features }
//                     windows { id?, windows }: the app windows, their tabs'
//                       url, title, favIcon, audible, muted, and volume
//                     done { id, error }: how a command with an `id` went
//   from the service: ping { id }, answered by windows { id, windows }
//                     mute { tab, muted }
//                     volume { tab, level }: 0 to 1, kept on the tab's media
//                     navigate { tab, url }: an http(s) address, in place
//                     reload { tab }
//                     media { tab, action }: "play", "pause", or "toggle"
// Commands may carry an `id`, answered by `done`. A command's effect on the
// tab arrives with the next windows report. Commands only ever touch tabs
// in app windows, which are the tiles.
//
// Each browser restart costs the user their tiles, so this worker carries
// everything the plugin is expected to need, and `features` tells the
// service what this copy can do.
//
// No reload message: after chrome.runtime.reload() the service worker isn't
// started again until something wakes it, so it would stay disconnected.
// A newer extension loads when the browser restarts.

// This file's own name. Brave kept running a cached copy of the old worker
// script after the extension's files changed, even across a restart, while
// reporting the new manifest's version; a new file name per change forces
// the new code (Omarchy's Copy URL extension does the same). Rename the file,
// update manifest.json, and change this together.
const SCRIPT = "background-3.js";
const FEATURES = ["mute", "volume", "navigate", "reload", "media", "favicon"];
const HOST = "pym.mosaic";
const RETRY_FIRST_MS = 1000;
const RETRY_LAST_MS = 60000;

let port = null;
let retryMs = RETRY_FIRST_MS;
let retryTimer = null;
let windowsTimer = null;
// The volume set on each tab; a tab without one plays at the site's own.
// Lost if the browser stops the worker, and the service sets it again when
// a report shows it missing.
const volumes = new Map();

function connect() {
  if (port) return;
  clearTimeout(retryTimer);
  retryTimer = null;
  try {
    port = chrome.runtime.connectNative(HOST);
  } catch (error) {
    port = null;
    scheduleRetry();
    return;
  }
  port.onMessage.addListener(receive);
  port.onDisconnect.addListener(function() {
    // Reading lastError keeps "host not found" out of the error console.
    void chrome.runtime.lastError;
    port = null;
    scheduleRetry();
  });
  send({ type: "hello", extension: chrome.runtime.getManifest().version, script: SCRIPT, features: FEATURES });
  reportWindows();
}

// A missing host fails at once, so back off; the alarm below brings the
// worker back if the browser stopped it meanwhile.
function scheduleRetry() {
  if (retryTimer) return;
  retryTimer = setTimeout(connect, retryMs);
  retryMs = Math.min(retryMs * 2, RETRY_LAST_MS);
}

function send(message) {
  if (!port) return;
  try {
    port.postMessage(message);
  } catch (error) {
    port = null;
    scheduleRetry();
  }
}

const COMMANDS = {
  mute: function(tab, message) {
    if (typeof message.muted !== "boolean") throw new Error("muted must be true or false");
    return chrome.tabs.update(tab.id, { muted: message.muted });
  },
  volume: async function(tab, message) {
    const level = Number(message.level);
    if (!Number.isFinite(level) || level < 0 || level > 1) throw new Error("level must be from 0 to 1");
    if (level === 1) volumes.delete(tab.id);
    else volumes.set(tab.id, level);
    await applyVolume(tab.id, level);
    windowsChanged();
  },
  navigate: function(tab, message) {
    const url = String(message.url || "");
    if (!/^https?:\/\//i.test(url)) throw new Error("only http and https addresses");
    return chrome.tabs.update(tab.id, { url: url });
  },
  reload: function(tab) {
    return chrome.tabs.reload(tab.id);
  },
  media: function(tab, message) {
    if (["play", "pause", "toggle"].indexOf(message.action) === -1) throw new Error("action must be play, pause, or toggle");
    return chrome.scripting.executeScript({ target: { tabId: tab.id, allFrames: true }, func: pageMedia, args: [message.action] });
  }
};

async function receive(message) {
  retryMs = RETRY_FIRST_MS;
  if (!message || typeof message !== "object") return;
  if (message.type === "ping") return reportWindows(Number.isInteger(message.id) ? message.id : undefined);
  const command = COMMANDS[message.type];
  if (!command) return;
  let error = "";
  try {
    const tab = await tileTab(message.tab);
    await command(tab, message);
  } catch (failure) {
    error = String(failure && failure.message ? failure.message : failure);
  }
  if (message.id !== undefined) send({ type: "done", id: message.id, error: error });
}

// The tab, if it is in an app window; anything else is refused.
async function tileTab(tabId) {
  if (!Number.isInteger(tabId)) throw new Error("no tab given");
  const tab = await chrome.tabs.get(tabId);
  const window = await chrome.windows.get(tab.windowId);
  if (window.type !== "app" && window.type !== "popup") throw new Error("not a tile");
  return tab;
}

// Sets the page's media to `level` now, and again whenever a media element
// loads or starts, since players reset their volume. At 1 it only sets it
// once, so the site's own volume control keeps working.
function applyVolume(tabId, level) {
  return chrome.scripting.executeScript({ target: { tabId: tabId, allFrames: true }, func: pageVolume, args: [level] })
    .catch(function() { /* A page that can't take scripts, such as an error page. */ });
}

// Runs in the page (isolated world), so it shares the DOM but not the
// page's scripts.
function pageVolume(level) {
  const state = globalThis.__mosaicVolume || (globalThis.__mosaicVolume = { level: 1, hooked: false });
  state.level = level;
  function apply(element) {
    if (element instanceof HTMLMediaElement && Math.abs(element.volume - state.level) > 0.001) element.volume = state.level;
  }
  if (!state.hooked) {
    state.hooked = true;
    ["play", "loadeddata"].forEach(function(type) {
      document.addEventListener(type, function(event) { if (state.level < 1) apply(event.target); }, true);
    });
  }
  document.querySelectorAll("video, audio").forEach(apply);
}

function pageMedia(action) {
  document.querySelectorAll("video, audio").forEach(function(element) {
    if (action === "play" || (action === "toggle" && element.paused)) element.play().catch(function() {});
    else element.pause();
  });
}

// App windows only: tiles are `--app` windows, and the user's normal
// browsing windows are none of Mosaic's business.
async function reportWindows(id) {
  let windows = [];
  try {
    const all = await chrome.windows.getAll({ populate: true, windowTypes: ["app", "popup"] });
    windows = all.map(function(window) {
      return {
        id: window.id,
        type: window.type,
        focused: window.focused,
        tabs: (window.tabs || []).map(function(tab) {
          return {
            id: tab.id,
            url: tab.url || "",
            title: tab.title || "",
            favIconUrl: tab.favIconUrl || "",
            audible: !!tab.audible,
            muted: !!(tab.mutedInfo && tab.mutedInfo.muted),
            volume: volumes.has(tab.id) ? volumes.get(tab.id) : 1
          };
        })
      };
    });
  } catch (error) {
    windows = [];
  }
  const message = { type: "windows", windows: windows };
  if (id !== undefined) message.id = id;
  send(message);
}

// Titles, audio, and windows change in bursts; report once they settle.
function windowsChanged() {
  clearTimeout(windowsTimer);
  windowsTimer = setTimeout(function() { reportWindows(); }, 250);
}

chrome.tabs.onUpdated.addListener(function(tabId, change) {
  // A new page starts at the site's volume; set the tile's again.
  if (change.status === "complete" && volumes.has(tabId)) applyVolume(tabId, volumes.get(tabId));
  if ("title" in change || "url" in change || "audible" in change || "mutedInfo" in change || "favIconUrl" in change) windowsChanged();
});
chrome.tabs.onRemoved.addListener(function(tabId) {
  volumes.delete(tabId);
  windowsChanged();
});
chrome.windows.onCreated.addListener(windowsChanged);
chrome.windows.onRemoved.addListener(windowsChanged);

chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
chrome.alarms.create("mosaic-connect", { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener(function(alarm) {
  if (alarm.name === "mosaic-connect") connect();
});

connect();
