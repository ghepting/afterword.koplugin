local T = dofile((debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$") or ".") .. "/helper.lua")
local Suggest = require("afterword/suggest")

print("suggest")

local function bk(path, title, authors, series, index)
    return { path = path, title = title, authors = authors, series = series, series_index = index }
end
local lib = {
    bk("/s3", "Career of Evil", "Robert Galbraith", "Strike", 3),
    bk("/s4", "Lethal White", "Robert Galbraith", "Strike", 4),
    bk("/s5", "Troubled Blood", "Robert Galbraith", "Strike", 5),
    bk("/s6", "The Ink Black Heart", "Robert Galbraith", "Strike", 6),
    bk("/hp1", "Harry Potter 1", "J. K. Rowling\nRobert Galbraith", "Potter", 1),
    bk("/solo", "A Standalone", "Robert Galbraith"),
    bk("/new1", "Fresh One", "Someone"),
    bk("/new2", "Fresh Two", "Someone Else"),
    bk("/new3", "Fresh Three", "A Third"),
    bk("/mid", "Halfway Book", "Another"),
    bk("/done", "Already Read", "Another"),
}
local status = { ["/s4"] = "complete", ["/mid"] = "reading", ["/done"] = "complete", ["/s3"] = "reading" }
local when = { ["/new1"] = 100, ["/new2"] = 300, ["/new3"] = 200, ["/solo"] = 50, ["/hp1"] = 60, ["/s5"] = 10, ["/s6"] = 20 }
local function ctx(extra)
    local c = {
        current = "/s3", library = lib,
        status_of = function(p) return status[p] or "new" end,
        modified_of = function(p) return when[p] or 0 end,
        history = { "/mid", "/s3", "/done" },
    }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end
local function find(groups, id) for _, g in ipairs(groups) do if g.id == id then return g end end end
local function paths(g) local o = {}; for i, b in ipairs(g and g.books or {}) do o[i] = b.path end; return table.concat(o, " ") end

T.test("the next book in the series is the first one you have not finished", function()
    -- /s4 is finished, so after /s3 the next is /s5
    local g = find(Suggest.groups(ctx()), "series")
    T.eq(paths(g), "/s5")
    T.eq(g.books[1].note, "Strike #5")
end)
T.test("more by this author: books you have not started, series together, others last", function()
    local g = find(Suggest.groups(ctx()), "author")
    -- The Strike books are the series group's business, not "more by". The author's other books you have not started: series by
    -- name, then the standalone last.
    T.eq(paths(g), "/hp1 /solo")
end)
T.test("more by the author leaves out the book's own series", function()
    local g = find(Suggest.groups(ctx()), "author")
    for _, b in ipairs(g.books) do T.eq(b.path:match("^/s%d") == nil, true, b.path .. " is in the series") end
end)
T.test("a book appears once, in the first group that wants it", function()
    local seen = {}
    for _, g in ipairs(Suggest.groups(ctx())) do
        for _, b in ipairs(g.books) do
            T.eq(seen[b.path], nil, b.path .. " appears twice")
            seen[b.path] = true
        end
    end
end)
T.test("the current book and finished books are never offered", function()
    for _, g in ipairs(Suggest.groups(ctx())) do
        for _, b in ipairs(g.books) do
            T.eq(b.path == "/s3", false)
            T.eq(status[b.path] == "complete", false, b.path)
        end
    end
end)
T.test("recently added: the newest books you have not started", function()
    T.eq(paths(find(Suggest.groups(ctx()), "recent")), "/new2 /new3 /new1")
end)
T.test("started: books you opened and not finished, most recent first", function()
    T.eq(paths(find(Suggest.groups(ctx()), "started")), "/mid")
end)
T.test("a chosen collection comes in its own order, without finished books", function()
    local g = find(Suggest.groups(ctx({ collection = { name = "To read", paths = { "/done", "/new1", "/mid", "/new3" } } })), "collection")
    T.eq(paths(g), "/new1 /mid /new3")
    T.eq(g.collection_name, "To read")
end)
T.test("groups come in order: series, author, collection, recent, started", function()
    local order = {}
    for _, g in ipairs(Suggest.groups(ctx({ collection = { name = "C", paths = { "/new1" } }, per_group = 1 }))) do order[#order + 1] = g.id end
    T.eq(table.concat(order, ","), "series,author,collection,recent,started")
end)
T.test("a group with nothing to offer is left out", function()
    local c = ctx({ library = { bk("/only", "Only", "Nobody") }, current = "/only", history = {} })
    T.eq(#Suggest.groups(c), 0)
end)
T.test("each group holds at most per_group books", function()
    for _, g in ipairs(Suggest.groups(ctx({ per_group = 2 }))) do T.eq(#g.books <= 2, true) end
end)
T.test("a book with no author gets no author group, and a missing library gives no groups", function()
    local c = ctx({ library = { bk("/a", "A"), bk("/b", "B") }, current = "/a", history = {} })
    T.eq(find(Suggest.groups(c), "author"), nil)
    T.eq(#Suggest.groups({ current = "/x" }), 0)
end)

T.test("one book picked for your taste is offered, with the tags that matched", function()
    local tagged = {
        { path = "/a", title = "A", keywords = "Fantasy\nRomantasy", language = "en" },
        { path = "/b", title = "B", keywords = "Fantasy\nRomantasy", language = "en" },
        { path = "/c", title = "C", keywords = "Fantasy\nRomantasy", language = "en" },
        { path = "/d", title = "D", keywords = "Cooking", language = "en" },
    }
    local st = { ["/a"] = "complete", ["/b"] = "complete" }
    local g = find(Suggest.groups(ctx({ current = "/a", library = tagged, history = {}, status_of = function(p) return st[p] or "new" end,
        rating_of = function() return 5 end })), "for_you")
    T.eq(paths(g), "/c")
    T.eq(g.books[1].note, "Fantasy \u{00B7} Romantasy") -- equally common, so alphabetical
end)

T.test("no taste pick without ratings to go on, and none when the caller does not ask for it", function()
    T.eq(find(Suggest.groups(ctx()), "for_you"), nil)
end)

T.test("asked without the groups about the open book, they are left out and a book is still never offered twice", function()
    local groups = Suggest.groups(ctx({ without = { next_in_series = true, more_by_author = true } }))
    T.eq(find(groups, "series"), nil)
    T.eq(find(groups, "author"), nil)
    T.eq(paths(find(groups, "recent")) ~= "", true)
end)

T.test("with no book open (the file browser) it still suggests", function()
    local groups = Suggest.groups(ctx({ current = nil, without = { next_in_series = true, more_by_author = true } }))
    T.eq(paths(find(groups, "started")) ~= "", true)
end)

T.done()
