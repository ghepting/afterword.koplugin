-- What to read next, in groups. No KOReader in here: everything it needs comes in through `ctx`.
--
--   ctx.current      path of the book just finished (never suggested)
--   ctx.library      { { path, title, authors, series, series_index }, ... } every book KOReader has details of; authors are one per line
--   ctx.status_of    function(path) -> "new" | "reading" | "complete" | "abandoned"  (a book never opened is "new")
--   ctx.modified_of  function(path) -> when the file was added, a number (larger is newer)
--   ctx.history      { path, ... } books you have opened, most recent first
--   ctx.collection   { name, paths } a collection chosen in settings, in its own order; or nil
--   ctx.per_group    how many in each group (default 3)
--
-- groups(ctx) -> { { id, name, books = { { path, title, note }, ... } }, ... } with a group left out when it has no books. A book
-- appears once, in the first group that wants it. A book you have finished is never offered.
local Series = require("afterword/series")

local Suggest = {}

local function norm(s) return (tostring(s or ""):lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end

local function authors_of(record)
    local set = {}
    for name in tostring(record.authors or ""):gmatch("[^\n]+") do
        local n = norm(name)
        if n ~= "" then set[n] = true end
    end
    return set
end

local function shares_author(a, b)
    for name in pairs(a) do
        if b[name] then return true end
    end
    return false
end

local function title_of(record, path)
    return record and record.title or tostring(path):match("([^/]+)%.%w+$") or tostring(path)
end

function Suggest.groups(ctx)
    local per = ctx.per_group or 3
    local by_path = {}
    for _i, r in ipairs(ctx.library or {}) do by_path[r.path] = r end
    local status_of = ctx.status_of or function() return "new" end
    local taken = { [ctx.current] = true }
    local out = {}

    local function offer(id, name, books)
        if #books > 0 then out[#out + 1] = { id = id, name = name, books = books } end
    end
    -- Adds a book to a group when it is not the current one, not finished, and not already in an earlier group.
    local function take(group, path, note)
        if #group >= per or taken[path] or status_of(path) == "complete" then return end
        taken[path] = true
        group[#group + 1] = { path = path, title = title_of(by_path[path], path), note = note }
    end

    -- 1. The next book in the series: the first one after this that you have not finished.
    local series = {}
    for _i, r in ipairs(Series.after(ctx.library or {}, ctx.current)) do
        if #series == 0 and status_of(r.path) ~= "complete" then
            take(series, r.path, string.format("%s #%s", r.series, string.format("%g", tonumber(r.series_index))))
        end
    end
    offer("series", "next_in_series", series)

    -- 2. More by this author: their other books you have not started, series together and in order.
    local me = by_path[ctx.current]
    local mine = me and authors_of(me) or {}
    local author = {}
    if next(mine) then
        local others = {}
        for _i, r in ipairs(ctx.library or {}) do
            if r.path ~= ctx.current and shares_author(mine, authors_of(r)) and status_of(r.path) == "new" then others[#others + 1] = r end
        end
        table.sort(others, function(a, b)
            local sa, sb = norm(a.series), norm(b.series)
            if sa ~= sb then
                if sa == "" or sb == "" then return sb == "" end
                return sa < sb
            end
            local ia, ib = tonumber(a.series_index), tonumber(b.series_index)
            if ia ~= ib then
                if ia == nil or ib == nil then return ib == nil end
                return ia < ib
            end
            return norm(a.title) < norm(b.title)
        end)
        for _i, r in ipairs(others) do take(author, r.path) end
    end
    offer("author", "more_by_author", author)

    -- 3. Your collection: its first books, in its own order, that you have not finished.
    local collection = {}
    if ctx.collection and ctx.collection.paths then
        for _i, path in ipairs(ctx.collection.paths) do take(collection, path) end
    end
    if #collection > 0 then out[#out + 1] = { id = "collection", name = "collection", collection_name = ctx.collection.name, books = collection } end

    -- 4. Recently added: the newest books you have not started.
    local recent = {}
    local candidates = {}
    for _i, r in ipairs(ctx.library or {}) do
        if not taken[r.path] and status_of(r.path) == "new" then candidates[#candidates + 1] = r end
    end
    local when = {}
    local modified_of = ctx.modified_of or function() return 0 end
    for _i, r in ipairs(candidates) do when[r.path] = tonumber(modified_of(r.path)) or 0 end
    table.sort(candidates, function(a, b)
        if when[a.path] ~= when[b.path] then return when[a.path] > when[b.path] end
        return tostring(a.path) < tostring(b.path)
    end)
    for _i, r in ipairs(candidates) do take(recent, r.path) end
    offer("recent", "recently_added", recent)

    -- 5. Pick up where you left off: books you started, most recently opened first.
    local started = {}
    for _i, path in ipairs(ctx.history or {}) do
        if status_of(path) == "reading" then take(started, path) end
    end
    offer("started", "started", started)

    return out
end

return Suggest
