local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local Series = require("afterword/series")
local Stats = require("afterword/stats")
local Store = require("afterword/store")
local AfterwordScreen = require("afterword/screen")
local Finish = require("afterword/finish")
local Suggest = require("afterword/suggest")

local Afterword = WidgetContainer:extend {
    name = "afterword",
    is_doc_only = true, -- it only matters while a book is open
}

local SETTING = "afterword_enabled"
local COLLECTION = "afterword_collection" -- the name of a collection to suggest from, or unset

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
                text_func = function()
                    local name = G_reader_settings:readSetting(COLLECTION)
                    return name and T(_("Suggest from the collection: %1"), name) or _("Suggest from a collection\u{2026}")
                end,
                help_text = _("Pick next also offers the first books of a collection you choose here."),
                keep_menu_open = true,
                callback = function(touchmenu_instance) self:chooseCollection(touchmenu_instance) end,
            },
            {
                text = _("Preview now"),
                help_text = _("Show the screen for this book without reaching its end."),
                callback = function() self:handleEnd(true) end,
            },
        },
    }
end

-- Where a book stands, in the words suggest.lua uses.
local function status_of(path)
    local BookList = require("ui/widget/booklist")
    local info = BookList.getBookInfo(path)
    if not info or not info.been_opened then return "new" end
    if info.status == "complete" or (tonumber(info.percent_finished) or 0) >= 1 then return "complete" end
    if info.status == "abandoned" then return "abandoned" end
    return "reading"
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
        for _i, r in ipairs(Series.after(library, file)) do
            if status_of(r.path) ~= "complete" then out.next = r; break end -- the first one after this you have not finished
        end
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

-- Asks which collection to suggest from (or none).
function Afterword:chooseCollection(touchmenu_instance)
    local ReadCollection = require("readcollection")
    local buttons = {}
    local dialog
    local names = {}
    for name in pairs(ReadCollection.coll or {}) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    local function choose(name)
        if name then G_reader_settings:saveSetting(COLLECTION, name) else G_reader_settings:delSetting(COLLECTION) end
        UIManager:close(dialog)
        if touchmenu_instance then touchmenu_instance:updateItems() end
    end
    buttons[#buttons + 1] = { { text = _("None"), callback = function() choose(nil) end } }
    for _i, name in ipairs(names) do
        buttons[#buttons + 1] = { { text = name, callback = function() choose(name) end } }
    end
    local ButtonDialog = require("ui/widget/buttondialog")
    dialog = ButtonDialog:new { title = _("Suggest from which collection?"), buttons = buttons }
    UIManager:show(dialog)
end

-- What to read next, in groups, for the book just finished.
function Afterword:suggestions(file)
    local library, history, collection = {}, {}, nil
    local ok, err = pcall(function()
        local BIM = require("bookinfomanager")
        BIM:openDbConnection()
        library = Store.books(BIM.db_conn)
    end)
    if not ok then logger.warn("afterword: could not read the library: " .. tostring(err)) end
    pcall(function()
        -- KOReader's own manual is in the history after a first run; it is not something to read next.
        local manual = require("ui/quickstart").quickstart_filename
        for _i, item in ipairs(require("readhistory").hist or {}) do
            if item.file ~= manual then history[#history + 1] = item.file end
        end
    end)
    local name = G_reader_settings:readSetting(COLLECTION)
    if name then
        pcall(function()
            local ReadCollection = require("readcollection")
            local paths = {}
            for _i, item in ipairs(ReadCollection:getOrderedCollection(name)) do paths[#paths + 1] = item.file end
            collection = { name = name, paths = paths }
        end)
    end
    local lfs = require("libs/libkoreader-lfs")
    return Suggest.groups {
        current = file, library = library, status_of = status_of,
        modified_of = function(path) return lfs.attributes(path, "modification") or 0 end,
        history = history, collection = collection,
    }
end

-- The list of suggestions. Tapping a book opens it.
function Afterword:showPicker(info, on_open)
    local Menu = require("ui/widget/menu")
    local groups = self:suggestions(info.file)
    local first_author = info.author and info.author:match("^[^,]+") or nil
    local heading = {
        next_in_series = function() return _("Next in the series") end,
        more_by_author = function() return first_author and T(_("More by %1"), first_author) or _("More by this author") end,
        collection = function(g) return T(_("From %1"), g.collection_name or "") end,
        recently_added = function() return _("Recently added") end,
        started = function() return _("Pick up where you left off") end,
    }
    local items = {}
    for _i, g in ipairs(groups) do
        items[#items + 1] = { text = (heading[g.name] or function() return g.name end)(g), bold = true, dim = true, callback = function() end }
        for _j, book in ipairs(g.books) do
            items[#items + 1] = { text = "    " .. book.title, mandatory = book.note, callback = function() on_open(book.path) end }
        end
    end
    if #items == 0 then
        UIManager:show(require("ui/widget/infomessage"):new { text = _("Nothing to suggest yet.") })
        return
    end
    local menu
    menu = Menu:new {
        title = _("Pick next"), item_table = items, is_borderless = true, is_popout = false, covers_fullscreen = true, is_enable_shortcut = false,
        close_callback = function() UIManager:close(menu) end,
    }
    UIManager:show(menu)
    return menu
end

-- The reader's book status as KOReader keeps it ("complete", "reading", ...), or nil.
function Afterword:status()
    local summary = self.ui.doc_settings and self.ui.doc_settings:readSetting("summary")
    return summary and summary.status or nil
end

-- Writes a status the way KOReader's own "mark as finished" does: the book's summary and the book list's copy.
function Afterword:setStatus(status)
    local summary = self.ui.doc_settings:readSetting("summary") or {}
    summary.status = status
    summary.modified = os.date("%Y-%m-%d", os.time())
    self.ui.doc_settings:saveSetting("summary", summary)
    pcall(function()
        require("ui/widget/booklist").setBookInfoCacheProperty(self.ui.document.file, "status", status)
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
    local was = self:status()
    local finished = Finish.default(G_reader_settings:isTrue("end_document_auto_mark"), was)
    -- Leaving the screen applies the box. A preview, which may be shown halfway through a book, never changes the book's status.
    local function close()
        if not preview then
            local status = Finish.status_after(was, finished)
            if status then self:setStatus(status) end
        end
        if self.screen then UIManager:close(self.screen); self.screen = nil end
    end
    self.screen = AfterwordScreen:new {
        title = info.title, author = info.author, series_text = info.series_text, cover = info.cover,
        lines = info.lines, rating = self:rating(),
        on_rate = function(n) self:setRating(n) end,
        finished = finished, on_finished = function(checked) finished = checked end,
        next_title = info.next and info.next.title or nil,
        on_next = function()
            close()
            self.ui:switchDocument(info.next.path)
        end,
        on_pick = function()
            self:showPicker(info, function(path)
                close()
                self.ui:switchDocument(path)
            end)
        end,
        on_done = close,
    }
    UIManager:show(self.screen)
    logger.info("afterword: screen shown for " .. tostring(info.file))
    return true
end

return Afterword
