local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local Series = require("afterword/series")
local Stats = require("afterword/stats")
local Store = require("afterword/store")

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
        checked_func = enabled,
        help_text = _("Show a screen when you reach the end of a book, instead of KOReader's end-of-book popup."),
        callback = function() G_reader_settings:saveSetting(SETTING, not enabled()) end,
    }
end

-- What the screen needs, gathered from KOReader's databases; each piece may be missing.
function Afterword:gather()
    local file = self.ui.document and self.ui.document.file
    local out = { file = file, lines = {}, title = nil, next = nil }
    local props = self.ui.doc_props or {}
    out.title = props.display_title or props.title or (file and file:match("([^/]+)%.%w+$")) or "?"
    local md5 = self.ui.doc_settings and self.ui.doc_settings:readSetting("partial_md5_checksum")
    local ok, err = pcall(function()
        local SQ3 = require("lua-ljsqlite3/init")
        local db = SQ3.open(DataStorage:getSettingsDir() .. "/statistics.sqlite3", "ro")
        local stats = Store.book_stats(db, md5, os.time())
        db:close()
        logger.info("afterword: statistics for md5 " .. tostring(md5) .. ": " .. (stats and "found" or "none"))
        if stats then out.lines = Stats.lines(stats) end
    end)
    if not ok then logger.warn("afterword: could not read the statistics: " .. tostring(err)) end
    ok, err = pcall(function()
        local BIM = require("bookinfomanager")
        BIM:openDbConnection()
        local nxt = Series.next_in_series(Store.library(BIM.db_conn), file)
        if nxt then out.next = nxt end
    end)
    if not ok then logger.warn("afterword: could not read the library: " .. tostring(err)) end
    return out
end

-- Shows the screen and returns true, or returns nil to leave the end of the book to KOReader.
function Afterword:handleEnd()
    local QuickStart = require("ui/quickstart")
    if G_reader_settings:readSetting("lastfile") == QuickStart.quickstart_filename then return nil end
    if not (self.ui.document and self.ui.document.file) then return nil end
    local info = self:gather()
    local buttons = {}
    if info.next then
        buttons[#buttons + 1] = { {
            text = _("Next: ") .. (info.next.title or "?"),
            callback = function()
                UIManager:close(self.screen)
                self.ui:switchDocument(info.next.path)
            end,
        } }
    end
    buttons[#buttons + 1] = { { text = _("Done"), callback = function() UIManager:close(self.screen) end } }
    local lines = { info.title }
    for _i, l in ipairs(info.lines) do lines[#lines + 1] = l.label .. ": " .. l.value end
    self.screen = ButtonDialog:new {
        name = "afterword_screen",
        title = table.concat(lines, "\n"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.screen)
    logger.info("afterword: screen shown for " .. tostring(info.file))
    return true
end

return Afterword
