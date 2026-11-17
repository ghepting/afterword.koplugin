-- The screen shown at the end of a book: the book, how it went, a place to rate it, and what to read next.
-- A plain KOReader widget, built from the stock pieces so it looks like the rest of KOReader and works on any screen.
--
--   Screen:new{ title, author, series_text, cover (a blitbuffer or nil), lines = { { label, value } ... }, rating (0-5),
--               on_rate = function(n), next_title, on_next = function(), on_done = function() }
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local Screen = Device.screen

local AfterwordScreen = InputContainer:extend {
    name = "afterword_screen",
    title = nil, author = nil, series_text = nil, cover = nil,
    lines = nil, rating = 0, on_rate = nil,
    next_title = nil, on_next = nil, on_done = nil,
}

local STAR_ON, STAR_OFF = "\u{2605}", "\u{2606}" -- filled and outline stars

function AfterwordScreen:init()
    self.dimen = Geom:new { w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
    if Device:isTouchDevice() then
        self.ges_events.TapOutside = { GestureRange:new { ges = "tap", range = self.dimen } }
    end

    local width = math.floor(Screen:getWidth() * 0.88)
    local pad = Size.padding.large
    local inner = width - 2 * pad - 2 * Size.border.window
    local face = function(size, bold) return Font:getFace(bold and "x_smalltfont" or "cfont", size) end

    local group = VerticalGroup:new { align = "left" }

    -- The header: the book (cover, title, author, series) side by side.
    local head = HorizontalGroup:new { align = "top" }
    local text_w = inner
    if self.cover then
        local cover = ImageWidget:new { image = self.cover, image_disposable = true,
            width = Screen:scaleBySize(86), height = Screen:scaleBySize(124), scale_factor = 0 }
        local cw = cover:getSize().w
        head[#head + 1] = FrameContainer:new { bordersize = Size.border.thin, padding = 0, margin = 0, cover }
        head[#head + 1] = HorizontalSpan:new { width = Screen:scaleBySize(14) }
        text_w = inner - cw - Screen:scaleBySize(14) - 2 * Size.border.thin
    end
    local texts = VerticalGroup:new { align = "left" }
    texts[#texts + 1] = TextBoxWidget:new { text = self.title or "?", face = Font:getFace("tfont", 22), bold = true, width = text_w }
    if self.author and self.author ~= "" then
        texts[#texts + 1] = VerticalSpan:new { width = Screen:scaleBySize(2) }
        texts[#texts + 1] = TextBoxWidget:new { text = self.author, face = face(17), width = text_w }
    end
    if self.series_text then
        texts[#texts + 1] = VerticalSpan:new { width = Screen:scaleBySize(8) }
        texts[#texts + 1] = FrameContainer:new {
            bordersize = Size.border.thin, radius = Size.radius.window, padding = Screen:scaleBySize(3),
            padding_left = Screen:scaleBySize(8), padding_right = Screen:scaleBySize(8), margin = 0,
            TextWidget:new { text = self.series_text, face = face(15, true) },
        }
    end
    head[#head + 1] = texts
    group[#group + 1] = head
    group[#group + 1] = VerticalSpan:new { width = Screen:scaleBySize(12) }
    group[#group + 1] = LineWidget:new { dimen = Geom:new { w = inner, h = Size.line.thick }, background = Blitbuffer.COLOR_BLACK }
    group[#group + 1] = VerticalSpan:new { width = Screen:scaleBySize(8) }

    -- How it went: a label on the left, the figure on the right. A line the plugin cannot know is not here.
    for _i, line in ipairs(self.lines or {}) do
        local label = TextWidget:new { text = line.label, face = face(17) }
        local value = TextWidget:new { text = line.value, face = face(17, true) }
        group[#group + 1] = HorizontalGroup:new {
            LeftContainer:new { dimen = Geom:new { w = math.floor(inner / 2), h = label:getSize().h }, label },
            RightContainer:new { dimen = Geom:new { w = inner - math.floor(inner / 2), h = value:getSize().h }, value },
        }
        group[#group + 1] = VerticalSpan:new { width = Screen:scaleBySize(4) }
    end
    if #(self.lines or {}) > 0 then
        group[#group + 1] = VerticalSpan:new { width = Screen:scaleBySize(4) }
        group[#group + 1] = LineWidget:new { dimen = Geom:new { w = inner, h = Size.line.thin }, background = Blitbuffer.COLOR_DARK_GRAY }
        group[#group + 1] = VerticalSpan:new { width = Screen:scaleBySize(6) }
    end

    -- Your rating: five stars, each one a tap target.
    self.stars = {}
    local rate_row = HorizontalGroup:new { align = "center" }
    local rate_label = TextWidget:new { text = _("Your rating"), face = face(17) }
    rate_row[#rate_row + 1] = rate_label
    rate_row[#rate_row + 1] = HorizontalSpan:new { width = Screen:scaleBySize(16) }
    for n = 1, 5 do
        local star = TextWidget:new { text = (n <= (self.rating or 0)) and STAR_ON or STAR_OFF, face = Font:getFace("cfont", 30) }
        self.stars[n] = star
        local tap = InputContainer:new { dimen = Geom:new { w = star:getSize().w + Screen:scaleBySize(10), h = star:getSize().h }, star }
        tap.ges_events = { TapStar = { GestureRange:new { ges = "tap", range = function() return tap.dimen end } } }
        tap.onTapStar = function() self:setRating(n); return true end
        rate_row[#rate_row + 1] = tap
    end
    group[#group + 1] = rate_row
    group[#group + 1] = VerticalSpan:new { width = Screen:scaleBySize(14) }

    -- What next.
    local rows = {}
    if self.next_title then
        rows[#rows + 1] = { { text = _("Next: ") .. self.next_title, bold = true, callback = function() if self.on_next then self.on_next() end end } }
    end
    rows[#rows + 1] = { { text = _("Done"), callback = function() self:finish() end } }
    group[#group + 1] = ButtonTable:new { width = inner, buttons = rows, show_parent = self }

    self.frame = FrameContainer:new {
        background = Blitbuffer.COLOR_WHITE, bordersize = Size.border.window, radius = Size.radius.window,
        padding = pad, padding_top = Size.padding.default, padding_bottom = Size.padding.default, margin = 0, group,
    }
    self[1] = CenterContainer:new { dimen = self.dimen, self.frame }
end

function AfterwordScreen:setRating(n)
    -- A second tap on the first star clears the rating, as it does on KOReader's own book status page.
    if n == 1 and self.rating == 1 then n = 0 end
    self.rating = n
    for i, star in ipairs(self.stars) do star:setText((i <= n) and STAR_ON or STAR_OFF) end
    if self.on_rate then self.on_rate(n) end
    UIManager:setDirty(self, "ui")
end

function AfterwordScreen:finish()
    if self.on_done then self.on_done() end
end

function AfterwordScreen:onClose() self:finish(); return true end

function AfterwordScreen:onTapOutside(arg, ges)
    if self.frame and ges.pos:notIntersectWith(self.frame.dimen) then self:finish(); return true end
end

function AfterwordScreen:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
end

return AfterwordScreen
