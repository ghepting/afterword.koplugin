local T = dofile((debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$") or ".") .. "/helper.lua")
package.preload["datastorage"] = function() return { getSettingsDir = function() return "/tmp" end } end
local Hardcover = require("afterword/hardcover")

print("hardcover")

local function tmp(content)
    local path = os.tmpname()
    if content then local f = io.open(path, "w"); f:write(content); f:close() end
    return path
end

T.test("the token is read from the sources file, with or without Bearer, and a missing file or token gives nil", function()
    T.eq(Hardcover.read_token(tmp('return { hardcover_token = "abc.def" }')), "abc.def")
    T.eq(Hardcover.read_token(tmp('return { hardcover_token = "Bearer abc.def " }')), "abc.def")
    T.eq(Hardcover.read_token(tmp('return { hardcover_token = "   " }')), nil)
    T.eq(Hardcover.read_token(tmp("return {}")), nil)
    T.eq(Hardcover.read_token("/tmp/does-not-exist-afterword"), nil)
    T.eq(Hardcover.read_token(tmp("this is not lua")), nil)
end)
T.test("the sources file's code is not run with the plugin's powers", function()
    local marker = os.tmpname()
    os.remove(marker)
    local path = tmp('local f = io.open("' .. marker .. '", "w"); if f then f:write("ran") f:close() end return { hardcover_token = "x" }')
    Hardcover.read_token(path)
    T.eq(io.open(marker), nil)
end)
T.test("forgetting the token removes the file when nothing else is in it, and keeps the rest when there is", function()
    local alone = tmp('return { hardcover_token = "abc" }')
    Hardcover.forget(alone)
    T.eq(io.open(alone), nil)
    local shared = tmp('return { hardcover_token = "abc", other = "keep" }')
    Hardcover.forget(shared)
    T.eq(Hardcover.read_token(shared), nil)
    local f = io.open(shared); local text = f:read("*a"); f:close()
    T.eq(text:find("keep", 1, true) ~= nil, true)
end)

T.test("a pasted token is kept, cleaned, beside whatever else the file holds, and an empty one is refused", function()
    local path = tmp('return { other = "keep" }')
    T.eq(Hardcover.write_token(path, "  Bearer abc.def\n"), true)
    T.eq(Hardcover.read_token(path), "abc.def")
    local f = io.open(path); local text = f:read("*a"); f:close()
    T.eq(text:find("keep", 1, true) ~= nil, true)
    T.eq(Hardcover.write_token(path, "   "), nil)
    T.eq(Hardcover.read_token(path), "abc.def")
    local fresh = os.tmpname(); os.remove(fresh)
    T.eq(Hardcover.write_token(fresh, "tok"), true)
    T.eq(Hardcover.read_token(fresh), "tok")
    T.eq(Hardcover.write_token("/nonexistent-dir/x.lua", "tok"), nil)
end)

local ANSWER = { data = { me = { { user_books = {
    { book = { title = "The Will of the Many", contributions = { { author = { name = "James Islington" } } }, book_series = { { position = 1, series = { name = "Hierarchy" } } } } },
    { book = { title = "Project Hail Mary", contributions = { { author = { name = "Andy Weir" } } }, book_series = {} } },
    { book = { title = "" } },
} } } } }

T.test("a want-to-read answer becomes a list: title, first author, series and place", function()
    local list = Hardcover.books_from(ANSWER)
    T.eq(list.source, "hardcover")
    T.eq(#list.books, 2)
    T.eq(list.books[1].title, "The Will of the Many")
    T.eq(list.books[1].author, "James Islington")
    T.eq(list.books[1].series, "Hierarchy")
    T.eq(list.books[1].series_index, 1)
    T.eq(list.books[2].series, nil)
end)
T.test("me as a single object, and an empty shelf, are fine", function()
    local list = Hardcover.books_from({ data = { me = { user_books = {} } } })
    T.eq(#list.books, 0)
end)
T.test("an error from Hardcover is told apart: a bad token, or anything else", function()
    local _l, kind, why = Hardcover.books_from({ errors = { { message = "Unable to verify JWT" } } })
    T.eq(kind, "token")
    local _l2, kind2, why2 = Hardcover.books_from({ errors = { { message = "field 'x' not found" } } })
    T.eq(kind2, "api")
    T.eq(why2, "field 'x' not found")
    local _l3, kind3 = Hardcover.books_from("nonsense")
    T.eq(kind3, "answer")
    local _l4, kind4 = Hardcover.books_from({ data = {} })
    T.eq(kind4, "answer")
end)

local function io_with(status, text)
    local seen = {}
    return {
        seen = seen,
        encode = function(v) seen.encoded = v; return "BODY" end,
        decode = function(t) if t == "bad" then error("no") end return ANSWER end,
        post = function(url, headers, body) seen.url, seen.headers, seen.body = url, headers, body; return status, text end,
    }
end

T.test("fetching asks Hardcover's address with the token as a bearer header and the want-to-read query", function()
    local io = io_with(200, "ok")
    local list = Hardcover.fetch("Bearer sekret", io)
    T.eq(#list.books, 2)
    T.eq(io.seen.url, "https://api.hardcover.app/v1/graphql")
    T.eq(io.seen.headers.Authorization, "Bearer sekret")
    T.eq(io.seen.encoded.query:find("status_id", 1, true) ~= nil, true)
end)
T.test("a refused token, no answer and an unreadable answer are told apart, and none of them includes the token", function()
    local _a, k1 = Hardcover.fetch("sekret", io_with(401, ""))
    T.eq(k1, "token")
    local _b, k2, d2 = Hardcover.fetch("sekret", io_with(nil, "timeout"))
    T.eq(k2, "network")
    local _c, k3 = Hardcover.fetch("sekret", io_with(200, "bad"))
    T.eq(k3, "answer")
    local _d, k4 = Hardcover.fetch("", io_with(200, "ok"))
    T.eq(k4, "token")
    for _i, kind in ipairs({ "token", "network", "api", "answer" }) do
        T.eq(Hardcover.explain(kind, "x"):find("sekret", 1, true), nil)
    end
end)

T.test("a cover address in the answer is kept only when it is an https address on a Hardcover host", function()
    local function answer(url)
        return { data = { me = { { user_books = { { book = { title = "A", image = { url = url }, contributions = {}, book_series = {} } } } } } } }
    end
    T.eq(Hardcover.books_from(answer("https://assets.hardcover.app/books/1/cover.jpg")).books[1].cover_url, "https://assets.hardcover.app/books/1/cover.jpg")
    T.eq(Hardcover.books_from(answer("http://assets.hardcover.app/x.jpg")).books[1].cover_url, nil)
    T.eq(Hardcover.books_from(answer("https://evil.example.com/hardcover.app/x.jpg")).books[1].cover_url, nil)
    T.eq(Hardcover.books_from(answer("https://hardcover.app.evil.com/x.jpg")).books[1].cover_url, nil)
end)
T.test("a field Hardcover does not know is retried without covers, and a refused token is not retried", function()
    local asked = {}
    local function io_for(fn)
        return { encode = function(v) return v.query end, decode = function(t) return t end,
            post = function(url, headers, body) asked[#asked + 1] = body; return fn(body) end }
    end
    local with_images = Hardcover.fetch("tok", io_for(function(body)
        if body:find("image", 1, true) then return 200, { errors = { { message = "field 'image' not found in type: 'books'" } } } end
        return 200, ANSWER
    end))
    T.eq(#with_images.books, 2)
    T.eq(with_images.covers_unavailable, true) -- said, so the empty frames are not a mystery
    T.eq(#asked, 2)
    asked = {}
    local _l, kind = Hardcover.fetch("tok", io_for(function() return 401, "" end))
    T.eq(kind, "token")
    T.eq(#asked, 1)
end)
T.test("covers are fetched once each, never twice, only from safe addresses, and not more than the limit", function()
    local list = { books = {
        { title = "One", author = "A B", cover_url = "https://assets.hardcover.app/1.jpg" },
        { title = "Two", author = "C D", cover_url = "https://assets.hardcover.app/2.jpg" },
        { title = "Three", author = "E F", cover_url = "http://elsewhere.example.com/3.jpg" },
        { title = "Four", author = "G H" },
    } }
    local have, fetched = {}, {}
    local io = {
        exists = function(path) return have[path] end,
        get = function(url) fetched[#fetched + 1] = url; return 200, "JPEGDATA" end,
        write = function(path, bytes) have[path] = bytes; return true end,
    }
    T.eq(Hardcover.fetch_covers(list, "/dir", io), 2)
    T.eq(#fetched, 2)
    T.eq(Hardcover.fetch_covers(list, "/dir", io), 0) -- already there
    T.eq(#fetched, 2)
    local Wanted = require("afterword/wanted")
    T.eq(have["/dir/" .. Wanted.cover_name(list.books[1])], "JPEGDATA")
end)
