local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local Series = require("afterword/series")
local Stats = require("afterword/stats")
local Store = require("afterword/store")
local AfterwordScreen = require("afterword/screen")

local Afterword = WidgetContainer:extend {
    name = "afterword",
    is_doc_only = true, -- it only matters while a book is open
}

local SETTING = "afterword_enabled"

local function enabled()
    return G_reader_settings:readSetting(SETTING) ~= false -- on unless switched off
end

function Afterword:init()
    self.ui.menu:registerToMainMenu(self)
    -- KOReader's own handler for the last page is registered before any plugin and does not stop the event, so both would run.
    -- This session's copy of it is wrapped: with Afterword on it shows the Afterword screen, with it off (or for the quickstart
    -- guide) it is KOReader's own, untouched.
    local status = self.ui.status
    if status and not status._afterword_original then
        status._afterword_original = status.onEndOfBook
        local plugin = self
        status.onEndOfBook = function(this, ...)
            if enabled() and plugin:handleEnd() then return end
            return this._afterword_original(this, ...)
        end
    end
end

function Afterword:addToMainMenu(menu_items)
    menu_items.afterword = {
        sorting_hint = "more_tools",
        text = _("Afterword"),
        sub_item_table = {
            {
                text = _("Show at the end of a book"),
                help_text = _("Show this screen when you reach the end of a book, instead of KOReader's end-of-book popup."),
                checked_func = enabled,
                callback = function() G_reader_settings:saveSetting(SETTING, not enabled()) end,
            },
            {
                text = _("Preview now"),
                help_text = _("Show the screen for this book without reaching its end."),
                callback = function() self:handleEnd(true) end,
            },
        },
    }
end

-- What the screen needs, gathered from KOReader's databases; each piece may be missing.
function Afterword:gather()
    local file = self.ui.document and self.ui.document.file
    local out = { file = file, lines = {}, title = nil, author = nil, series_text = nil, cover = nil, next = nil }
    local props = self.ui.doc_props or {}
    out.title = props.display_title or props.title or (file and file:match("([^/]+)%.%w+$")) or "?"
    out.author = props.authors and (tostring(props.authors):gsub("\n", ", ")) or nil
    local md5 = self.ui.doc_settings and self.ui.doc_settings:readSetting("partial_md5_checksum")
    local ok, err = pcall(function()
        local SQ3 = require("lua-ljsqlite3/init")
        local db = SQ3.open(DataStorage:getSettingsDir() .. "/statistics.sqlite3", "ro")
        local stats = Store.book_stats(db, md5, os.time())
        db:close()
        if stats then out.lines = Stats.lines(stats) end
    end)
    if not ok then logger.warn("afterword: could not read the statistics: " .. tostring(err)) end
    ok, err = pcall(function()
        local BIM = require("bookinfomanager")
        BIM:openDbConnection()
        local library = Store.library(BIM.db_conn)
        out.next = Series.next_in_series(library, file)
        local pos = Series.position(library, file)
        if pos then out.series_text = string.format("%s #%s", pos.series, string.format("%g", pos.index)) end
        local info = BIM:getBookInfo(file, true)
        if info and info.has_cover and info.cover_bb then out.cover = info.cover_bb end
    end)
    if not ok then logger.warn("afterword: could not read the library: " .. tostring(err)) end
    return out
end

-- The rating KOReader keeps for this book (0 when none).
function Afterword:rating()
    local summary = self.ui.doc_settings and self.ui.doc_settings:readSetting("summary")
    return summary and tonumber(summary.rating) or 0
end

-- The stars write where KOReader's own book status page does: the book's summary, and the book list's copy of it.
function Afterword:setRating(n)
    local summary = self.ui.doc_settings:readSetting("summary") or {}
    summary.rating = n ~= 0 and n or nil
    summary.modified = os.date("%Y-%m-%d", os.time())
    self.ui.doc_settings:saveSetting("summary", summary)
    pcall(function()
        require("ui/widget/booklist").setBookInfoCacheProperty(self.ui.document.file, "rating", n)
    end)
end

-- Shows the screen and returns true, or returns nil to leave the end of the book to KOReader. `preview`: shown on request, in the
-- middle of a book (so the quickstart guide is no reason to hold back).
function Afterword:handleEnd(preview)
    if not preview then
        local QuickStart = require("ui/quickstart")
        if G_reader_settings:readSetting("lastfile") == QuickStart.quickstart_filename then return nil end
    end
    if not (self.ui.document and self.ui.document.file) then return nil end
    local info = self:gather()
    local function close() if self.screen then UIManager:close(self.screen); self.screen = nil end end
    self.screen = AfterwordScreen:new {
        title = info.title, author = info.author, series_text = info.series_text, cover = info.cover,
        lines = info.lines, rating = self:rating(),
        on_rate = function(n) self:setRating(n) end,
        next_title = info.next and info.next.title or nil,
        on_next = function()
            close()
            self.ui:switchDocument(info.next.path)
        end,
        on_done = close,
    }
    UIManager:show(self.screen)
    logger.info("afterword: screen shown for " .. tostring(info.file))
    return true
end

return Afterword
