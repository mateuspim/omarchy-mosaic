# Layouts

A layout belongs to a **workspace**: set workspace 8 to Grid and workspace
9 to one of your own, and whatever opens there, tiles or not, is laid out
that way. The panel's **Layouts** tab lists your workspaces, each with a dropdown of
layouts (Enter moves to the next one, 0 hands it back to Hyprland's own).
Each session header on the Tiles tab shows the layout of the workspace its
tiles are on, and its grid button (or **G** on a tile) switches it.

- **Grid**: a balanced grid; a short last row stretches across.
- **Stack**: one row on a landscape monitor, one column on a portrait one.
- **Main + small**: the first tile takes 70% of the monitor, the rest line
  up beside it (or below it, on a portrait monitor).
- **16:9 fit**: the largest 16:9 tiles that fit, centered.
- **Your own layouts**, below.
- **Hyprland**: the workspace's own layout again.

**Design your own** on the Layouts tab with **N** (or E on one to edit
it), by mouse or keyboard. Start from a preset (Columns, Rows, Grid, Main +
side; T cycles them), then shape it on the preview: drag the lines between
zones to resize them, and hover a zone for its buttons: split it beside or
below (S, B), make it the main zone (★, M), or remove it (×, X). ←/→ pick a
zone and −/+ resize it from the keyboard. The main zone gets the first
window, the others fill in order (the preview numbers them), and when
windows outnumber zones the extra ones share the last zone. The first
preset, Columns 25 / 50 / 25 with the middle one main, puts one tile in the
center and two small ones beside it. The toolbar under the preview does
the same for the selected zone, however small. For detailed layouts,
**Large** (F) opens the editor over the whole monitor, at its shape; Back
(Esc) returns to the panel with your changes. N names the layout, Enter
saves, Esc cancels, and D (twice) deletes one; workspaces using it get
their own layout back.

Tiles stay tiled, so Omarchy's window bindings (swapping included) keep
working. Mosaic saves the choices in `~/.local/state/mosaic/layouts.json`
and applies them again after a Hyprland config reload.
