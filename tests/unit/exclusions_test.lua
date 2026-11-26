local T = dofile((debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$") or ".") .. "/helper.lua")
local Exclusions = require("afterword/exclusions")

print("exclusions")

local function fake()
    local store = {}
    return {
        readSetting = function(_, k) return store[k] end,
        saveSetting = function(_, k, v) store[k] = v end,
        delSetting = function(_, k) store[k] = nil end,
        store = store,
    }
end

T.test("add, count, list and remove; the last removal clears the setting", function()
    local s = fake()
    local ex = Exclusions.new(s)
    ex:add("author", "Zed")
    ex:add("author", "abe")
    T.eq(ex:count("author"), 2)
    T.eq(table.concat(ex:keys("author"), ","), "abe,Zed")
    ex:remove("author", "Zed"); ex:remove("author", "abe")
    T.eq(ex:count("author"), 0)
    T.eq(s.store.afterword_hidden_authors, nil)
end)

T.test("books keep the setting the first release wrote", function()
    local s = fake()
    s.store.afterword_hidden = { ["/a"] = true }
    T.eq(Exclusions.new(s):has("book", "/a"), true)
end)

T.test("a snooze hides a book until its time, then drops out of the settings", function()
    local s = fake()
    local ex = Exclusions.new(s)
    ex:snooze("/a", 1000, 30)
    T.eq(ex:hidden_paths(1000 + 29 * Exclusions.DAY)["/a"], true)
    T.eq(ex:hidden_paths(1000 + 31 * Exclusions.DAY)["/a"], nil)
    T.eq(ex:count("snooze"), 0)
end)

T.test("a skipped collection hides every book in it", function()
    local ex = Exclusions.new(fake())
    ex:add("collection", "Cookbooks")
    ex:add("book", "/x")
    local set = ex:hidden_paths(0, function(name) return name == "Cookbooks" and { "/c1", "/c2" } or {} end)
    T.eq(set["/c1"] and set["/c2"] and set["/x"], true)
    T.eq(set["/other"], nil)
end)

T.test("clear forgets every kind", function()
    local ex = Exclusions.new(fake())
    ex:add("book", "/a"); ex:add("series", "S"); ex:add("group", "recently_added"); ex:snooze("/b", 0, 1)
    T.eq(ex:total(), 4)
    ex:clear()
    T.eq(ex:total(), 0)
end)
