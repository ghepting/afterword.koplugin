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
        current = "/s3", finished = "/s3", library = lib, -- the end of book 3: it counts as finished although its status is not set yet
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
    T.eq(Suggest.series_text(g.books[1]), "Book 5 of Strike") -- said by the row label now, not a note
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
T.test("groups are shown in order: the series, what you were reading, the author, your collection, then recent", function()
    local order = {}
    for _, g in ipairs(Suggest.groups(ctx({ collection = { name = "C", paths = { "/new1" } }, per_group = 1 }))) do order[#order + 1] = g.id end
    T.eq(table.concat(order, ","), "series,started,author,collection,recent")
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

T.test("something different is offered with a book open, from a different corner of your library", function()
    local tagged = {
        { path = "/f1", title = "F1", keywords = "Fantasy\nRomantasy", language = "en" },
        { path = "/f2", title = "F2", keywords = "Fantasy\nRomantasy", language = "en" },
        { path = "/s1", title = "S1", keywords = "Science Fiction", language = "en" },
        { path = "/cur", title = "Now", keywords = "Fantasy\nRomantasy", language = "en" },
        { path = "/f3", title = "F3", keywords = "Fantasy\nRomantasy", language = "en" },
        { path = "/sf", title = "SF", keywords = "Science Fiction", language = "en" },
    }
    local st = { ["/f1"] = "complete", ["/f2"] = "complete", ["/s1"] = "complete", ["/cur"] = "reading" }
    local groups = Suggest.groups(ctx({ current = "/cur", library = tagged, history = {}, status_of = function(p) return st[p] or "new" end,
        rating_of = function() return 5 end, without = { next_in_series = true, more_by_author = true } }))
    T.eq(paths(find(groups, "for_you")), "/f3")
    T.eq(paths(find(groups, "different")), "/sf") -- one each, and never the same book twice
end)

T.test("something different with no book open is the opposite of the one you read last", function()
    local tagged = {
        { path = "/f1", title = "F1", keywords = "Fantasy\nRomantasy", language = "en" },
        { path = "/f2", title = "F2", keywords = "Fantasy\nRomantasy", language = "en" },
        { path = "/s1", title = "S1", keywords = "Science Fiction", language = "en" },
        { path = "/sf", title = "SF", keywords = "Science Fiction", language = "en" },
        { path = "/sf2", title = "SF2", keywords = "Science Fiction", language = "en" },
    }
    local st = { ["/f1"] = "complete", ["/f2"] = "complete", ["/s1"] = "complete" }
    local groups = Suggest.groups(ctx({ current = false, library = tagged, history = { "/f2", "/f1" }, status_of = function(p) return st[p] or "new" end,
        rating_of = function() return 5 end, without = { next_in_series = true, more_by_author = true } }))
    T.eq(paths(find(groups, "for_you")), "/sf")
    T.eq(paths(find(groups, "different")), "/sf2") -- /f2 was the last read (fantasy), so the cleanser is not fantasy
end)

T.test("books you started show how far through them you are", function()
    local g = find(Suggest.groups(ctx({ percent_of = function(p) return p == "/mid" and 0.376 or 0.002 end })), "started")
    for _, b in ipairs(g.books) do
        if b.path == "/mid" then T.eq(b.note, "38%") else T.eq(b.note, nil) end -- rounded; no note for 0.2%, which rounds to 0
    end
end)

T.test("something different skips past a book with no tags to the last one that has some", function()
    local tagged = {
        { path = "/f1", title = "F1", keywords = "Fantasy", language = "en" },
        { path = "/f2", title = "F2", keywords = "Fantasy", language = "en" },
        { path = "/s1", title = "S1", keywords = "Science Fiction", language = "en" },
        { path = "/bare", title = "Bare", language = "en" },
        { path = "/sf", title = "SF", keywords = "Science Fiction", language = "en" },
        { path = "/sf2", title = "SF2", keywords = "Science Fiction", language = "en" },
    }
    local st = { ["/f1"] = "complete", ["/f2"] = "complete", ["/s1"] = "complete", ["/bare"] = "reading" }
    local groups = Suggest.groups(ctx({ current = false, library = tagged, history = { "/bare", "/f2" }, status_of = function(p) return st[p] or "new" end,
        rating_of = function() return 5 end, without = { next_in_series = true, more_by_author = true } }))
    T.eq(paths(find(groups, "different")), "/sf2") -- /bare has no tags, so /f2 (fantasy) is what to be the opposite of
end)

T.test("a book in a series says which book it is: Book 3 of the series", function()
    T.eq(Suggest.series_text({ series = "Strike", series_index = 5 }), "Book 5 of Strike")
    T.eq(Suggest.series_text({ series = "Strike", series_index = 2.5 }), "Book 2.5 of Strike")
    T.eq(Suggest.series_text({ series = "Strike" }), "Strike") -- a series with no number
    T.eq(Suggest.series_text({ title = "Standalone" }), nil)
    T.eq(Suggest.series_text({ series = "" }), nil)
end)

T.test("the books offered carry their series, so the list can say where they belong", function()
    local g = find(Suggest.groups(ctx()), "series")
    T.eq(g.books[1].series, "Strike")
    T.eq(g.books[1].series_index, 5)
    T.eq(g.books[1].note, nil) -- the label says it; the note no longer repeats it
end)

T.test("nothing new is offered out of order in a series: only the next one you have not read", function()
    -- /s3 just finished, /s4 finished: /s5 is next, so /s6 must not be offered anywhere
    local groups = Suggest.groups(ctx({ per_group = 10 }))
    for _, g in ipairs(groups) do
        for _, b in ipairs(g.books) do T.eq(b.path ~= "/s6", true) end
    end
    T.eq(paths(find(groups, "series")), "/s5")
end)

T.test("a later book of a series is offered once the earlier ones are finished", function()
    status["/s3"], status["/s5"] = "complete", "complete" -- 3, 4 and 5 are all finished now
    local groups = Suggest.groups(ctx({ current = "/s5", finished = "/s5", per_group = 10 }))
    status["/s3"], status["/s5"] = "reading", nil
    T.eq(paths(find(groups, "series")), "/s6")
end)

T.test("a book half read blocks the later ones, but is itself offered under started", function()
    status["/s5"] = "reading"
    local groups = Suggest.groups(ctx({ current = "/new1", finished = "/new1", per_group = 10, history = { "/s5" } }))
    status["/s5"] = nil
    for _, g in ipairs(groups) do
        if g.id ~= "started" then
            for _, b in ipairs(g.books) do T.eq(b.path ~= "/s6", true) end
        end
    end
    T.eq(paths(find(groups, "started")), "/s5")
end)

T.test("a series book with no number is never offered as something new", function()
    local l = { { path = "/u", title = "U", authors = "A", series = "Loose" }, { path = "/n", title = "N", authors = "B" } }
    local groups = Suggest.groups({ current = "/x", library = l, status_of = function() return "new" end, modified_of = function() return 0 end })
    T.eq(paths(find(groups, "recent")), "/n")
end)

T.test("the line under a title says the author and which book of the series, whichever it has", function()
    T.eq(Suggest.byline({ authors = "Colleen Hoover", series = "Verity", series_index = 1 }), "Colleen Hoover \u{00B7} Book 1 of Verity")
    T.eq(Suggest.byline({ authors = "A. One\nB. Two" }), "A. One, B. Two")
    T.eq(Suggest.byline({ series = "Strike", series_index = 5 }), "Book 5 of Strike")
    T.eq(Suggest.byline({ title = "Nothing known" }), nil)
    T.eq(Suggest.byline({ authors = "  " }), nil)
end)

T.test("a group holds five books by default, a shelf of covers", function()
    local many = {}
    for i = 1, 8 do many[#many + 1] = { path = "/n" .. i, title = "N" .. i, authors = "Someone" .. i } end
    local groups = Suggest.groups({ current = "/x", library = many, status_of = function() return "new" end, modified_of = function(p) return tonumber(p:match("%d+")) end })
    T.eq(#find(groups, "recent").books, 5)
end)

T.test("a book carries its tags, language and description for the detail sheet", function()
    local lib2 = { { path = "/a", title = "A", authors = "X", keywords = "Fantasy\n Romance \n", language = "en", description = "About A." } }
    local g = find(Suggest.groups({ current = "/x", library = lib2, status_of = function() return "new" end, modified_of = function() return 0 end }), "recent")
    T.eq(table.concat(g.books[1].tags, "|"), "Fantasy|Romance")
    T.eq(g.books[1].language, "en")
    T.eq(g.books[1].description, "About A.")
end)

T.test("the picks say why: the liked books behind them, and what they are different from", function()
    local lib3 = {
        { path = "/f1", title = "Lightlark", keywords = "Fantasy\nRomantasy", language = "en" },
        { path = "/f2", title = "Crowntide", keywords = "Fantasy\nRomantasy", language = "en" },
        { path = "/s1", title = "Dune", keywords = "Science Fiction", language = "en" },
        { path = "/cur", title = "Now", keywords = "Fantasy\nRomantasy", language = "en" },
        { path = "/f3", title = "F3", keywords = "Fantasy\nRomantasy", language = "en" },
        { path = "/sf", title = "SF", keywords = "Science Fiction", language = "en" },
    }
    local st = { ["/f1"] = "complete", ["/f2"] = "complete", ["/s1"] = "complete", ["/cur"] = "reading" }
    local groups = Suggest.groups({ current = "/cur", library = lib3, status_of = function(p) return st[p] or "new" end,
        rating_of = function(p) return st[p] and 5 or 0 end, modified_of = function() return 0 end, without = { next_in_series = true, more_by_author = true } })
    local pick, other = find(groups, "for_you").books[1], find(groups, "different").books[1]
    T.eq(pick.path, "/f3")
    T.eq(table.concat(pick.because, "|"), "Crowntide|Lightlark") -- the two that share most with it (equal, so by title)
    T.eq(other.path, "/sf")
    T.eq(other.against, "Now")
    T.eq(table.concat(other.because, "|"), "Dune")
end)

T.test("books you started carry how far through them you are as a number", function()
    local g = find(Suggest.groups(ctx({ percent_of = function(p) return p == "/mid" and 0.376 or 0 end })), "started")
    for _, b in ipairs(g.books) do
        if b.path == "/mid" then T.eq(b.percent, 38) end
    end
end)

T.test("a pick says why: the books you liked and what they share, in a short line and a long one", function()
    local short, long = Suggest.explain("picked_for_you", { because = { "Lightlark", "Crowntide" }, matched = { "Fantasy", "Romance" } }, {})
    T.eq(short, "Because you liked Lightlark and Crowntide")
    T.eq(long, "You liked Lightlark and Crowntide. They share Fantasy and Romance with this book.")
    short, long = Suggest.explain("picked_for_you", { because = { "Lightlark" } }, {})
    T.eq(short, "Because you liked Lightlark")
    T.eq(long, "Because you liked Lightlark.")
end)

T.test("something different says what it is different from, and what you like in it", function()
    local short, long = Suggest.explain("something_different", { against = "Now", matched = { "Romance" }, tags = { "Romance" } }, {})
    T.eq(short, "Nothing in common with Now, but you like Romance")
    T.eq(long, "Nothing in common with Now, but you like Romance.")
end)

T.test("the other groups explain themselves in the detail sheet only", function()
    local short, long = Suggest.explain("next_in_series", { series = "Strike" }, {})
    T.eq(short, nil)
    T.eq(long, "The next book in Strike.")
    short, long = Suggest.explain("started", { percent = 38 }, {})
    T.eq(long, "You are 38% through it.")
    short, long = Suggest.explain("collection", {}, { collection_name = "To Be Read" })
    T.eq(long, "From your collection To Be Read.")
    T.eq(select(2, Suggest.explain("started", { percent = 0 }, {})), nil)
    T.eq(select(2, Suggest.explain("more_by_author", {}, {})), nil)
end)

T.done()
