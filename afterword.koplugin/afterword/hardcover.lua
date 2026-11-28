-- Reading your want-to-read list from Hardcover. Nothing here runs unless a token has been put in the sources file and someone taps
-- "Sync now". The token is read from a file on the device, never typed, never shown and never put in a message.
--
--   Hardcover.read_token(path)  -> the token, or nil when there is no file or no token in it
--   Hardcover.write_token(path, token)  keeps a token a person pasted in (true, or nil when it is empty or the file cannot be written)
--   Hardcover.forget(path)      removes the token (the file goes when nothing else is in it)
--   Hardcover.books_from(answer) -> { source = "hardcover", books = { { title, author, series, series_index }, ... } } or nil, kind, detail
--   Hardcover.fetch(token, io)  -> the same, asking Hardcover through io.post(url, headers, body) -> status, text, and io.encode / io.decode
--   Hardcover.explain(kind, detail) -> a sentence for the person
--
-- `kind` is "token" (not accepted), "network" (no answer), "api" (Hardcover reported an error), or "answer" (not what was expected).
local Hardcover = {
    URL = "https://api.hardcover.app/v1/graphql",
    FILE = "afterword_sources.lua", -- in KOReader's settings folder: return { hardcover_token = "..." }
}
local _ = require("gettext")
local T = require("ffi/util").template

-- The user's books on the Want to read shelf (status 1), newest first. With the cover's address first; Hardcover's answer to a field it does
-- not know is an error, so a sync that fails on it is asked again without (see Hardcover.fetch).
local function query(image)
    return "query { me { user_books(where: {status_id: {_eq: 1}}, order_by: {date_added: desc}, limit: 500) "
        .. "{ book { title " .. (image and "image { url } " or "") .. "contributions { author { name } } book_series { position series { name } } } } } }"
end
Hardcover.QUERY = query(false)
Hardcover.QUERY_WITH_IMAGES = query(true)

-- A cover is fetched only from Hardcover's own hosts, over https: the address comes from an answer, not from the person.
function Hardcover.safe_cover_url(url)
    return type(url) == "string" and url:match("^https://[%w%.%-]*hardcover%.app/") ~= nil
end

function Hardcover.path()
    return require("datastorage"):getSettingsDir() .. "/" .. Hardcover.FILE
end

-- The file's table, read without running anything it could contain: its code gets an empty environment.
local function load_file(path)
    local chunk = loadfile(path)
    if not chunk then return nil end
    if setfenv then setfenv(chunk, {}) end
    local ok, value = pcall(chunk)
    return ok and type(value) == "table" and value or nil
end

-- What Hardcover shows as the token starts with "Bearer ": either way round is fine.
local function clean(token)
    token = tostring(token or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^[Bb]earer%s+", "")
    return token ~= "" and token or nil
end

function Hardcover.read_token(path)
    local value = load_file(path)
    return value and type(value.hardcover_token) == "string" and clean(value.hardcover_token) or nil
end

-- Writes the table `value` (strings, numbers and booleans only) as a Lua file.
local function save_file(path, value)
    local lines = { "return {" }
    for key, v in pairs(value) do
        if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
            lines[#lines + 1] = string.format("    [%q] = %s,", key, type(v) == "string" and string.format("%q", v) or tostring(v))
        end
    end
    lines[#lines + 1] = "}"
    local handle = io.open(path, "w")
    if not handle then return false end
    handle:write(table.concat(lines, "\n"), "\n")
    handle:close()
    return true
end

function Hardcover.write_token(path, token)
    token = clean(token)
    if not token then return nil end
    local value = load_file(path) or {}
    value.hardcover_token = token
    return save_file(path, value) or nil
end

function Hardcover.forget(path)
    local value = load_file(path)
    if not value then return end
    value.hardcover_token = nil
    if next(value) == nil then os.remove(path) else save_file(path, value) end
end

local function first(list) return type(list) == "table" and list[1] or nil end

local function looks_like_token_error(message)
    message = tostring(message or ""):lower()
    return message:find("jwt", 1, true) or message:find("token", 1, true) or message:find("authenticat", 1, true)
        or message:find("unauthor", 1, true) or message:find("verify", 1, true)
end

function Hardcover.books_from(answer)
    if type(answer) ~= "table" then return nil, "answer" end
    local err = first(answer.errors)
    if err then
        local message = type(err) == "table" and err.message or tostring(err)
        return nil, looks_like_token_error(message) and "token" or "api", message
    end
    local me = answer.data and answer.data.me
    if type(me) == "table" and me.user_books == nil then me = me[1] end -- `me` is a list of one
    local shelf = type(me) == "table" and me.user_books
    if type(shelf) ~= "table" then return nil, "answer" end
    local books = {}
    for _i, entry in ipairs(shelf) do
        local book = type(entry) == "table" and entry.book
        if type(book) == "table" and type(book.title) == "string" and book.title ~= "" then
            local contribution = first(book.contributions)
            local author = contribution and contribution.author and contribution.author.name
            local membership = first(book.book_series)
            local series = membership and membership.series and membership.series.name
            local image = type(book.image) == "table" and book.image.url or nil
            books[#books + 1] = {
                title = book.title, author = type(author) == "string" and author or "",
                cover_url = Hardcover.safe_cover_url(image) and image or nil,
                series = type(series) == "string" and series ~= "" and series or nil,
                series_index = series and tonumber(membership.position) or nil,
            }
        end
    end
    return { source = "hardcover", books = books }
end

local function ask(token, io, text)
    local body = io.encode { query = text }
    local status, answer = io.post(Hardcover.URL, { ["Content-Type"] = "application/json", Authorization = "Bearer " .. token }, body)
    if status == 401 or status == 403 then return nil, "token" end
    if status ~= 200 then return nil, "network", tostring(status or "no answer") end
    local ok, decoded = pcall(io.decode, answer)
    if not ok then return nil, "answer" end
    return Hardcover.books_from(decoded)
end

function Hardcover.fetch(token, io)
    token = clean(token)
    if not token then return nil, "token" end
    local list, kind, detail = ask(token, io, Hardcover.QUERY_WITH_IMAGES)
    if not list and kind == "api" then -- no cover field here: the shelf without covers is still the shelf
        list, kind, detail = ask(token, io, Hardcover.QUERY)
        if list then list.covers_unavailable = true end
    end
    return list, kind, detail
end

-- The real network: KOReader's socket.http and json. Blocks for up to the timeouts.
function Hardcover.fetch_now(token)
    return Hardcover.fetch(token, {
        encode = function(value) return require("json").encode(value) end,
        decode = function(text) return require("json").decode(text) end,
        post = function(url, headers, body)
            local http = require("socket.http")
            local ltn12 = require("ltn12")
            local socket = require("socket")
            local socketutil = require("socketutil")
            local chunks = {}
            headers["Content-Length"] = tostring(#body)
            socketutil:set_timeout(10, 30)
            local code, status = socket.skip(1, http.request {
                url = url, method = "POST", headers = headers, source = ltn12.source.string(body), sink = ltn12.sink.table(chunks),
            })
            socketutil:reset_timeout()
            if type(code) ~= "number" then return nil, tostring(status or code) end
            return code, table.concat(chunks)
        end,
    })
end

Hardcover.MAX_COVERS = 60 -- fetched in one sync

-- Fetches the covers of `list` that are not in `dir` yet: io.exists(path), io.get(url) -> status, bytes, and io.write(path, bytes) -> true.
-- Returns how many were fetched. A cover that cannot be had is skipped; the book still shows, with an empty frame.
function Hardcover.fetch_covers(list, dir, io)
    local Wanted = require("afterword/wanted")
    local got = 0
    for _i, book in ipairs(list.books) do
        if got >= Hardcover.MAX_COVERS then break end
        if Hardcover.safe_cover_url(book.cover_url) then
            local path = dir .. "/" .. Wanted.cover_name(book)
            if not io.exists(path) then
                local status, bytes = io.get(book.cover_url)
                if status == 200 and type(bytes) == "string" and #bytes > 0 and #bytes < 3000000 and io.write(path, bytes) then got = got + 1 end
            end
        end
    end
    return got
end

function Hardcover.cover_dir()
    return require("datastorage"):getDataDir() .. "/cache/afterword/covers"
end

-- The real thing: makes the folder, fetches with socket.http. Blocks for up to the timeouts, a cover at a time.
function Hardcover.fetch_covers_now(list)
    local lfs = require("libs/libkoreader-lfs")
    local dir = Hardcover.cover_dir()
    local base = require("datastorage"):getDataDir() .. "/cache"
    lfs.mkdir(base); lfs.mkdir(base .. "/afterword"); lfs.mkdir(dir)
    return Hardcover.fetch_covers(list, dir, {
        exists = function(path) return lfs.attributes(path, "mode") == "file" end,
        get = function(url)
            local http = require("socket.http")
            local ltn12 = require("ltn12")
            local socket = require("socket")
            local socketutil = require("socketutil")
            local chunks = {}
            socketutil:set_timeout(10, 30)
            local code = socket.skip(1, http.request { url = url, method = "GET", sink = ltn12.sink.table(chunks) })
            socketutil:reset_timeout()
            return type(code) == "number" and code or nil, table.concat(chunks)
        end,
        write = function(path, bytes)
            local handle = io.open(path, "wb")
            if not handle then return false end
            handle:write(bytes)
            handle:close()
            return true
        end,
    })
end

-- Deletes the covers kept for Hardcover's list (when it is disconnected).
function Hardcover.forget_covers()
    local lfs = require("libs/libkoreader-lfs")
    local dir = Hardcover.cover_dir()
    if lfs.attributes(dir, "mode") ~= "directory" then return end
    for name in lfs.dir(dir) do
        if name:match("%.jpg$") then os.remove(dir .. "/" .. name) end
    end
end

function Hardcover.explain(kind, detail)
    if kind == "token" then return _("Hardcover did not accept the token. Check that it was copied whole and has the permissions read:library, read:catalog and read:me:content.") end
    if kind == "network" then return T(_("Could not reach Hardcover (%1). Check the connection and try again."), detail or "?") end
    if kind == "api" then return T(_("Hardcover reported a problem: %1"), detail or "?") end
    return _("Hardcover's answer was not what Afterword expected.")
end

return Hardcover
