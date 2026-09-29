-- Omarchy Mosaic's tiling layouts, registered in Hyprland at runtime by the
-- service (`hyprctl eval 'dofile("…/layouts.lua")'`) and chosen per
-- workspace with `hl.workspace_rule({ layout = "lua:mosaic-grid" })`.
-- They are Hyprland tiled layouts, not floating geometry, so swaps and
-- Omarchy's bindings keep working. Hyprland applies the gaps.
--
-- Loaded as a plain file too (tests/layouts_test.lua), where `hl` is absent
-- and only the returned table is used.

local M = {}

-- The layout names, in the order the panel cycles them.
M.names = { "grid", "stack", "main", "fit" }

local function box(x, y, w, h)
  return { x = x, y = y, w = w, h = h }
end

-- Rows of a grid with `n` cells, as a list of cell counts: `cols` per row,
-- and whatever is left in the last one, so no cell is left empty.
local function rows_of(n, cols)
  local rows = {}
  local left = n
  while left > 0 do
    local count = math.min(cols, left)
    rows[#rows + 1] = count
    left = left - count
  end
  return rows
end

-- Cells laid out in rows (landscape) or columns (portrait), each line
-- stretched across the area.
local function lines(area, counts, vertical)
  local boxes = {}
  local lineCount = #counts
  for l, count in ipairs(counts) do
    for c = 1, count do
      if vertical then
        local w = area.w / lineCount
        local h = area.h / count
        boxes[#boxes + 1] = box(area.x + (l - 1) * w, area.y + (c - 1) * h, w, h)
      else
        local w = area.w / count
        local h = area.h / lineCount
        boxes[#boxes + 1] = box(area.x + (c - 1) * w, area.y + (l - 1) * h, w, h)
      end
    end
  end
  return boxes
end

-- Balanced grid: about as many columns as rows, with the longer side of
-- the area getting the extra ones. A short last line stretches its cells.
function M.grid(area, n)
  if n == 0 then return {} end
  local vertical = area.h > area.w
  local per = math.ceil(math.sqrt(n))
  return lines(area, rows_of(n, per), vertical)
end

-- Stack: one row on a landscape area, one column on a portrait one.
function M.stack(area, n)
  if n == 0 then return {} end
  return lines(area, { n }, area.h > area.w)
end

-- One large plus several small: the first tile takes `ratio` of the long
-- side, and the others share the rest in a line beside or below it.
M.main_ratio = 0.7

function M.main(area, n)
  if n <= 1 then return n == 1 and { box(area.x, area.y, area.w, area.h) } or {} end
  local boxes = {}
  if area.w >= area.h then
    local w = math.floor(area.w * M.main_ratio)
    boxes[1] = box(area.x, area.y, w, area.h)
    local rest = box(area.x + w, area.y, area.w - w, area.h)
    for _, cell in ipairs(lines(rest, { n - 1 }, true)) do boxes[#boxes + 1] = cell end
  else
    local h = math.floor(area.h * M.main_ratio)
    boxes[1] = box(area.x, area.y, area.w, h)
    local rest = box(area.x, area.y + h, area.w, area.h - h)
    for _, cell in ipairs(lines(rest, { n - 1 }, false)) do boxes[#boxes + 1] = cell end
  end
  return boxes
end

-- 16:9 fit: the grid whose 16:9 tiles come out largest, centered, with a
-- short last row centered too. The rest of the area stays empty.
M.aspect = 16 / 9

function M.fit(area, n)
  if n == 0 then return {} end
  local best
  for cols = 1, n do
    local rows = math.ceil(n / cols)
    local w = math.min(area.w / cols, area.h / rows * M.aspect)
    if not best or w > best.w + 0.5 then best = { cols = cols, rows = rows, w = w } end
  end
  local w = best.w
  local h = w / M.aspect
  local counts = rows_of(n, best.cols)
  local top = area.y + (area.h - #counts * h) / 2
  local boxes = {}
  for r, count in ipairs(counts) do
    local left = area.x + (area.w - count * w) / 2
    for c = 1, count do
      boxes[#boxes + 1] = box(left + (c - 1) * w, top + (r - 1) * h, w, h)
    end
  end
  return boxes
end

local function whole(b)
  local x = math.floor(b.x + 0.5)
  local y = math.floor(b.y + 0.5)
  return box(x, y, math.floor(b.x + b.w + 0.5) - x, math.floor(b.y + b.h + 0.5) - y)
end

-- Boxes in whole pixels, so neighbours meet without a seam.
function M.arrange(name, area, n)
  local boxes = M[name](area, n)
  for i, b in ipairs(boxes) do boxes[i] = whole(b) end
  return boxes
end

-- Hyprland refuses a name registered twice and has no way to unregister
-- one, so the names are registered once per config load (a reload starts
-- a fresh Lua state), and they call whatever code the last load left in
-- `MosaicLayouts`. Loading this file again updates the layouts in place.
if hl and hl.layout then
  local first = MosaicLayouts == nil
  MosaicLayouts = M
  if first then
    for _, name in ipairs(M.names) do
      hl.layout.register("mosaic-" .. name, {
        recalculate = function(ctx)
          local boxes = MosaicLayouts.arrange(name, ctx.area, #ctx.targets)
          for i, target in ipairs(ctx.targets) do target:place(boxes[i]) end
        end,
      })
    end
  end
end

return M
