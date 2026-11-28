-- The books you mean to read, from a list kept somewhere else. No KOReader in here.
--
--   Wanted.from_csv(text)  -> { source = "goodreads" | "storygraph" | "csv", books = { { title, author, series, series_index }, ... } } or nil, why
--   Wanted.match(wanted, library) -> owned, missing
--       owned   { [path] = wanted book }  the books of the list that are in the library
--       missing { wanted book, ... }      the rest, in the order of the list
--
-- A book is matched by its title and its author's surname, never by an id: the library has no ISBN to go on.

local Wanted = {}

-- parse(text) -> { { field, ... }, ... }. RFC 4180: quoted fields hold commas, doubled quotes and line breaks; CRLF or LF.
function Wanted.parse(text)
    text = tostring(text or ""):gsub("^\239\187\191", "") -- a byte order mark
    local rows, row, field, i, n = {}, {}, {}, 1, #text
    local function end_field() row[#row + 1] = table.concat(field); field = {} end
    local function end_row()
        end_field()
        if not (#row == 1 and row[1] == "") then rows[#rows + 1] = row end
        row = {}
    end
    while i <= n do
        local c = text:sub(i, i)
        if c == '"' and #field == 0 then
            i = i + 1
            while i <= n do
                local q = text:sub(i, i)
                if q == '"' then
                    if text:sub(i + 1, i + 1) == '"' then field[#field + 1] = '"'; i = i + 2
                    else i = i + 1; break end
                else field[#field + 1] = q; i = i + 1 end
            end
        elseif c == "," then end_field(); i = i + 1
        elseif c == "\r" then end_row(); i = i + (text:sub(i + 1, i + 1) == "\n" and 2 or 1)
        elseif c == "\n" then end_row(); i = i + 1
        else field[#field + 1] = c; i = i + 1 end
    end
    if #field > 0 or #row > 0 then end_row() end
    return rows
end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- A title as the matching sees it: lower case, no "(Series, #3)", no subtitle, no punctuation, no leading "the".
function Wanted.title_key(title)
    local s = tostring(title or ""):lower()
    s = s:gsub("%b()", " "):gsub("%b[]", " ")
    s = s:gsub("&", " and "):gsub(":.*$", "")
    s = s:gsub("[^%w%s]", ""):gsub("%s+", " ")
    s = trim(s)
    s = s:gsub("^the ", ""):gsub("^an? ", "")
    return s
end

-- The surname of one author, lower case: the last word of "Robert Galbraith", the part before the comma of "Galbraith, Robert".
function Wanted.surname(author)
    local s = trim(author):lower()
    local before = s:match("^([^,]+),")
    if before then s = before end
    s = s:gsub("[^%w%s]", "")
    return s:match("(%S+)%s*$") or ""
end

-- "The Hallmarked Man (Cormoran Strike, #7)" -> "The Hallmarked Man", "Cormoran Strike", 7
local function split_series(title)
    local inner = title:match("%(([^()]*#[%d%.]+)%)%s*$")
    if not inner then return title, nil, nil end
    local name, num = inner:match("^(.-),?%s*#([%d%.]+)$")
    local base = trim(title:gsub("%s*%([^()]*#[%d%.]+%)%s*$", ""))
    name = trim(name)
    return base, name ~= "" and name or nil, tonumber(num)
end

local function column(header, ...)
    for _, want in ipairs({ ... }) do
        for i, name in ipairs(header) do
            if trim(name):lower() == want then return i end
        end
    end
end

local DONE = { ["to-read"] = true, ["to read"] = true, ["want to read"] = true, ["want-to-read"] = true, ["tbr"] = true }

function Wanted.from_csv(text)
    local rows = Wanted.parse(text)
    if #rows < 2 then return nil, "empty" end
    local header = rows[1]
    local title_at = column(header, "title")
    local author_at = column(header, "author", "authors")
    if not title_at or not author_at then return nil, "columns" end
    local source = "csv"
    local status_at
    if column(header, "exclusive shelf") then source, status_at = "goodreads", column(header, "exclusive shelf")
    elseif column(header, "read status") then source, status_at = "storygraph", column(header, "read status") end
    local books = {}
    for r = 2, #rows do
        local row = rows[r]
        local status = status_at and trim(row[status_at]):lower() or nil
        if (not status_at or DONE[status]) and trim(row[title_at]) ~= "" then
            local title, series, index = split_series(trim(row[title_at]))
            local author = trim((tostring(row[author_at] or ""):match("^([^,]+)") or ""))
            books[#books + 1] = { title = title, author = author, series = series, series_index = index }
        end
    end
    return { source = source, books = books }
end

-- The titles of a library book as the matching sees them: its own, and the title without the series it may carry.
local function library_index(library)
    local by_title = {}
    for _, b in ipairs(library or {}) do
        local key = Wanted.title_key(b.title)
        if key ~= "" then
            by_title[key] = by_title[key] or {}
            table.insert(by_title[key], b)
        end
    end
    return by_title
end

local function has_author(book, surname)
    if surname == "" then return true end
    for name in tostring(book.authors or ""):gmatch("[^\n]+") do
        if Wanted.surname(name) == surname then return true end
    end
    return false
end

function Wanted.match(wanted, library)
    local by_title = library_index(library)
    local owned, missing = {}, {}
    for _, w in ipairs(wanted and wanted.books or {}) do
        local found
        for _, b in ipairs(by_title[Wanted.title_key(w.title)] or {}) do
            if has_author(b, Wanted.surname(w.author)) then found = b; break end
        end
        if found then owned[found.path] = w else missing[#missing + 1] = w end
    end
    return owned, missing
end

-- The name a book's cover is kept under on the device (a list's books carry no id): its title as the matching sees it, and a short number
-- from that title and its author, so two books never share a file.
local function hash(text)
    local h = 5381
    for i = 1, #text do h = (h * 33 + text:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end
function Wanted.cover_name(book)
    local key = Wanted.title_key(book.title)
    local slug = key:gsub("%s+", "-"):sub(1, 40)
    return (slug ~= "" and slug or "book") .. "-" .. hash(key .. "|" .. Wanted.surname(book.author)) .. ".jpg"
end

-- What is kept in KOReader's settings (`settings` is G_reader_settings, or any object with readSetting / saveSetting / delSetting).
-- One list per source ("goodreads", "storygraph", "hardcover", "csv"): importing a source again replaces only its own list.
local LISTS, BOOST, SHOW = "afterword_wanted", "afterword_wanted_boost", "afterword_wanted_show_unowned"

local function all(settings)
    local lists = settings:readSetting(LISTS)
    return type(lists) == "table" and lists or {}
end

-- The saved lists, { { source, books, imported }, ... }, in the order of their names.
function Wanted.lists(settings)
    local out = {}
    for source, list in pairs(all(settings)) do
        if type(list) == "table" and type(list.books) == "table" then
            out[#out + 1] = { source = source, books = list.books, imported = list.imported }
        end
    end
    table.sort(out, function(a, b) return a.source < b.source end)
    return out
end

function Wanted.save(settings, list, now)
    local lists = all(settings)
    lists[list.source] = { books = list.books, imported = now }
    settings:saveSetting(LISTS, lists)
end

-- Forgets one source's list.
function Wanted.forget(settings, source)
    local lists = all(settings)
    lists[source] = nil
    if next(lists) then settings:saveSetting(LISTS, lists) else settings:delSetting(LISTS) end
end

-- Every list as one: a book on several lists once, with `sources` saying which, in the order of the lists.
function Wanted.merged(settings)
    local books, seen = {}, {}
    for _i, list in ipairs(Wanted.lists(settings)) do
        for _j, b in ipairs(list.books) do
            local key = Wanted.title_key(b.title) .. "|" .. Wanted.surname(b.author)
            local at = seen[key]
            if at then
                table.insert(books[at].sources, list.source)
                books[at].cover_url = books[at].cover_url or b.cover_url
            else
                books[#books + 1] = { title = b.title, author = b.author, series = b.series, series_index = b.series_index, cover_url = b.cover_url, sources = { list.source } }
                seen[key] = #books
            end
        end
    end
    return { books = books }
end

-- Owned books of the lists are ranked higher (on unless switched off); books you do not own get a row (off unless switched on).
function Wanted.boost(settings) return settings:readSetting(BOOST) ~= false end
function Wanted.set_boost(settings, on) settings:saveSetting(BOOST, on and true or false) end
function Wanted.show_unowned(settings) return settings:readSetting(SHOW) == true end
function Wanted.set_show_unowned(settings, on) settings:saveSetting(SHOW, on and true or false) end

return Wanted
