-- Omarchy Mosaic's tiling layouts, registered in Hyprland at runtime by the
-- service (`hyprctl eval 'dofile("…/layouts.lua")'`) and chosen per
-- workspace with `hl.workspace_rule({ layout = "lua:mosaic-grid" })`.
-- They are Hyprland tiled layouts, not floating geometry, so swaps and
-- Omarchy's bindings keep working. Hyprland applies the gaps.
--
-- Custom layouts, designed on the panel's Layouts tab, are zones: boxes in
-- fractions of the area, in the order windows fill them (the main zone
-- first). The service sends them with `MosaicLayouts.define(slug, zones)`,
-- which registers `mosaic-c-<slug>`.
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

-- A custom layout: window i takes zone i, and when windows outnumber
-- zones, the extra ones share the last zone with its own window, split
-- along its longer side. Without zones, a balanced grid.
function M.zones(zones, area, n)
  if not zones or #zones == 0 then return M.grid(area, n) end
  local boxes = {}
  if n == 0 then return boxes end
  local function scaled(z)
    return box(area.x + z.x * area.w, area.y + z.y * area.h, z.w * area.w, z.h * area.h)
  end
  local own = math.min(n, #zones)
  for i = 1, own - 1 do boxes[i] = scaled(zones[i]) end
  local last = scaled(zones[own])
  for _, cell in ipairs(lines(last, { n - own + 1 }, last.h > last.w)) do boxes[#boxes + 1] = cell end
  return boxes
end

-- Boxes in whole pixels, so neighbours meet without a seam. `name` is a
-- built-in layout, or a table of zones.
function M.arrange(name, area, n)
  local boxes = type(name) == "table" and M.zones(name, area, n) or M[name](area, n)
  for i, b in ipairs(boxes) do boxes[i] = whole(b) end
  return boxes
end

-- Hyprland refuses a name registered twice and has no way to unregister
-- one, so each name is registered once per config load (a reload starts a
-- fresh Lua state), and calls whatever code the last load left in
-- `MosaicLayouts`. Loading this file again updates the layouts in place.
-- Custom zones live in `MosaicCustom`, which a load keeps.
local function register(name, pick)
  if MosaicRegistered[name] then return end
  hl.layout.register(name, {
    recalculate = function(ctx)
      local boxes = MosaicLayouts.arrange(pick(), ctx.area, #ctx.targets)
      for i, target in ipairs(ctx.targets) do target:place(boxes[i]) end
    end,
  })
  MosaicRegistered[name] = true
end

-- Sets a custom layout's zones, registering its name the first time.
function M.define(slug, zones)
  MosaicCustom[slug] = zones
  register("mosaic-c-" .. slug, function() return MosaicCustom[slug] or "grid" end)
end

-- A load from before MosaicRegistered existed makes the first register
-- here complain "already registered", which the service accepts.
if hl and hl.layout then
  MosaicLayouts = M
  MosaicCustom = MosaicCustom or {}
  MosaicRegistered = MosaicRegistered or {}
  for _, name in ipairs(M.names) do
    register("mosaic-" .. name, function() return name end)
  end
end

return M
