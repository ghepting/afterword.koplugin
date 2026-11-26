-- Two small things drawn over a screen: a Sheet (what to do about a book, rising from the bottom) and a Toast (a line with Undo that goes by itself).
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Header = require("afterword/header")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local PickMenu = require("afterword/picklist")
local RightContainer = require("ui/widget/container/rightcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Screen = Device.screen
local H = PickMenu.helpers
local s, face = H.s, H.face

local Sheet = InputContainer:extend { modal = true }

-- Sheet:new { title, subtitle, cover_path, options = { { title, subtitle, callback }, ... }, cancel_text, on_close }
function Sheet:init()
    local W, SH = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new { x = 0, y = 0, w = W, h = SH }
    self.ges_events = { TapOutside = { GestureRange:new { ges = "tap", range = self.dimen } } }
    local pad = s(22)
    local inner = W - 2 * pad
    local panel = VerticalGroup:new { align = "left" }
    panel[#panel + 1] = VerticalSpan:new { width = s(16) }
    -- the book (or whatever this is about): a cover, then its title and a line about it
    local top = HorizontalGroup:new { align = "center", HorizontalSpan:new { width = pad } }
    local text_w = inner
    if self.cover_path then
        local cover = H.cover(self.cover_path, self.title, s(44), s(66))
        top[#top + 1] = cover
        top[#top + 1] = HorizontalSpan:new { width = s(14) }
        text_w = inner - cover:getSize().w - s(14)
    end
    local texts = VerticalGroup:new { align = "left",
        TextWidget:new { text = self.title or "", face = Font:getFace("tfont", 19), max_width = text_w, truncate_with_ellipsis = true } }
    if self.subtitle and self.subtitle ~= "" then
        texts[#texts + 1] = TextWidget:new { text = self.subtitle, face = face(12), fgcolor = H.GREY, max_width = text_w, truncate_with_ellipsis = true }
    end
    top[#top + 1] = texts
    panel[#panel + 1] = top
    panel[#panel + 1] = VerticalSpan:new { width = s(12) }
    local function rule() return HorizontalGroup:new { HorizontalSpan:new { width = pad },
        LineWidget:new { dimen = Geom:new { w = inner, h = Size.line.thin }, background = Blitbuffer.COLOR_GRAY } } end
    panel[#panel + 1] = rule()
    for _i, option in ipairs(self.options) do
        local label = VerticalGroup:new { align = "left",
            TextWidget:new { text = option.title, face = Font:getFace("tfont", 17), bold = true, max_width = inner - s(40), truncate_with_ellipsis = true } }
        if option.subtitle then
            label[#label + 1] = TextWidget:new { text = option.subtitle, face = face(12), fgcolor = H.GREY, max_width = inner - s(40), truncate_with_ellipsis = true }
        end
        local row_h = s(66)
        local row = OverlapGroup:new {
            dimen = Geom:new { w = W, h = row_h },
            LeftContainer:new { dimen = Geom:new { w = W, h = row_h }, HorizontalGroup:new { HorizontalSpan:new { width = pad }, label } },
            RightContainer:new { dimen = Geom:new { w = W - pad, h = row_h },
                TextWidget:new { text = "\u{203A}", face = Font:getFace("tfont", 26), fgcolor = Blitbuffer.COLOR_GRAY_4 } },
        }
        panel[#panel + 1] = Header.tappable(row, function() self:close(); option.callback() end)
        panel[#panel + 1] = rule()
    end
    local cancel = CenterContainer:new { dimen = Geom:new { w = W, h = s(56) },
        TextWidget:new { text = self.cancel_text or "Cancel", face = Font:getFace("tfont", 17), bold = true } }
    panel[#panel + 1] = Header.tappable(cancel, function() self:close() end)
    panel[#panel + 1] = VerticalSpan:new { width = s(10) }
    self[1] = BottomContainer:new {
        dimen = Geom:new { w = W, h = SH },
        FrameContainer:new { background = Blitbuffer.COLOR_WHITE, bordersize = Size.border.window, radius = 0, padding = 0, margin = 0, panel },
    }
end

function Sheet:close()
    UIManager:close(self)
    if self.on_close then self.on_close() end
end

function Sheet:onTapOutside() self:close(); return true end

function Sheet:onShow() UIManager:setDirty(self, function() return "ui", self.dimen end) end

-- A line along the bottom that goes by itself after a few seconds, with one thing to undo. Taps elsewhere pass through to the screen below.
local Toast = InputContainer:extend { toast = true }

-- Toast:new { text, undo_text, on_undo, seconds }
function Toast:init()
    local W, SH = Screen:getWidth(), Screen:getHeight()
    local pad = s(22)
    local undo = Header.tappable(TextWidget:new { text = self.undo_text, face = Font:getFace("tfont", 16), bold = true, fgcolor = Blitbuffer.COLOR_WHITE },
        function() self:close(); if self.on_undo then self.on_undo() end end)
    local text_w = W - 2 * pad - 2 * s(20) - undo:getSize().w - s(24)
    local bar = FrameContainer:new {
        background = Blitbuffer.COLOR_BLACK, bordersize = 0, radius = s(10), padding = s(14), padding_left = s(20), padding_right = s(20),
        HorizontalGroup:new { align = "center",
            TextWidget:new { text = self.text, face = face(13), fgcolor = Blitbuffer.COLOR_WHITE, max_width = text_w, truncate_with_ellipsis = true },
            HorizontalSpan:new { width = s(24) }, undo },
    }
    local size = bar:getSize()
    local strip = size.h + s(24)
    self.dimen = Geom:new { x = 0, y = SH - strip, w = W, h = strip }
    self[1] = BottomContainer:new { dimen = Geom:new { w = W, h = SH }, FrameContainer:new { bordersize = 0, padding = 0, margin = 0, padding_bottom = s(12), bar } }
    self.region = self.dimen
end

function Toast:close()
    if self.closed then return end
    self.closed = true
    UIManager:unschedule(self.timeout)
    UIManager:close(self, "ui", self.region)
end

function Toast.show(opts)
    local toast = Toast:new(opts)
    toast.timeout = function() toast:close() end
    UIManager:show(toast, "ui", toast.region)
    UIManager:scheduleIn(opts.seconds or 6, toast.timeout)
    return toast
end

return { Sheet = Sheet, Toast = Toast }
