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

return Series
