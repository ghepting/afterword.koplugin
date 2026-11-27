-- The list when there is nothing to put in it: a heading, a line or two, and buttons for what to do next. Full screen under Afterword's
-- own header, so there is always a way out (and, when things are hidden, a way back).
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local Header = require("afterword/header")
local InputContainer = require("ui/widget/container/inputcontainer")
local PickMenu = require("afterword/picklist")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Screen = Device.screen
local s, face, GREY = PickMenu.helpers.s, PickMenu.helpers.face, PickMenu.helpers.GREY

local Empty = InputContainer:extend { covers_fullscreen = true }

-- Empty:new { heading, text, detail, buttons = { { text, solid, callback }, ... } }
function Empty:init()
    local W, SH = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new { x = 0, y = 0, w = W, h = SH }
    local header = Header:new { title = _("Afterword"), width = W, on_close = function() self:close() end }
    local body_w = math.floor(W * 0.8)
    local group = VerticalGroup:new { align = "center" }
    group[#group + 1] = TextWidget:new { text = self.heading, face = Font:getFace("tfont", 24), bold = true, max_width = body_w, truncate_with_ellipsis = true }
    group[#group + 1] = VerticalSpan:new { width = s(10) }
    group[#group + 1] = TextBoxWidget:new { text = self.text, face = face(14), fgcolor = GREY, width = body_w, alignment = "center" }
    if self.detail then
        group[#group + 1] = VerticalSpan:new { width = s(14) }
        group[#group + 1] = TextWidget:new { text = self.detail, face = Font:getFace("tfont", 16), bold = true, max_width = body_w, truncate_with_ellipsis = true }
    end
    group[#group + 1] = VerticalSpan:new { width = s(28) }
    local button_w = math.floor(W * 0.6)
    for _i, b in ipairs(self.buttons or {}) do
        local label = CenterContainer:new { dimen = Geom:new { w = button_w - 2 * s(4), h = s(34) },
            TextWidget:new { text = b.text, face = Font:getFace("tfont", 17), bold = true, fgcolor = b.solid and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK } }
        local box = FrameContainer:new { background = b.solid and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE, bordersize = Size.border.thin,
            radius = s(8), margin = 0, padding = s(4), label }
        group[#group + 1] = Header.tappable(box, function() self:close(); b.callback() end)
        group[#group + 1] = VerticalSpan:new { width = s(10) }
    end
    local below = SH - header:getSize().h
    self[1] = FrameContainer:new { background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0, margin = 0,
        VerticalGroup:new { align = "left", header,
            CenterContainer:new { dimen = Geom:new { w = W, h = below }, group } } }
end

function Empty:close() UIManager:close(self) end

function Empty:onShow() UIManager:setDirty(self, function() return "ui", self.dimen end) end

return Empty
