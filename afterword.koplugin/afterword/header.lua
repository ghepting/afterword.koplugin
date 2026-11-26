-- The title bar of the What to read next list, in the style of ShelfSpace's: Afterword's mark on the left, the title in the middle, a
-- close button on the right. On a colour screen it is a band of the plugin's slate with the mark and title in white; on a grey one it
-- is plain, with a rule under it. Menu takes it as its `custom_title_bar`, so it answers the few calls Menu makes of a TitleBar.
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")

local Screen = Device.screen
local SLATE = Blitbuffer.colorFromString and Blitbuffer.colorFromString("#2a363b") or Blitbuffer.gray(0.25)

local function sp(n) return Screen:scaleBySize(n) end

-- Two books, one leaning on the other, on a shelf, with a play badge: the logo without its name, in `ink` on `bg` (hex, no '#'). The
-- label bands and the badge's triangle are painted in the background colour, since the header is a flat colour.
local function mark_svg(ink, bg)
    return table.concat {
        '<svg xmlns="http://www.w3.org/2000/svg" width="118" height="94" viewBox="38 58 118 94">',
        string.format('<rect x="48" y="66" width="30" height="68" rx="5.5" fill="#%s"/>', ink),
        string.format('<rect x="47" y="79" width="32" height="4.2" fill="#%s"/>', bg),
        -- the second book has a gap of the background colour around it, where it leans on the first
        string.format('<g transform="rotate(-12 82 134)"><rect x="82" y="74" width="30" height="60" rx="5" fill="#%s" stroke="#%s" stroke-width="7"/>', bg, bg),
        string.format('<rect x="82" y="74" width="30" height="60" rx="5.5" fill="#%s"/>', ink),
        string.format('<rect x="81" y="87" width="32" height="4.2" fill="#%s"/></g>', bg),
        string.format('<circle cx="134" cy="114" r="15.5" fill="#%s"/>', ink),
        string.format('<path d="M130.4 106.8 L141.6 114 L130.4 121.2 Z" fill="#%s" stroke="#%s" stroke-width="3.6" stroke-linejoin="round"/>', bg, bg),
        string.format('<rect x="41.6" y="140" width="108" height="9" rx="4.5" fill="#%s"/>', ink),
        '</svg>',
    }
end

local function mark_widget(width, ink, bg)
    local dir = DataStorage:getDataDir() .. "/cache/afterword"
    lfs.mkdir(DataStorage:getDataDir() .. "/cache")
    lfs.mkdir(dir)
    local path = string.format("%s/mark-%s-%s.svg", dir, ink, bg)
    local f = io.open(path, "w")
    if not f then return nil end
    f:write(mark_svg(ink, bg))
    f:close()
    return IconWidget:new { file = path, width = width, height = math.floor(width * 94 / 118), alpha = true }
end

-- A tappable box: calls `callback` on a tap anywhere in it.
local function tappable(widget, callback)
    local box = InputContainer:new { widget, ges_events = {} }
    box.ges_events.Tap = { GestureRange:new { ges = "tap", range = function() return box.dimen end } }
    function box:onTap() callback(); return true end
    return box
end

local Header = {}
Header.__index = Header

-- Header:new { title, width, on_close } -> a widget Menu can use as its title bar.
function Header:new(opts)
    local colour = Screen:isColorEnabled()
    local band = colour and SLATE or Blitbuffer.COLOR_WHITE
    local ink = colour and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    local width, h = opts.width, sp(46)
    local close_icon = colour and TextWidget:new { text = "\u{2715}", face = Font:getFace("tfont", 26), fgcolor = ink }
        or IconWidget:new { icon = "close", alpha = true, width = sp(26), height = sp(26) }
    local close = tappable(CenterContainer:new { dimen = Geom:new { w = sp(56), h = h }, close_icon }, opts.on_close)
    local mark = mark_widget(sp(44), colour and "ffffff" or "000000", colour and "2a363b" or "ffffff")
    local bar = FrameContainer:new {
        bordersize = 0, padding = 0, margin = 0, background = band,
        OverlapGroup:new {
            dimen = Geom:new { w = width, h = h },
            CenterContainer:new {
                dimen = Geom:new { w = width, h = h },
                TextWidget:new { text = opts.title, face = Font:getFace("tfont", 22), fgcolor = ink, max_width = width - 2 * sp(90), truncate_with_ellipsis = true },
            },
            LeftContainer:new {
                dimen = Geom:new { w = width, h = h },
                HorizontalGroup:new {
                    HorizontalSpan:new { width = sp(14) },
                    -- On a screen reached from another, a back arrow takes the mark's place; on the first, a tap on the mark opens its menu.
                    opts.on_back and tappable(CenterContainer:new { dimen = Geom:new { w = sp(56), h = h },
                        TextWidget:new { text = "\u{2190}", face = Font:getFace("tfont", 30), fgcolor = ink } }, opts.on_back)
                        or opts.on_mark and mark and tappable(mark, opts.on_mark) or mark or HorizontalSpan:new { width = 0 },
                },
            },
            RightContainer:new { dimen = Geom:new { w = width, h = h }, close },
        },
    }
    local self = setmetatable({}, Header)
    self.widget = VerticalGroup:new {
        align = "left", bar,
        colour and VerticalSpan:new { width = 0 }
            or LineWidget:new { dimen = Geom:new { w = width, h = Size.line.medium }, background = Blitbuffer.COLOR_BLACK },
    }
    self.dimen = Geom:new { w = width, h = self.widget:getSize().h }
    return self
end

-- What Menu calls on a title bar: it is a widget (size, painting, layout), with a title and icon it needs not change.
Header.tappable = tappable
-- The accent of the plugin's screens: the slate on colour, black on grey.
function Header.accent() return Screen:isColorEnabled() and SLATE or Blitbuffer.COLOR_BLACK end

function Header:getSize() return self.widget:getSize() end
function Header:getHeight() return self.widget:getSize().h end
function Header:paintTo(bb, x, y) self.dimen.x, self.dimen.y = x, y; self.widget:paintTo(bb, x, y) end
function Header:free() self.widget:free() end
function Header:handleEvent(event) return self.widget:handleEvent(event) end
function Header:generateVerticalLayout() return {} end
function Header:setTitle() end
function Header:setSubTitle() end
function Header:setLeftIcon() end

return Header
