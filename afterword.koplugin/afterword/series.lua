-- Which book comes next in a series. No KOReader in here.
--
-- A record is { path, series, series_index } for each book in the library, as KOReader's book-info database has it. Books are
-- matched to a series by name, ignoring case and spacing. "Next" is the owned book with the next higher number in the same
-- series, so a series with a gap (you own 1, 2 and 4) goes 2 to 4, and one with a novella between (1, 1.5, 2) goes through it.
local Series = {}

local function norm(s) return (tostring(s or ""):lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end

-- The record of this book, or nil when it is not in the library or has no series.
local function find(records, path)
    for _i, r in ipairs(records) do
        if r.path == path and norm(r.series) ~= "" then return r end
    end
end

-- next_in_series(records, path) -> the record of the next book, or nil. A book with no number is not in order: it has no next,
-- and is never anyone's next.
function Series.next_in_series(records, path)
    local me = find(records, path)
    local mine = me and tonumber(me.series_index)
    if not mine then return nil end
    local best, best_n
    for _i, r in ipairs(records) do
        local n = tonumber(r.series_index)
        if r.path ~= path and norm(r.series) == norm(me.series) and n and n > mine then
            if not best_n or n < best_n or (n == best_n and tostring(r.path) < tostring(best.path)) then best, best_n = r, n end
        end
    end
    return best
end

-- after(records, path) -> every book that comes after this one in its series, in order (the same rule as next_in_series).
function Series.after(records, path)
    local me = find(records, path)
    local mine = me and tonumber(me.series_index)
    if not mine then return {} end
    local out = {}
    for _i, r in ipairs(records) do
        local n = tonumber(r.series_index)
        if r.path ~= path and norm(r.series) == norm(me.series) and n and n > mine then out[#out + 1] = r end
    end
    table.sort(out, function(a, b)
        local na, nb = tonumber(a.series_index), tonumber(b.series_index)
        if na ~= nb then return na < nb end
        return tostring(a.path) < tostring(b.path)
    end)
    return out
end

-- position(records, path) -> { index, last } where `index` is this book's number and `last` the highest number you own in its
-- series; for "book 5 of 8 owned". nil when it is not in a numbered series.
function Series.position(records, path)
    local me = find(records, path)
    local mine = me and tonumber(me.series_index)
    if not mine then return nil end
    local last = mine
    for _i, r in ipairs(records) do
        local n = tonumber(r.series_index)
        if norm(r.series) == norm(me.series) and n and n > last then last = n end
    end
    return { index = mine, last = last, series = me.series }
end

-- missing(records, path) -> the numbers of the books before this one in its series that are not in the library, as whole numbers
-- (book 5 with 1, 2, 3 and 5 owned gives { 4 }; a lone book 3 gives { 1, 2 }); { } for a book that is first, complete so far, or not
-- numbered. A novella (1.5) is not counted: only the whole numbers up to this one are expected.
function Series.missing(records, path)
    local me = find(records, path)
    local mine = me and tonumber(me.series_index)
    if not mine then return {} end
    local owned = {}
    for _i, r in ipairs(records) do
        local n = tonumber(r.series_index)
        if n and norm(r.series) == norm(me.series) then owned[math.floor(n)] = true end
    end
    local out = {}
    for n = 1, math.ceil(mine) - 1 do
        if not owned[n] then out[#out + 1] = n end
    end
    return out
end

-- eligible(records, status_of) -> function(path) -> true when the book may be suggested as something new: it is in no series, or
-- every book of its series with a lower number is finished. So book 3 is not offered while book 2 is unread, half read or on hold;
-- a gap in what you own is skipped. A book in a series but with no number cannot be placed, so it is never offered.
function Series.eligible(records, status_of)
    local by_path, by_series = {}, {}
    for _i, r in ipairs(records or {}) do
        by_path[r.path] = r
        local key = norm(r.series)
        if key ~= "" then
            by_series[key] = by_series[key] or {}
            table.insert(by_series[key], r)
        end
    end
    return function(path)
        local r = by_path[path]
        if not r then return true end
        local key = norm(r.series)
        if key == "" then return true end
        local index = tonumber(r.series_index)
        if not index then return false end
        for _i, other in ipairs(by_series[key]) do
            local before = tonumber(other.series_index)
            if before and before < index and status_of(other.path) ~= "complete" then return false end
        end
        return true
    end
end

return Series
