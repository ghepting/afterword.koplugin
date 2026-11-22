local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local ButtonDialog = require("ui/widget/buttondialog")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
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
local Dispatcher = require("dispatcher")
local Updater = require("afterword/updater")
local Installer = require("afterword/installer")

local Afterword = WidgetContainer:extend {
    name = "afterword",
    is_doc_only = false, -- loaded in the file browser too, so it can be set up before a book is opened
}

local SETTING = "afterword_enabled"
local COLLECTION = "afterword_collection" -- the name of a collection to suggest from, or unset

local function enabled()
    return G_reader_settings:readSetting(SETTING) ~= false -- on unless switched off
end

-- A gesture, profile or hotkey can start this from KOReader's action list.
function Afterword:onDispatcherRegisterActions()
    Dispatcher:registerAction("afterword_next",
        { category = "none", event = "AfterwordNext", title = _("Afterword: what to read next"), general = true })
end

function Afterword:onAfterwordNext()
    self:showWhatNext()
    return true
end

function Afterword:init()
    self:onDispatcherRegisterActions()
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
        sorting_hint = "tools",
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
                text = _("What to read next"),
                help_text = _("Pick something else to read, from a book you have open or from the file browser. It can also be started from a gesture."),
                callback = function(touchmenu_instance)
                    if touchmenu_instance then touchmenu_instance:closeMenu() end
                    self:showWhatNext()
                end,
            },
            {
                text = _("Check for updates"),
                help_text = _("Ask GitHub whether a newer Afterword has been released, and install it if you want. Only when you tap this."),
                keep_menu_open = true,
                callback = function() self:checkForUpdates() end,
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
function Afterword:suggestions(file, without, just_finished)
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
        current = file, follow = (not file) and history[1] or nil, finished = just_finished and file or nil, library = library, status_of = status_of, without = without,
        rating_of = function(path)
            local info = require("ui/widget/booklist").getBookInfo(path)
            return info and tonumber(info.rating) or 0
        end,
        percent_of = function(path)
            local info = require("ui/widget/booklist").getBookInfo(path)
            return info and tonumber(info.percent_finished) or 0
        end,
        modified_of = function(path) return lfs.attributes(path, "modification") or 0 end,
        history = history, collection = collection,
    }
end

-- The list of suggestions. Tapping a book opens it.
-- `opts.title` names it; `opts.without` leaves out the groups that are about the book you are leaving; `opts.just_finished` says the
-- open book has been finished, so its sequel is next in line although it may not be marked finished yet.
function Afterword:showPicker(info, on_open, opts)
    opts = opts or {}
    local PickMenu = require("afterword/picklist")
    local groups = self:suggestions(info.file, opts.without, opts.just_finished)
    local first_author = info.author and info.author:match("^[^,]+") or nil
    local heading = {
        next_in_series = function() return _("Next in the series") end,
        more_by_author = function(g)
            local who = first_author or g.author_name
            return who and T(_("More by %1"), who) or _("More by this author")
        end,
        collection = function(g) return T(_("From %1"), g.collection_name or "") end,
        picked_for_you = function() return _("Picked for you") end,
        something_different = function() return _("Something different") end,
        recently_added = function() return _("Recently added") end,
        on_hold = function() return _("On hold") end,
        started = function() return _("Keep reading") end,
    }
    -- The first two single picks sit side by side at the top; every other group (and any further single pick) is a column of books
    -- below them, three columns to a row.
    local single = { next_in_series = true, picked_for_you = true, something_different = true }
    local items, cards, columns = {}, {}, {}
    for _i, g in ipairs(groups) do
        local name = (heading[g.name] or function() return g.name end)(g)
        if single[g.name] and #cards < 2 then
            local book = g.books[1]
            cards[#cards + 1] = {
                heading = name, book = book, why = (Suggest.explain(g.name, book, g)),
                solid = #cards == 0, button = _("Start reading"),
            }
        else
            columns[#columns + 1] = { heading = name, books = g.books, progress = g.name == "started" }
        end
    end
    if #cards > 0 then items[#items + 1] = { kind = "picks", cards = cards } end
    for first = 1, #columns, 3 do
        local row = {}
        for i = first, math.min(first + 2, #columns) do row[#row + 1] = columns[i] end
        items[#items + 1] = { kind = "lists", columns = row }
    end
    if #items == 0 then
        UIManager:show(require("ui/widget/infomessage"):new { text = _("Nothing to suggest yet.") })
        return
    end
    local menu
    menu = PickMenu:new {
        title = opts.title or _("Pick next"), item_table = items, items_max_lines = 2, -- rows of different heights: PickMenu measures and draws them
        is_borderless = true, is_popout = false, covers_fullscreen = true, is_enable_shortcut = false,
        close_callback = function() UIManager:close(menu) end,
        on_open = function(book) on_open(book.path) end,
    }
    self.picker = menu
    UIManager:show(menu)
    return menu
end

-- Opens a book from wherever the person is: the reader switches documents, the file browser opens the reader.
function Afterword:openBook(path)
    if self.picker then UIManager:close(self.picker); self.picker = nil end
    if self.ui.document then
        self.ui:switchDocument(path)
    else
        require("apps/reader/readerui"):showReader(path)
    end
end

-- What to read next, on request: from a book you have open (and are perhaps not into) or from the file browser. The book you leave
-- stays as it is, still "reading", and turns up under "Pick up where you left off".
function Afterword:showWhatNext()
    local file = self.ui.document and self.ui.document.file
    self:showPicker({ file = file }, function(path) self:openBook(path) end, {
        title = _("What to read next"),
        -- Those two are about the book you are leaving; from the file browser they follow on from the book you read last.
        without = file and { next_in_series = true, more_by_author = true } or nil,
    })
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

-- Shows the screen and returns true, or returns nil to leave the end of the book to KOReader.
function Afterword:handleEnd()
    local QuickStart = require("ui/quickstart")
    if G_reader_settings:readSetting("lastfile") == QuickStart.quickstart_filename then return nil end
    if not (self.ui.document and self.ui.document.file) then return nil end
    local info = self:gather()
    local was = self:status()
    local finished = Finish.default(G_reader_settings:isTrue("end_document_auto_mark"), was)
    -- Leaving the screen applies the box.
    local function close()
        local status = Finish.status_after(was, finished)
        if status then self:setStatus(status) end
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
            end, { just_finished = true })
        end,
        on_done = close,
    }
    UIManager:show(self.screen)
    logger.info("afterword: screen shown for " .. tostring(info.file))
    return true
end

-- One dialog at a time: a second tap while one is up (easy on a slow e-ink screen) is ignored, so dialogs cannot stack.
function Afterword:showDialog(make)
    -- Not called `dialog`: inside a book the reader gives every plugin a `dialog` field that points at itself, which would make
    -- this guard refuse to show anything.
    if self.popup and UIManager:isWidgetShown(self.popup) then return end
    self.popup = make()
    UIManager:show(self.popup)
end

function Afterword:notify(text)
    self:showDialog(function() return InfoMessage:new { text = text } end)
end

-- The version this copy says it is, from its own _meta.lua.
function Afterword:currentVersion()
    local ok, meta = pcall(dofile, self.path .. "/_meta.lua")
    return ok and type(meta) == "table" and meta.version or "0.0.0"
end

-- Asks GitHub for the latest release, when online, and says what it found. Runs only when asked.
function Afterword:checkForUpdates()
    local current = self:currentVersion()
    require("ui/network/manager"):runWhenOnline(function()
        local busy = InfoMessage:new { text = _("Checking for updates…") }
        UIManager:show(busy)
        UIManager:forceRePaint()
        local result = Updater.check(current)
        UIManager:close(busy)
        self:showUpdateResult(current, result)
    end)
end

-- Why an update cannot be installed here, or nil when it can: this copy is a link to a source checkout, which an update would swap
-- out from under the developer.
function Afterword:updateBlockedReason()
    if lfs.symlinkattributes(self.path, "mode") == "link" then
        return _("This copy of Afterword is a link to a source checkout, so it is updated with git, not from here.")
    end
end

function Afterword:showUpdateResult(current, result)
    local blocked = self:updateBlockedReason()
    self:showDialog(function()
        local dialog
        local function act(fn)
            return function()
                UIManager:close(dialog)
                fn()
            end
        end
        local rows = {}
        local text = Updater.message(result, current)
        if result.state == "available" then
            if blocked then
                text = text .. "\n\n" .. blocked
            elseif result.asset then
                table.insert(rows, { { text = _("Update now"), callback = act(function() self:confirmInstall(current, result) end) } })
            end
            table.insert(rows, { { text = _("Close"), callback = act(function() end) } })
            -- A viewer scrolls long release notes and keeps its buttons on screen, which a dialog's title does not.
            dialog = require("ui/widget/textviewer"):new { title = _("Update available"), text = text, buttons_table = rows }
            return dialog
        end
        table.insert(rows, { { text = _("Close"), callback = act(function() end) } })
        dialog = ButtonDialog:new { title = text, title_align = "center", buttons = rows }
        return dialog
    end)
end

function Afterword:confirmInstall(current, result)
    local blocked = self:updateBlockedReason()
    if blocked then self:notify(blocked) return end
    self:showDialog(function()
        return ConfirmBox:new {
            text = T(_("Update Afterword from %1 to %2?\n\nThis downloads %3, checks it against GitHub's checksum, installs it and offers to restart KOReader. If anything goes wrong nothing is changed, and the current version is kept as afterword.koplugin.old."),
                current, result.latest, util.getFriendlySize(result.asset.size or 0)),
            ok_text = _("Update"),
            ok_callback = function() self:installUpdate(result) end,
        }
    end)
end

-- Downloads, checks and installs the release in `result` (see Updater.interpret) over this plugin.
function Afterword:installUpdate(result)
    -- The confirm box is still up while its callback runs, and showDialog shows nothing over a popup.
    if self.popup then UIManager:close(self.popup) end
    local busy = InfoMessage:new { text = _("Updating Afterword…") }
    UIManager:show(busy)
    UIManager:forceRePaint()
    local cache = DataStorage:getDataDir() .. "/cache"
    lfs.mkdir(cache)
    lfs.mkdir(cache .. "/afterword")
    local ok, err = Installer.install(result.asset, result.latest, self.path, cache .. "/afterword/update.zip")
    UIManager:close(busy)
    if not ok then
        self:notify(T(_("The update was not installed, and nothing was changed.\n\n%1"), tostring(err)))
        return
    end
    local can_restart = Device:canRestart()
    self:showDialog(function()
        return ConfirmBox:new {
            text = can_restart and T(_("Afterword %1 is installed.\n\nRestart KOReader to start using it."), result.latest)
                or T(_("Afterword %1 is installed.\n\nQuit KOReader and open it again to start using it."), result.latest),
            ok_text = can_restart and _("Restart now") or _("Quit now"),
            cancel_text = _("Later"),
            ok_callback = function()
                if can_restart then UIManager:restartKOReader() else UIManager:quit() end
            end,
        }
    end)
end

return Afterword
