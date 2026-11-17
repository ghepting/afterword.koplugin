-- What the screen says about how a book went. No KOReader in here: the numbers come in as plain data (from KOReader's own
-- statistics) and go out as figures and short phrases.
--
-- `book` is { read_seconds, read_pages, first_read, finished } where the times are Unix seconds: how long you spent reading it,
-- how many pages, when you first read a page of it, and when it was finished. A figure that cannot be known is nil, and the
-- screen leaves that line out.
local _ = require("gettext")
local T = require("ffi/util").template

local Stats = {}

local DAY = 86400

-- span_days(first, finished) -> whole calendar days from the first page to the last, at least 1.
function Stats.span_days(first, finished)
    first, finished = tonumber(first), tonumber(finished)
    if not first or not finished or finished < first then return nil end
    return math.max(1, math.ceil((finished - first) / DAY))
end

-- pages_per_day(book) -> whole pages a day over the days it took, or nil.
function Stats.pages_per_day(book)
    local days = Stats.span_days(book.first_read, book.finished)
    local pages = tonumber(book.read_pages)
    if not days or not pages or pages <= 0 then return nil end
    return math.floor(pages / days + 0.5)
end

-- "3 weeks, 2 days", "5 days", "1 day": how long it took from first page to last.
function Stats.span_text(days)
    if not days then return nil end
    local weeks, rest = math.floor(days / 7), days % 7
    if weeks == 0 then
        if days == 1 then return _("1 day") end
        return T(_("%1 days"), days)
    end
    local w = weeks == 1 and _("1 week") or T(_("%1 weeks"), weeks)
    if rest == 0 then return w end
    return T(_("%1, %2"), w, rest == 1 and _("1 day") or T(_("%1 days"), rest))
end

-- "21 h 40 m", "45 m", "2 h": time spent reading. Under a minute is nil (nothing worth a line).
function Stats.duration_text(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds < 60 then return nil end
    local minutes = math.floor(seconds / 60 + 0.5)
    local h, m = math.floor(minutes / 60), minutes % 60
    if h == 0 then return T(_("%1 m"), m) end
    if m == 0 then return T(_("%1 h"), h) end
    return T(_("%1 h %2 m"), h, m)
end

-- lines(book) -> the stat lines to show, each { label, value }, only those that can be known.
function Stats.lines(book)
    local out = {}
    local span = Stats.span_text(Stats.span_days(book.first_read, book.finished))
    if span then out[#out + 1] = { label = _("Read in"), value = span } end
    local time = Stats.duration_text(book.read_seconds)
    if time then out[#out + 1] = { label = _("Time reading"), value = time } end
    local pace = Stats.pages_per_day(book)
    if pace then out[#out + 1] = { label = _("Pace"), value = T(_("%1 pages a day"), pace) } end
    return out
end

return Stats
