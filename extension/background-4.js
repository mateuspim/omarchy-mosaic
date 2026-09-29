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
//                       until the page's own controls change it, which
//                       the next windows report then shows
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
const SCRIPT = "background-4.js";
// "follow": reported volumes follow changes made with the page's own
// controls, and survive the worker stopping, so the service mirrors them
// instead of setting its own again.
const FEATURES = ["mute", "volume", "follow", "navigate", "reload", "media", "favicon"];
const HOST = "pym.mosaic";
const RETRY_FIRST_MS = 1000;
const RETRY_LAST_MS = 60000;

let port = null;
let retryMs = RETRY_FIRST_MS;
let retryTimer = null;
let windowsTimer = null;
// Each tab's volume, set by the service or with the page's own controls; a
// tab without one plays at the site's own. Kept in session storage, which
// outlives the worker (the browser stops it when idle) but not the browser.
const volumes = new Map();
const volumesReady = chrome.storage.session.get("volumes").then(function(stored) {
  const saved = stored && stored.volumes ? stored.volumes : {};
  Object.keys(saved).forEach(function(id) { volumes.set(Number(id), saved[id]); });
}).catch(function() {});

function setVolume(tabId, level) {
  if (level >= 1) volumes.delete(tabId);
  else volumes.set(tabId, level);
  chrome.storage.session.set({ volumes: Object.fromEntries(volumes) }).catch(function() {});
}

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
    setVolume(tab.id, level);
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
  await volumesReady;
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

// Sets the page's media to `level` (null: leave it as it is, only watch),
// and again whenever a media element loads or starts, since players reset
// their volume. At 1 it only sets it once, so the site's own volume keeps
// working. Last change wins: a change made with the page's own controls
// (right after the user clicked, dragged, scrolled, or typed in the page)
// becomes the tab's level and is reported; one a player makes on its own
// is undone at the next load or start.
function applyVolume(tabId, level) {
  return chrome.scripting.executeScript({ target: { tabId: tabId, allFrames: true }, func: pageVolume, args: [level] })
    .catch(function() { /* A page that can't take scripts, such as an error page. */ });
}

// Runs in the page (isolated world), so it shares the DOM but not the
// page's scripts.
function pageVolume(level) {
  const INPUT_MS = 1500;
  const state = globalThis.__mosaicVolume || (globalThis.__mosaicVolume = { level: 1, hooked: false, input: -Infinity });
  if (level !== null) state.level = level;
  function apply(element) {
    if (element instanceof HTMLMediaElement && Math.abs(element.volume - state.level) > 0.001) element.volume = state.level;
  }
  if (!state.hooked) {
    state.hooked = true;
    function touched(event) {
      if (event.isTrusted && (event.type !== "pointermove" || event.buttons !== 0)) state.input = performance.now();
    }
    ["pointerdown", "pointermove", "pointerup", "keydown", "wheel"].forEach(function(type) {
      window.addEventListener(type, touched, { capture: true, passive: true });
    });
    ["play", "loadeddata"].forEach(function(type) {
      document.addEventListener(type, function(event) { if (state.level < 1) apply(event.target); }, true);
    });
    document.addEventListener("volumechange", function(event) {
      const element = event.target;
      if (!(element instanceof HTMLMediaElement) || Math.abs(element.volume - state.level) <= 0.001) return;
      if (performance.now() - state.input > INPUT_MS) return;
      state.level = element.volume;
      try {
        chrome.runtime.sendMessage({ type: "pageVolume", level: element.volume }).catch(function() {});
      } catch (error) { /* The extension was updated or removed. */ }
    }, true);
  }
  if (level !== null) document.querySelectorAll("video, audio").forEach(apply);
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
  await volumesReady;
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

// A page's own volume controls, reported by pageVolume.
chrome.runtime.onMessage.addListener(function(message, sender) {
  if (!message || message.type !== "pageVolume" || !sender.tab) return;
  const level = Number(message.level);
  if (!Number.isFinite(level) || level < 0 || level > 1) return;
  const tabId = sender.tab.id;
  tileTab(tabId).then(async function() {
    await volumesReady;
    setVolume(tabId, Math.round(level * 100) / 100);
    windowsChanged();
  }).catch(function() {});
});

// Watches every tile's page, so its own volume controls are followed even
// before the service sets a volume, and sets the tile's level again on a
// new page, which starts at the site's volume.
async function watchPage(tabId) {
  try {
    await tileTab(tabId);
  } catch (error) {
    return;
  }
  await volumesReady;
  applyVolume(tabId, volumes.has(tabId) ? volumes.get(tabId) : null);
}

chrome.tabs.onUpdated.addListener(function(tabId, change) {
  if (change.status === "complete") watchPage(tabId);
  if ("title" in change || "url" in change || "audible" in change || "mutedInfo" in change || "favIconUrl" in change) windowsChanged();
});
chrome.tabs.onRemoved.addListener(function(tabId) {
  if (volumes.has(tabId)) setVolume(tabId, 1);
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
// Pages already open when the worker starts, as after an update.
chrome.windows.getAll({ populate: true, windowTypes: ["app", "popup"] }).then(function(all) {
  all.forEach(function(window) { (window.tabs || []).forEach(function(tab) { watchPage(tab.id); }); });
}).catch(function() {});
