-- Reads what the screen needs from KOReader's two databases: the statistics (how the book went) and the book-info cache (the
-- library, for the series). `conn` is an open SQ3 connection (db_conn); everything returned is plain data for series.lua and
-- stats.lua. Values put into SQL are a hex checksum or a whole number, never free text.
local Store = {}

local function rows(conn, sql)
    local ok, res, n = pcall(function() return conn:exec(sql) end)
    if not ok or not res then return {}, 0 end
    return res, tonumber(n) or (res[1] and #res[1]) or 0
end

-- The statistics keep a book by its checksum (the partial MD5 KOReader files it under).
local function hex(s) return tostring(s or ""):match("^%x+$") end

-- book_stats(conn, md5, finished) -> { read_seconds, read_pages, first_read, finished } or nil when the book is not in the
-- statistics. `finished` is the time it was finished (now, at the end of the book).
function Store.book_stats(conn, md5, finished)
    md5 = hex(md5)
    if not md5 then return nil end
    local res, n = rows(conn, "SELECT id, total_read_time, total_read_pages FROM book WHERE md5 = '" .. md5 .. "' LIMIT 1;")
    if n < 1 then return nil end
    local id = tonumber(res[1][1])
    if not id then return nil end
    local first = rows(conn, "SELECT MIN(start_time) FROM page_stat_data WHERE id_book = " .. id .. ";")
    return {
        read_seconds = tonumber(res[2][1]),
        read_pages = tonumber(res[3][1]),
        first_read = first[1] and tonumber(first[1][1]) or nil,
        finished = finished,
    }
end

-- library(conn) -> { { path, series, series_index, title }, ... } for every book KOReader has details of that is in a series.
function Store.library(conn)
    local res, n = rows(conn,
        "SELECT directory, filename, title, series, series_index FROM bookinfo "
        .. "WHERE has_meta = 'Y' AND ignore_meta IS NOT 'Y' AND unsupported IS NULL AND series IS NOT NULL AND series != '';")
    local out = {}
    for i = 1, n do
        out[#out + 1] = { path = res[1][i] .. res[2][i], title = res[3][i], series = res[4][i], series_index = tonumber(res[5][i]) }
    end
    return out
end

-- books(conn) -> { { path, title, authors, series, series_index, keywords, language }, ... } every book KOReader has details of
-- (the whole library, series or not), for suggesting what to read next. keywords is the book's tags, one per line.
function Store.books(conn)
    local res, n = rows(conn,
        "SELECT directory, filename, title, authors, series, series_index, keywords, language FROM bookinfo "
        .. "WHERE has_meta = 'Y' AND ignore_meta IS NOT 'Y' AND unsupported IS NULL;")
    local out = {}
    for i = 1, n do
        local series = res[5][i]
        out[#out + 1] = {
            path = res[1][i] .. res[2][i], title = res[3][i], authors = res[4][i],
            series = (series and series ~= "") and series or nil, series_index = tonumber(res[6][i]),
            keywords = res[7][i], language = res[8][i],
        }
    end
    return out
end

return Store
