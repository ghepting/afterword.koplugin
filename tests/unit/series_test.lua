local T = dofile((debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$") or ".") .. "/helper.lua")
local Series = require("afterword/series")

print("series")

local lib = {
    { path = "/s5", series = "Strike", series_index = 5 },
    { path = "/s6", series = "Strike", series_index = 6 },
    { path = "/s4", series = "strike ", series_index = 4 },
    { path = "/s8", series = "Strike", series_index = 8 },
    { path = "/hp1", series = "Potter", series_index = 1 },
    { path = "/hp2", series = "Potter", series_index = 2 },
    { path = "/n1", series = "Novel", series_index = 1 },
    { path = "/n15", series = "Novel", series_index = 1.5 },
    { path = "/n2", series = "Novel", series_index = 2 },
    { path = "/free", title = "no series" },
    { path = "/unnum", series = "Strike" },
}

T.test("the next book is the one with the next higher number in the same series", function()
    T.eq(Series.next_in_series(lib, "/s5").path, "/s6")
    T.eq(Series.next_in_series(lib, "/hp1").path, "/hp2")
end)
T.test("a series name matches ignoring case and spacing", function()
    T.eq(Series.next_in_series(lib, "/s4").path, "/s5")
end)
T.test("a gap in what you own is skipped", function()
    T.eq(Series.next_in_series(lib, "/s6").path, "/s8")
end)
T.test("a novella between books is in the order", function()
    T.eq(Series.next_in_series(lib, "/n1").path, "/n15")
    T.eq(Series.next_in_series(lib, "/n15").path, "/n2")
end)
T.test("the last book you own has no next", function()
    T.eq(Series.next_in_series(lib, "/s8"), nil)
    T.eq(Series.next_in_series(lib, "/hp2"), nil)
end)
T.test("a book with no series, no number, or not in the library has no next", function()
    T.eq(Series.next_in_series(lib, "/free"), nil)
    T.eq(Series.next_in_series(lib, "/unnum"), nil)
    T.eq(Series.next_in_series(lib, "/missing"), nil)
    T.eq(Series.next_in_series({}, "/s5"), nil)
end)
T.test("an unnumbered book is never anyone's next", function()
    T.eq(Series.next_in_series(lib, "/s8"), nil)
end)
T.test("two books with the same number: the same one every time", function()
    local twins = { { path = "/a", series = "S", series_index = 1 }, { path = "/c", series = "S", series_index = 2 },
                    { path = "/b", series = "S", series_index = 2 } }
    T.eq(Series.next_in_series(twins, "/a").path, "/b")
end)
T.test("position: this book's number and the highest number you own", function()
    local p = Series.position(lib, "/s5")
    T.eq(p.index, 5); T.eq(p.last, 8); T.eq(p.series, "Strike")
    T.eq(Series.position(lib, "/free"), nil)
end)

T.test("everything after a book, in order, skipping other series and unnumbered books", function()
    local after = Series.after(lib, "/s5")
    local out = {}
    for i, r in ipairs(after) do out[i] = r.path end
    T.eq(table.concat(out, " "), "/s6 /s8")
    T.eq(#Series.after(lib, "/s8"), 0)
    T.eq(#Series.after(lib, "/free"), 0)
end)

T.done()
