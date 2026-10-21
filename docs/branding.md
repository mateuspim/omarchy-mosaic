# Mosaic brand assets

The mark is the picture Mosaic makes: four tiles inside one frame, split by
a cross, the way a monitor holds several web apps side by side. Each tile is
a different shade of the same slate teal, so they read as separate windows
that still belong together. The frame and cross are thick on purpose: at
32 px the mark stays four distinct tiles, and at 16 px it reduces to a pale
square split into four. It is drawn as vector shapes on a dark rounded
field, so it also holds up on a light page.

The colours were sampled from the 2026-10-21 `preview.png` (the first hero,
made before this standard) and are kept as the brand colours:

| Colour | Hex | Use |
| --- | --- | --- |
| Slate teal (accent) | `#9cbec9` | Wordmark on dark, hero accents, chip icons, the sample theme's accent in the captures |
| Frame | `#9dbbc5` | Icon frame and cross |
| Tile 1 | `#a8c5ce` | Top-left tile |
| Tile 2 | `#83a8b4` | Top-right tile |
| Tile 3 | `#7899a7` | Bottom-left tile |
| Tile 4 | `#b9cbd0` | Bottom-right tile |
| Icon field | `#101a20` | Icon background, between the tiles |
| Deep teal | `#4f7f8f` | Wordmark on light surfaces; the hero's bottom-left glow |

The wordmark is the whole word **Mosaic**, in JetBrainsMono Nerd Font Bold,
in slate teal on dark surfaces or deep teal on light ones. Never "Omarchy
Mosaic" or "Mosaic for Omarchy" as a wordmark. The browser extension keeps
the name "Omarchy Mosaic", since that is how it shows on the browser's
extensions page and how the native host recognises older copies of it.

| Asset | Use |
| --- | --- |
| [`icon.svg`](../icon.svg) | Square app icon and README heading. |
| [`logo.svg`](brand/logo.svg) | Horizontal wordmark on a dark surface. |
| [`logo-light.svg`](brand/logo-light.svg) | Horizontal wordmark on a light surface. |
| [`preview.svg`](brand/preview.svg) | Editable README hero layout. |
| [`captures/`](brand/captures/) | Offscreen panel renders with sample tiles, placed by the hero. |
| [`preview.png`](../preview.png) | Rendered README hero at 3840 × 2160. |

The logo SVGs and the preview inline the mark so they render standalone; keep
the shapes in sync when changing the icon. Wordmarks use live SVG text, so the
font can vary where JetBrainsMono Nerd Font is not installed.

The hero's right half has two parts. The monitor, with workspace 8 in the
"Three" layout and the middle tile's video fullscreen inside its tile, is
drawn in the SVG. The two panels are real Quickshell renders of `Panel.qml`
(Tiles and Layouts tabs), made offscreen by `tests/preview.sh` with a fake
service and a sample theme whose accent is the slate teal; inside Omarchy the
panel follows the user's theme. The captures show site names and made-up
titles only: no real channels, accounts, paths or monitors beyond `DP-4` and
`DP-5`.

Keep clear space around the mark and the wordmark casing **Mosaic**. The
[development runbook](runbooks/development.md#refresh-the-preview) explains how
to re-render the hero from offscreen captures with fake data.
