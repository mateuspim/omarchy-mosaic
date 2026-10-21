# `layouts.lua` and custom layouts

Mosaic's layouts are Hyprland Lua tiling layouts
([ADR 12](../adr/0012-layouts-as-hyprland-lua-tiling-layouts.md)). How to
use them is in the [layouts guide](../guide/layouts.md).

## Loading

The service loads the file into Hyprland's Lua state with
`hyprctl eval 'dofile("<plugin>/layouts.lua")'` (`Model.layoutsLoadLua`
refuses a path with characters it can't quote plainly) at start and after
every `configreloaded`. A reply of `ok`, or only "is already registered"
complaints, counts as loaded.

When `hl.layout` exists, loading sets three globals:

| Global | Holds |
| --- | --- |
| `MosaicLayouts` | The module table returned by the file; replaced on every load, so a reload of the file updates the code in place. |
| `MosaicCustom` | Custom zones by slug; kept across loads. |
| `MosaicRegistered` | Names already registered in this Lua state; Hyprland refuses a second registration and can't unregister one. |

It registers `mosaic-grid`, `mosaic-stack`, `mosaic-main` and `mosaic-fit`.
Each layout's `recalculate(ctx)` calls
`MosaicLayouts.arrange(name, ctx.area, #ctx.targets)` and places each target
in its box; Hyprland applies the gaps.

Without `hl` (plain `lua`, as in `tests/layouts_test.lua`), the file only
returns the module table.

## Module

| Function | Returns |
| --- | --- |
| `M.names` | `{ "grid", "stack", "main", "fit" }`, the cycle order. |
| `M.grid(area, n)` | A balanced grid: `ceil(sqrt(n))` per line, lines along the shorter side, a short last line stretched. |
| `M.stack(area, n)` | One row on a landscape area, one column on a portrait one. |
| `M.main(area, n)` | The first box takes `M.main_ratio` (0.7) of the long side; the rest share a line beside or below it. |
| `M.fit(area, n)` | The grid whose 16:9 (`M.aspect`) boxes come out largest, centered, with a short last row centered. |
| `M.zones(zones, area, n)` | Window `i` takes zone `i`; extra windows share the last zone, split along its longer side. No zones: a grid. |
| `M.arrange(name, area, n)` | `name` is a built-in name or a zones table; boxes rounded to whole pixels so neighbours meet without a seam. |
| `M.define(slug, zones)` | Stores a custom layout's zones in `MosaicCustom` and registers `mosaic-c-<slug>` the first time. |

`area` and every box are `{ x, y, w, h }` in pixels. Every arrangement
returns exactly `n` boxes inside the area without overlaps (tested for 0–9
windows on landscape and portrait areas).

## Choosing a layout

A workspace's layout is set with
`hl.workspace_rule({ workspace = "N", layout = "lua:mosaic-grid" })`
(`Model.layoutRuleLua`). The `lua:` prefix is required: an unknown name
silently falls back to dwindle. `default` puts back the workspace's layout
from before Mosaic changed it (`before` in
[`layouts.json`](files.md#layoutsjson-version-2)). A rule works before the
workspace exists. Setting the same rule again doesn't lay the workspace out
again; switching to dwindle and back does, which is how a saved custom
layout reaches workspaces that use it.

## Custom layouts

A custom layout is stored in `layouts.json` under its slug (lowercase
letters, digits, `-` and `_`, from its name) and validated by
`Model.normalizeCustom`:

```json
{ "name": "Three",
  "tree": { "split": "row", "sizes": [25, 50, 25], "children": [{}, {}, {}] },
  "main": 2 }
```

- `name`: up to 40 characters, with at least one letter, digit, `-` or `_`
  (its slug is the name lowercased with other runs turned into `-`, up to
  32 characters).
- `tree`: a zone is `{}`; a split is `{ "split": "row" | "column", "sizes",
  "children" }`, with whole-number `sizes` in percent (at least 5 each,
  adding up to 100), up to 6 children (a one-child split collapses into its
  child), at most 4 levels and 16 zones in all.
- `main`: the 1-based zone (depth first) that gets the first window; the
  others fill in visual order.
- The older form, `{ "template": "columns" | "rows", "sizes" }` or
  `{ "template": "grid", "cols", "rows" }` (1–4 each), is read as a tree.

The service turns the tree into zones in fill order, as fractions of the
area, and sends `MosaicLayouts.define("<slug>", { { x = …, y = …, w = …, h
= … }, … })` (`Model.defineLua`, which refuses a slug that is not a valid
session-style name).
