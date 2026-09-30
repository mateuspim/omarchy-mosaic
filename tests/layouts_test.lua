-- Tests for layouts.lua: `lua tests/layouts_test.lua` from the repository.

local L = dofile("layouts.lua")

local failures = 0
local function check(name, condition)
  if not condition then
    failures = failures + 1
    print("FAIL " .. name)
  end
end

local function same(a, b)
  return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

-- Every box inside the area, and no two overlapping.
local function tidy(area, boxes)
  for i, a in ipairs(boxes) do
    if a.w <= 0 or a.h <= 0 or a.x < area.x or a.y < area.y
        or a.x + a.w > area.x + area.w or a.y + a.h > area.y + area.h then
      return false
    end
    for j = i + 1, #boxes do
      local b = boxes[j]
      if a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h then return false end
    end
  end
  return true
end

local landscape = { x = 0, y = 0, w = 2000, h = 1000 }
local portrait = { x = 10, y = 20, w = 1000, h = 2000 }

for _, name in ipairs(L.names) do
  for _, area in ipairs({ landscape, portrait }) do
    for n = 0, 9 do
      local boxes = L.arrange(name, area, n)
      check(name .. " gives one box per tile (" .. n .. ")", #boxes == n)
      check(name .. " stays inside the area without overlaps (" .. n .. ")", tidy(area, boxes))
    end
  end
  check(name .. " fills the area with one tile",
    name == "fit" or same(L.arrange(name, landscape, 1)[1], landscape))
end

-- Grid: 3 tiles on landscape are two on top and one wide below.
local g = L.arrange("grid", landscape, 3)
check("grid 3 top row", same(g[1], { x = 0, y = 0, w = 1000, h = 500 }) and same(g[2], { x = 1000, y = 0, w = 1000, h = 500 }))
check("grid 3 stretched last row", same(g[3], { x = 0, y = 500, w = 2000, h = 500 }))
-- On portrait, the lines are columns.
local gp = L.arrange("grid", portrait, 2)
check("grid 2 portrait stacks", same(gp[1], { x = 10, y = 20, w = 1000, h = 1000 }) and same(gp[2], { x = 10, y = 1020, w = 1000, h = 1000 }))

-- Stack: a row on landscape, a column on portrait.
local s = L.arrange("stack", landscape, 4)
check("stack landscape is a row", s[4].x == 1500 and s[4].h == 1000)
local sp = L.arrange("stack", portrait, 4)
check("stack portrait is a column", sp[4].y == 1520 and sp[4].w == 1000)

-- Main: the first tile gets 70% of the long side.
local m = L.arrange("main", landscape, 3)
check("main big tile", same(m[1], { x = 0, y = 0, w = 1400, h = 1000 }))
check("main small tiles", same(m[2], { x = 1400, y = 0, w = 600, h = 500 }) and same(m[3], { x = 1400, y = 500, w = 600, h = 500 }))
local mp = L.arrange("main", portrait, 3)
check("main portrait big tile on top", same(mp[1], { x = 10, y = 20, w = 1000, h = 1400 }))

-- Fit: tiles are 16:9 and centered.
local f = L.arrange("fit", { x = 0, y = 0, w = 1920, h = 1080 }, 1)
check("fit one tile fills a 16:9 area", same(f[1], { x = 0, y = 0, w = 1920, h = 1080 }))
local f4 = L.arrange("fit", { x = 0, y = 0, w = 1920, h = 1080 }, 4)
check("fit four is 2x2", same(f4[4], { x = 960, y = 540, w = 960, h = 540 }))
local f3 = L.arrange("fit", portrait, 3)
check("fit portrait stacks 16:9 tiles", f3[1].w == 1000 and f3[1].h == 563 and f3[1].x == 10)
check("fit portrait centers vertically", f3[1].y > 20)

-- Custom zones: 25/50/25 columns with the middle one filled first.
local three = { { x = 0.25, y = 0, w = 0.5, h = 1 }, { x = 0, y = 0, w = 0.25, h = 1 }, { x = 0.75, y = 0, w = 0.25, h = 1 } }
local c1 = L.arrange(three, landscape, 1)
check("custom one window takes the main zone", #c1 == 1 and same(c1[1], { x = 500, y = 0, w = 1000, h = 1000 }))
local c3 = L.arrange(three, landscape, 3)
check("custom three windows fill all zones", same(c3[2], { x = 0, y = 0, w = 500, h = 1000 }) and same(c3[3], { x = 1500, y = 0, w = 500, h = 1000 }))
local c5 = L.arrange(three, landscape, 5)
check("custom extra windows share the last zone", #c5 == 5 and same(c5[3], { x = 1500, y = 0, w = 500, h = 333 }) and same(c5[5], { x = 1500, y = 667, w = 500, h = 333 }))
check("custom stays tidy", tidy(landscape, c5) and tidy(portrait, L.arrange(three, portrait, 7)))
check("no zones is a grid", #L.arrange({}, landscape, 4) == 4)

-- Registration, with a stand-in for Hyprland's `hl`: each name once, even
-- across loads, and custom zones changed in place.
local registered = {}
hl = { layout = { register = function(name, provider)
  registered[#registered + 1] = name
  registered[name] = provider
end } }
dofile("layouts.lua")
dofile("layouts.lua")
MosaicLayouts.define("three", three)
MosaicLayouts.define("three", { { x = 0, y = 0, w = 1, h = 1 } })
check("each name registered once", #registered == 5 and registered[5] == "mosaic-c-three")
local placed = {}
local ctx = { area = landscape, targets = {} }
for i = 1, 2 do ctx.targets[i] = { place = function(_, b) placed[i] = b end } end
registered["mosaic-c-three"].recalculate(ctx)
check("custom provider uses the latest zones", same(placed[1], { x = 0, y = 0, w = 1000, h = 1000 }))
hl, MosaicLayouts, MosaicCustom, MosaicRegistered = nil, nil, nil, nil

if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("layouts: all passed")
