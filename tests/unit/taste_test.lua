local T = dofile((debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$") or ".") .. "/helper.lua")
local Taste = require("afterword/taste")

print("taste")

local function bk(path, tags, language) return { path = path, keywords = table.concat(tags, "\n"), language = language } end
local lib = {
    bk("/liked1", { "Fantasy", "Romantasy", "Young Adult" }, "en"),
    bk("/liked2", { "Fantasy", "Romantasy" }, "en"),
    bk("/disliked", { "Thriller", "Crime" }, "en"),
    bk("/fit", { "Fantasy", "Romantasy" }, "en"),
    bk("/fitless", { "Fantasy", "Cooking", "History", "Travel" }, "en"),
    bk("/crime", { "Thriller", "Crime" }, "en"),
    bk("/foreign", { "Fantasy", "Romantasy" }, "de"),
    bk("/untagged", {}, "en"),
}
local status = { ["/liked1"] = "complete", ["/liked2"] = "complete", ["/disliked"] = "complete" }
local rating = { ["/liked1"] = 5, ["/liked2"] = 4, ["/disliked"] = 1 }
local function ctx(extra)
    local c = { library = lib, status_of = function(p) return status[p] or "new" end, rating_of = function(p) return rating[p] or 0 end }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

T.test("offers the unread book whose tags match what you rated highly, and says which", function()
    local pick = Taste.pick(ctx())
    T.eq(pick.path, "/fit")
    T.eq(table.concat(pick.tags, "+"), "Romantasy+Fantasy") -- the rarer tag first
end)

T.test("a book matching tags you rated badly is not offered", function()
    local pick = Taste.pick(ctx())
    T.eq(pick.path ~= "/crime", true)
end)

T.test("a long tag list does not beat a closer fit", function()
    T.eq(Taste.pick(ctx()).path, "/fit") -- /fitless shares only Fantasy, and carries four tags
end)

T.test("books in another language than the one you read are left out", function()
    local pick = Taste.pick(ctx({ skip = { ["/fit"] = true } }))
    T.eq(pick.path ~= "/foreign", true)
end)

T.test("never offers a book you have started, finished, or were told to skip", function()
    status["/fit"] = "reading"
    local pick = Taste.pick(ctx())
    status["/fit"] = nil
    T.eq(pick.path ~= "/fit", true)
    T.eq(Taste.pick(ctx({ skip = { ["/fit"] = true, ["/fitless"] = true } })) == nil, true)
end)

T.test("too little to go on: one liked book is not enough to guess from", function()
    local only = { library = { lib[1], lib[4] }, status_of = function(p) return p == "/liked1" and "complete" or "new" end,
        rating_of = function(p) return p == "/liked1" and 5 or 0 end }
    T.eq(Taste.pick(only) == nil, true)
end)

T.test("finishing a book without rating it counts a little for its tags", function()
    rating["/liked1"], rating["/liked2"] = nil, nil
    local pick = Taste.pick(ctx())
    rating["/liked1"], rating["/liked2"] = 5, 4
    T.eq(pick.path, "/fit")
end)

T.test("books with no tags are never offered, and generic tags carry no weight", function()
    local l = { bk("/a", { "Fiction", "Space" }, "en"), bk("/b", { "Fiction", "Space" }, "en"), bk("/c", { "Fiction" }, "en"),
        bk("/d", { "Space" }, "en"), bk("/e", {}, "en") }
    local st = { ["/a"] = "complete", ["/b"] = "complete" }
    local pick = Taste.pick({ library = l, status_of = function(p) return st[p] or "new" end, rating_of = function() return 5 end })
    T.eq(pick.path, "/d")
end)

T.done()
