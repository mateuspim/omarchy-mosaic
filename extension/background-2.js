// Omarchy Mosaic's browser side. It connects to the plugin's native host,
// `pym.mosaic` (bin/mosaic-native-host), which relays messages to and from
// the Mosaic service in the Omarchy shell, and it reports the browser's app
// windows, which is how the service finds its tiles in this browser.
//
// Messages are JSON objects with a `type`:
//   to the service:   hello { extension, script }, windows { id?, windows }
//   from the service: ping { id }, answered by windows { id, windows };
//                     and mute { tab, muted }, which mutes or unmutes a tab
//                     (the tab's change then arrives as windows).
// No reload message: after chrome.runtime.reload() the service worker isn't
// started again until something wakes it, so it would stay disconnected.
// A newer extension loads when the browser restarts.

// This file's own name. Brave kept running a cached copy of the old worker
// script after the extension's files changed, even across a restart, while
// reporting the new manifest's version; a new file name per change forces
// the new code (Omarchy's Copy URL extension does the same). Rename the file,
// update manifest.json, and change this together.
const SCRIPT = "background-2.js";
const HOST = "pym.mosaic";
const RETRY_FIRST_MS = 1000;
const RETRY_LAST_MS = 60000;

let port = null;
let retryMs = RETRY_FIRST_MS;
let retryTimer = null;
let windowsTimer = null;

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
  send({ type: "hello", extension: chrome.runtime.getManifest().version, script: SCRIPT });
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

function receive(message) {
  retryMs = RETRY_FIRST_MS;
  if (!message || typeof message !== "object") return;
  if (message.type === "ping") reportWindows(Number.isInteger(message.id) ? message.id : undefined);
  else if (message.type === "mute" && Number.isInteger(message.tab) && typeof message.muted === "boolean") mute(message.tab, message.muted);
}

// Only tabs in app windows, which are the tiles, are ever muted.
async function mute(tabId, muted) {
  try {
    const tab = await chrome.tabs.get(tabId);
    const window = await chrome.windows.get(tab.windowId);
    if (window.type !== "app" && window.type !== "popup") return;
    await chrome.tabs.update(tabId, { muted: muted });
  } catch (error) {
    // The tab closed meanwhile; the next windows report shows it gone.
  }
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
            audible: !!tab.audible,
            muted: !!(tab.mutedInfo && tab.mutedInfo.muted)
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
  if ("title" in change || "url" in change || "audible" in change || "mutedInfo" in change) windowsChanged();
});
chrome.tabs.onRemoved.addListener(windowsChanged);
chrome.windows.onCreated.addListener(windowsChanged);
chrome.windows.onRemoved.addListener(windowsChanged);

chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
chrome.alarms.create("mosaic-connect", { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener(function(alarm) {
  if (alarm.name === "mosaic-connect") connect();
});

connect();
