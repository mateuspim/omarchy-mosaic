// Evaluates JavaScript in a browser tab through the Chrome DevTools protocol,
// as if from a user gesture, so fullscreen can be requested without clicking.
//
// The browser must run with --remote-debugging-port. Use a throwaway profile,
// never the everyday one, for example with this --browser wrapper:
//   #!/bin/sh
//   exec brave --user-data-dir=/tmp/mosaic-probe-profile \
//     --remote-debugging-port=9333 --no-first-run --disable-sync "$@"
//
// Usage: node examples/cdp-eval.mjs URL_SUBSTRING INDEX EXPRESSION
//   node examples/cdp-eval.mjs fullscreen-test.html 0 \
//     'video.requestFullscreen().then(() => new Promise(r => setTimeout(r, 1500)))
//        .then(() => document.fullscreenElement?.tagName + " " + innerWidth + "x" + innerHeight)'
// Requires Node 22 or newer for the global WebSocket.

const [match, index, expression] = process.argv.slice(2);
if (!expression) {
  console.error("Usage: node cdp-eval.mjs URL_SUBSTRING INDEX EXPRESSION");
  process.exit(2);
}
const port = process.env.CDP_PORT ?? "9333";
const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
const pages = targets.filter((target) => target.type === "page" && target.url.includes(match));
const page = pages[Number(index)];
if (!page) {
  console.error(`No tab #${index} matching ${match}; found ${pages.length}`);
  process.exit(1);
}
const socket = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve) => socket.addEventListener("open", resolve));
socket.addEventListener("message", (event) => {
  const reply = JSON.parse(event.data);
  if (reply.id !== 1) return;
  const result = reply.result?.result;
  console.log(reply.result?.exceptionDetails ? `error: ${result?.description}` : result?.value);
  socket.close();
});
socket.send(JSON.stringify({
  id: 1,
  method: "Runtime.evaluate",
  params: { expression, userGesture: true, awaitPromise: true, returnByValue: true },
}));
