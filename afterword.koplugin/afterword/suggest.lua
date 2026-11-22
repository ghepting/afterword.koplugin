-- What to read next, in groups. No KOReader in here: everything it needs comes in through `ctx`.
--
--   ctx.current      path of the book just finished, or the one open now (never suggested); nil when none is open
--   ctx.finished     path of the book just finished, counted as finished although it may not be marked so yet (end of a book)
--   ctx.without      { next_in_series = true, more_by_author = true } groups to leave out (they are about ctx.current)
--   ctx.rating_of    function(path) -> 0 (none) to 5; with it, one unread book that fits your taste is offered, and, when a book is
--                    open, or else the one you read last, one that is the opposite of it
--   ctx.library      { { path, title, authors, series, series_index }, ... } every book KOReader has details of; authors are one per line
--   ctx.status_of    function(path) -> "new" | "reading" | "complete" | "abandoned"  (a book never opened is "new")
--   ctx.modified_of  function(path) -> when the file was added, a number (larger is newer)
--   ctx.percent_of   function(path) -> how far through a book you are, 0 to 1 (optional; shown on the books you started)
--   ctx.history      { path, ... } books you have opened, most recent first (started books outside it are found in the library)
--   ctx.collection   { name, paths } a collection chosen in settings, in its own order; or nil
--   ctx.per_group    how many in each group (default 4, a shelf of covers)
--
-- groups(ctx) -> { { id, name, books = { { path, title, note }, ... } }, ... } with a group left out when it has no books. A book
-- appears once, in the first group that wants it. A book you have finished is never offered.
local _ = require("gettext")
local T = require("ffi/util").template
local Series = require("afterword/series")
local Taste = require("afterword/taste")

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

-- "Book 3 of Strike" for a numbered book in a series, "Strike" for one without a number, nil for a book in none.
function Suggest.series_text(book)
    if not book or not book.series or book.series == "" then return nil end
    local index = tonumber(book.series_index)
    if index then return T(_("Book %1 of %2"), string.format("%g", index), book.series) end
    return book.series
end

-- The second line under a title: "Colleen Hoover \u{00B7} Book 3 of Series", with whichever part the book has; nil when it has neither.
function Suggest.byline(book)
    local authors = tostring(book and book.authors or ""):gsub("\n", ", "):gsub("^%s+", ""):gsub("%s+$", "")
    local parts = {}
    if authors ~= "" then parts[#parts + 1] = authors end
    local series = Suggest.series_text(book)
    if series then parts[#parts + 1] = series end
    if #parts == 0 then return nil end
    return table.concat(parts, " \u{00B7} ")
end

-- "A and B" for two titles, "A" for one.
local function and_join(list)
    if #list >= 2 then return T(_("%1 and %2"), list[1], list[2]) end
    return list[1] or ""
end

-- Why a suggestion was made, in a sentence: `short` for a card, `long` for the detail sheet. Both are nil when there is nothing to say.
function Suggest.explain(group_name, book, group)
    local liked, tags = book.because or {}, book.matched or {}
    if group_name == "picked_for_you" and book.fallback == "start" then
        local line = Suggest.series_text(book)
        if line and tonumber(book.series_index) == 1 then
            return T(_("%1, a good place to start"), line), T(_("%1, a good place to start."), line)
        end
        return _("One of your newest books"), _("One of the newest books in your library.")
    elseif group_name == "something_different" and book.fallback then
        local tag = (book.matched or {})[1]
        if tag then
            return T(_("Less common in your library: %1"), tag), T(_("Not many books in your library are %1."), tag)
        end
        return _("A change from most of your library"), _("An author you have few books from, a change from most of your library.")
    elseif group_name == "picked_for_you" and #liked > 0 then
        local short = T(_("Because you liked %1"), and_join(liked))
        if #tags == 0 then return short, short .. "." end
        return short, T(_("You liked %1. They share %2 with this book."), and_join(liked), and_join(tags))
    elseif group_name == "something_different" and book.against then
        local like = tags[1] or (book.tags or {})[1]
        if not like then return nil, T(_("Nothing in common with %1."), book.against) end
        return T(_("Nothing in common with %1, but you like %2"), book.against, like),
            T(_("Nothing in common with %1, but you like %2."), book.against, like)
    elseif group_name == "next_in_series" and book.series then
        return nil, T(_("The next book in %1."), book.series)
    elseif group_name == "started" and (book.percent or 0) > 0 then
        return nil, T(_("You are %1 through it."), book.percent .. "%")
    elseif group_name == "collection" and group.collection_name then
        return nil, T(_("From your collection %1."), group.collection_name)
    elseif group_name == "recently_added" then
        return nil, _("Recently added to your library.")
    end
end

local function title_of(record, path)
    return record and record.title or tostring(path):match("([^/]+)%.%w+$") or tostring(path)
end

function Suggest.groups(ctx)
    local per = ctx.per_group or 4
    local by_path = {}
    for _i, r in ipairs(ctx.library or {}) do by_path[r.path] = r end
    local raw_status = ctx.status_of or function() return "new" end
    local function status_of(path)
        if ctx.finished and path == ctx.finished then return "complete" end
        return raw_status(path)
    end
    -- Nothing new is offered out of order: a book in a series only when every lower-numbered one is finished (Series.eligible).
    local eligible = Series.eligible(ctx.library, status_of)
    local without = ctx.without or {}
    local taken = {}
    if ctx.current then taken[ctx.current] = true end
    local out = {}

    local function offer(id, name, books)
        if #books > 0 then out[#out + 1] = { id = id, name = name, books = books } end
    end
    -- Adds a book to a group when it is not the current one, not finished, and not already in an earlier group.
    -- `resume`: a book you already started, which is not "out of order" whatever its place in a series.
    -- `extra`: more to say about the book (why it was picked, how far through it you are), merged into what it carries.
    local function take(group, path, note, resume, extra)
        if #group >= per or taken[path] or status_of(path) == "complete" then return end
        if not resume and not eligible(path) then return end
        taken[path] = true
        local record = by_path[path]
        local tags = {}
        for line in tostring(record and record.keywords or ""):gmatch("[^\n]+") do
            local tag = line:gsub("^%s+", ""):gsub("%s+$", "")
            if tag ~= "" then tags[#tags + 1] = tag end
        end
        local book = {
            path = path, title = title_of(record, path), note = note,
            series = record and record.series, series_index = record and record.series_index, authors = record and record.authors,
            tags = tags, language = record and record.language, description = record and record.description,
        }
        for key, value in pairs(extra or {}) do book[key] = value end
        group[#group + 1] = book
    end

    -- 1. The next book in the series: the first one after this that you have not finished.
    local series = {}
    for _i, r in ipairs(without.next_in_series and {} or Series.after(ctx.library or {}, ctx.current)) do
        if #series == 0 and status_of(r.path) ~= "complete" then
            take(series, r.path)
        end
    end
    offer("series", "next_in_series", series)

    -- Pick up where you left off: books you started, most recently opened first, then any other started book that is not in the
    -- history. Claimed before the lists below so a half-read book is shown once, under its progress, not as a fresh suggestion.
    local started = {}
    local listed = {}
    for _i, path in ipairs(ctx.history or {}) do listed[#listed + 1] = path end
    local seen = {}
    for _i, path in ipairs(listed) do seen[path] = true end
    for _i, r in ipairs(ctx.library or {}) do
        if not seen[r.path] then listed[#listed + 1] = r.path end
    end
    for _i, path in ipairs(listed) do
        if status_of(path) == "reading" then
            local percent = math.floor((ctx.percent_of and tonumber(ctx.percent_of(path)) or 0) * 100 + 0.5)
            take(started, path, percent > 0 and string.format("%d%%", percent) or nil, true, { percent = percent }) -- nothing for a sliver that rounds to 0%
        end
    end
    offer("started", "started", started)

    -- 2. More by this author: their other books you have not started, series together and in order. Not this book's own series: that
    -- is the group above, and three more books of it under "more by" is the same suggestion again.
    local me = by_path[ctx.current]
    local mine = me and authors_of(me) or {}
    local author = {}
    if next(mine) and not without.more_by_author then
        local others = {}
        for _i, r in ipairs(ctx.library or {}) do
            local same_series = me and norm(me.series) ~= "" and norm(r.series) == norm(me.series)
            if r.path ~= ctx.current and not same_series and shares_author(mine, authors_of(r)) and status_of(r.path) == "new" then
                others[#others + 1] = r
            end
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

    -- 4. Picked for you: one unread book whose tags match the books you have rated highly or finished.
    local foryou = {}
    if ctx.rating_of then
        local pick = Taste.pick { library = ctx.library, status_of = status_of, rating_of = ctx.rating_of, skip = taken, allowed = eligible }
        if pick then take(foryou, pick.path, table.concat(pick.tags, " \u{00B7} "), false, { because = pick.because, matched = pick.tags }) end
    end
    -- With no taste to go on yet (a new device, or nothing rated): a good place to start. The first book of a series you own, else
    -- the newest book.
    local function newest_first(list)
        local when = {}
        for _i, r in ipairs(list) do when[r.path] = tonumber((ctx.modified_of or function() return 0 end)(r.path)) or 0 end
        table.sort(list, function(a, b)
            if when[a.path] ~= when[b.path] then return when[a.path] > when[b.path] end
            return tostring(a.path) < tostring(b.path)
        end)
        return list
    end
    local function unread()
        local list = {}
        for _i, r in ipairs(ctx.library or {}) do
            if r.path ~= ctx.current and not taken[r.path] and status_of(r.path) == "new" and eligible(r.path) then list[#list + 1] = r end
        end
        return newest_first(list)
    end
    if #foryou == 0 and ctx.rating_of then
        local list, firsts = unread(), {}
        for _i, r in ipairs(list) do
            if norm(r.series) ~= "" and tonumber(r.series_index) == 1 then firsts[#firsts + 1] = r end
        end
        local pick = firsts[1] or list[1]
        if pick then take(foryou, pick.path, nil, false, { fallback = "start" }) end
    end
    offer("for_you", "picked_for_you", foryou)

    -- Something different: for when you want the opposite of the book you are on. One unread book with no tag of this one that
    -- fits what you like.
    local different = {}
    -- The opposite of the book you are on or read last; one with no tags has nothing to be the opposite of, so the most recent that
    -- has some is used.
    local anchor
    if ctx.current and Taste.tagged(by_path[ctx.current]) then
        anchor = ctx.current
    else
        for _i, path in ipairs(ctx.history or {}) do
            if Taste.tagged(by_path[path]) then anchor = path; break end
        end
    end
    if ctx.rating_of and anchor then
        local pick = Taste.contrast { library = ctx.library, status_of = status_of, rating_of = ctx.rating_of, skip = taken, allowed = eligible, current = anchor }
        if pick then
            take(different, pick.path, table.concat(pick.tags, " \u{00B7} "), false,
                { because = pick.because, matched = pick.tags, against = title_of(by_path[anchor], anchor) })
        end
    end
    -- With nothing to be the opposite of: a book unlike most of the library. One carrying a tag few other books have, else one by an
    -- author you have few books from.
    if #different == 0 and ctx.rating_of then
        local list = unread()
        local count, authors = {}, {}
        for _i, r in ipairs(ctx.library or {}) do
            for _j, t in ipairs(Taste.tags(r)) do count[t.key] = (count[t.key] or 0) + 1 end
            for name in pairs(authors_of(r)) do authors[name] = (authors[name] or 0) + 1 end
        end
        local best, best_n, best_tag
        for _i, r in ipairs(list) do
            for _j, t in ipairs(Taste.tags(r)) do
                if not best_n or count[t.key] < best_n then best, best_n, best_tag = r, count[t.key], t.label end
            end
        end
        if not best then
            for _i, r in ipairs(list) do
                local fewest
                for name in pairs(authors_of(r)) do fewest = math.min(fewest or math.huge, authors[name]) end
                if fewest and (not best_n or fewest < best_n) then best, best_n = r, fewest end
            end
        end
        if best then take(different, best.path, nil, false, { fallback = "different", matched = best_tag and { best_tag } or nil }) end
    end
    offer("different", "something_different", different)

    -- 6. Recently added: the newest books you have not started.
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


    -- Shown in this order, which is not the order they claim books in: the single picks first, then what you were reading, then lists.
    local rank = { next_in_series = 1, picked_for_you = 2, something_different = 3, started = 4, more_by_author = 5, collection = 6, recently_added = 7 }
    table.sort(out, function(a, b) return (rank[a.name] or 99) < (rank[b.name] or 99) end)
    return out
end

return Suggest
