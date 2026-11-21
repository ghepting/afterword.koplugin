-- The sheet shown when you tap a book in the list: its cover and details, why it was picked, and Start reading / Not now.
--
--   Detail:new{ book = { path, title, authors, series, series_index, tags, language, description }, why = "text" or nil,
--               on_open = function(), on_close = function() }
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local PickMenu = require("afterword/picklist")
local Size = require("ui/size")
local Suggest = require("afterword/suggest")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local Screen = Device.screen
local GREY = Blitbuffer.COLOR_DARK_GRAY

local LANGUAGES = {
    en = "English", fr = "French", de = "German", es = "Spanish", it = "Italian", pt = "Portuguese", nl = "Dutch", ja = "Japanese",
    zh = "Chinese", ru = "Russian", pl = "Polish", sv = "Swedish", da = "Danish", no = "Norwegian", fi = "Finnish",
}

local Detail = InputContainer:extend { name = "afterword_detail", book = nil, why = nil, on_open = nil, on_close = nil }

local function s(n) return Screen:scaleBySize(n) end
local function face(size) return Font:getFace("cfont", size) end

-- "en" or "en-US" as a language's name, when we know it; else the code, as written.
local function language_name(code)
    code = tostring(code or "")
    if code == "" then return nil end
    return LANGUAGES[code:lower():match("^(%a+)")] or code
end

-- Genre pills in as many rows as they need.
local function wrapped_chips(tags, max_width)
    local rows, row, used = VerticalGroup:new { align = "left" }, nil, 0
    for _i, tag in ipairs(tags or {}) do
        local pill = PickMenu.chips({ tag }, max_width, 1)
        if pill then
            local w = pill:getSize().w
            if not row or used + w > max_width then
                if row then rows[#rows + 1] = VerticalSpan:new { width = s(4) } end
                row, used = HorizontalGroup:new { align = "center" }, 0
                rows[#rows + 1] = row
            end
            row[#row + 1] = pill
            used = used + w
        end
    end
    return #rows > 0 and rows or nil
end

function Detail:init()
    self.dimen = Geom:new { w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
    if Device:isTouchDevice() then
        self.ges_events.TapOutside = { GestureRange:new { ges = "tap", range = self.dimen } }
    end

    local book = self.book
    local width = math.floor(Screen:getWidth() * 0.92)
    local pad = Size.padding.large
    local inner = width - 2 * pad - 2 * Size.border.window
    local group = VerticalGroup:new { align = "left" }

    local cover_w = math.floor(inner * 0.34)
    local image = PickMenu.cover(book.path, book.title, cover_w, math.floor(cover_w * 1.5))
    local text_w = inner - image:getSize().w - s(16)
    local texts = VerticalGroup:new { align = "left" }
    texts[#texts + 1] = TextBoxWidget:new { text = book.title or "?", face = Font:getFace("tfont", 24), bold = true, width = text_w }
    if book.authors and book.authors ~= "" then
        texts[#texts + 1] = VerticalSpan:new { width = s(4) }
        texts[#texts + 1] = TextBoxWidget:new { text = (tostring(book.authors):gsub("\n", ", ")), face = face(17), width = text_w }
    end
    local series = Suggest.series_text(book)
    if series then
        texts[#texts + 1] = VerticalSpan:new { width = s(4) }
        texts[#texts + 1] = TextBoxWidget:new { text = series, face = face(14), fgcolor = GREY, width = text_w }
    end
    local language = language_name(book.language)
    if language then
        texts[#texts + 1] = TextWidget:new { text = language, face = face(14), fgcolor = GREY, max_width = text_w }
    end
    local pills = wrapped_chips(book.tags, text_w)
    if pills then
        texts[#texts + 1] = VerticalSpan:new { width = s(8) }
        texts[#texts + 1] = pills
    end
    group[#group + 1] = HorizontalGroup:new { align = "top", image, HorizontalSpan:new { width = s(16) }, texts }

    if self.why and self.why ~= "" then
        group[#group + 1] = VerticalSpan:new { width = s(14) }
        group[#group + 1] = FrameContainer:new {
            bordersize = Size.border.thin, radius = s(8), margin = 0, padding = s(10),
            VerticalGroup:new {
                align = "left",
                TextWidget:new { text = _("Why this"), face = face(14), bold = true },
                VerticalSpan:new { width = s(3) },
                TextBoxWidget:new { text = self.why, face = face(15), width = inner - 2 * s(10) - 2 * Size.border.thin },
            },
        }
    end

    local description = book.description and require("util").htmlToPlainTextIfHtml(book.description):gsub("%s+", " ") or ""
    if description:match("%S") then
        group[#group + 1] = VerticalSpan:new { width = s(14) }
        group[#group + 1] = TextWidget:new { text = _("About"), face = face(14), bold = true }
        group[#group + 1] = VerticalSpan:new { width = s(3) }
        local f = face(15)
        group[#group + 1] = TextBoxWidget:new {
            text = description, face = f, width = inner, height = 6 * TextWidget:new { text = "Ag", face = f }:getSize().h,
            height_overflow_show_ellipsis = true,
        }
    end

    group[#group + 1] = VerticalSpan:new { width = s(16) }
    group[#group + 1] = ButtonTable:new {
        width = inner, show_parent = self,
        buttons = { {
            { text = _("Start reading"), bold = true, callback = function() if self.on_open then self.on_open() end end },
            { text = _("Not now"), callback = function() self:finish() end },
        } },
    }

    self.frame = FrameContainer:new {
        background = Blitbuffer.COLOR_WHITE, bordersize = Size.border.window, radius = Size.radius.window,
        padding = pad, padding_top = Size.padding.default, padding_bottom = Size.padding.default, margin = 0, group,
    }
    self[1] = CenterContainer:new { dimen = self.dimen, self.frame }
end

function Detail:finish()
    if self.on_close then self.on_close() end
end

function Detail:onClose() self:finish(); return true end

function Detail:onTapOutside(arg, ges)
    if self.frame and ges.pos:notIntersectWith(self.frame.dimen) then self:finish(); return true end
end

function Detail:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
end

return Detail
