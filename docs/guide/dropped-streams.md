# Dropped streams

Twitch sometimes drops a stream: the picture freezes or the player shows
an error such as "Error #3000", and only a page reload brings it back.
With the browser extension connected, **Recover dropped streams** at the
top of the Tiles tab (on by default, Shift+R) does that reload for you.
The extension watches each tile's video, and a tile counts as dropped
when its video fails, the site shows its player error, or a video that
was playing stands still for 12 seconds without being paused. A player
that gives up behind its spinner counts too: a video that was playing
and then ended or was paused, not by you, for 20 seconds, and a video
that never starts for 20 seconds, as after a reload that hangs. Pausing
by hand (a click or a key in the tile, or `mosaic` media commands) and
an ad playing in another video don't count. Media keys and playerctl
give the page no sign of a hand pause, so a tile paused that way is
reloaded after 20 seconds, at most three times.

A tile that was fullscreen goes fullscreen again once the stream plays:
Mosaic presses its f (the fullscreen key on Twitch, YouTube, and Kick),
which briefly focuses the tile, so it waits until the tile's workspace
is on screen, then hands focus and the cursor back.

It reloads a dropped tile right away, then waits 30 seconds and 2 minutes
before trying again. After three tries in ten minutes it stops and the
tile's row says **stream stalled**; P reloads it by hand. A tile's row
also says when a stream was recovered. It only acts on the sites in the
widget's **Stream recovery sites** setting, `twitch.tv, kick.com` by
default (YouTube doesn't need it). `mosaic streams` shows each tile's
stream and the recent recoveries with the reason, such as
`MEDIA_ERR_DECODE`; they are logged to the shell's journal too.

Recovery needs the [browser extension](browser-extension.md); see also [Audio](audio.md) for per-tile controls.
