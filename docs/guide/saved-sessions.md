# Saved sessions

Keep a session to open it again later: its tiles, in order, with the
monitor and workspace they were on, that workspace's layout, and each
tile's volume and mute. On the Tiles tab, the 󰆓 button on a session's
header (or **W** on one of its tiles) saves it under its own name, and
saving again updates it. The **Saved** tab lists saved sessions: **Enter**
opens the tiles that aren't open yet, back where they were (on the
focused monitor if that one is gone), **O** switches **Open at login** on
or off, and **D** (twice) deletes one. Saved sessions live in
`~/.local/state/mosaic/saved.json`. To open one with a key, bind
`mosaic restore NAME` in your Hyprland config.
