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
