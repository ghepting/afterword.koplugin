-- One unread book that fits what you have liked, judged by the genre tags KOReader keeps for each book. No KOReader in here.
--
--   ctx.library    { { path, keywords, language }, ... }; keywords is one tag per line
--   ctx.status_of  function(path) -> "new" | "reading" | "complete" | "abandoned"
--   ctx.rating_of  function(path) -> 0 (none) to 5
--   ctx.skip       { [path] = true } books not to offer (the current one, ones already suggested)
--
--   ctx.current    contrast only: path of the book just read or open now
--
-- pick(ctx) -> { path, tags } where tags are the two that matched best, or nil when there is too little to go on.
-- contrast(ctx) -> the same shape: an unread book that shares no tag with ctx.current and none you have rated down, and fits
-- the tags you do like, for when you want something different from the book you are on.
--
-- A book you rated 4 or 5 counts for its tags, a 3 a little, a 1 or 2 against them; one you finished without rating counts a
-- little; one you put on hold counts a little against. Tags that few books carry count for more than ones nearly everything has,
-- and a book with a long tag list is not favoured for it.
local Taste = {}

local GENERIC = { fiction = true, general = true, ebook = true, books = true, novel = true, literature = true }
local MIN_LIKED = 2 -- books you liked before it will guess

local function tags_of(record)
    local seen, list = {}, {}
    for line in tostring(record.keywords or ""):gmatch("[^\n]+") do
        local key = line:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if key ~= "" and not GENERIC[key] and not seen[key] then
            seen[key] = true
            list[#list + 1] = { key = key, label = (line:gsub("^%s+", ""):gsub("%s+$", "")) }
        end
    end
    return list
end

-- How much a book you have read says you like its tags.
local function weight(status, rating)
    if rating >= 4 then return 2 end
    if rating == 3 then return 0.5 end
    if rating >= 1 then return -1 end
    if status == "complete" then return 1 end
    if status == "abandoned" then return -0.5 end
    return 0
end

-- Whether a library record has any usable genre tags.
function Taste.tagged(record)
    return record ~= nil and #tags_of(record) > 0
end

-- What the library says about taste: each book's tags, how common each tag is, and how much you like each one.
local function build(ctx)
    local library = ctx.library or {}
    local tags, label, df, tagged = {}, {}, {}, 0
    for _i, r in ipairs(library) do
        local list = tags_of(r)
        tags[r.path] = list
        if #list > 0 then tagged = tagged + 1 end
        for _j, t in ipairs(list) do
            df[t.key] = (df[t.key] or 0) + 1
            label[t.key] = label[t.key] or t.label
        end
    end

    local profile, liked, languages = {}, 0, {}
    for _i, r in ipairs(library) do
        local w = weight(ctx.status_of(r.path), ctx.rating_of and ctx.rating_of(r.path) or 0)
        if w ~= 0 and #tags[r.path] > 0 then
            for _j, t in ipairs(tags[r.path]) do profile[t.key] = (profile[t.key] or 0) + w end
            if w > 0 then
                liked = liked + 1
                local lang = tostring(r.language or ""):lower()
                if lang ~= "" then languages[lang] = (languages[lang] or 0) + 1 end
            end
        end
    end

    local mine, best = nil, 0
    for lang, n in pairs(languages) do
        if n > best then mine, best = lang, n end
    end
    return { tags = tags, label = label, df = df, tagged = tagged, profile = profile, liked = liked, language = mine }
end

-- How well an unread book fits the tags you like (0 when none of its tags qualify), and the two that matter most.
-- `except` is a set of tag keys not to count.
local function fit(model, record, except)
    local list = model.tags[record.path]
    local score, matched = 0, {}
    for _j, t in ipairs(list) do
        local p = model.profile[t.key] or 0
        if p > 0 and not (except and except[t.key]) then
            local value = p * math.log(1 + model.tagged / model.df[t.key])
            score = score + value
            matched[#matched + 1] = { key = t.key, value = value }
        end
    end
    score = score / math.sqrt(math.max(#list, 1))
    table.sort(matched, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.key < b.key
    end)
    local top = {}
    for i = 1, math.min(2, #matched) do top[i] = model.label[matched[i].key] end
    return score, top
end

-- Whether a book may be offered: unread, not skipped, and in a language you read.
local function offerable(ctx, model, record)
    local lang = tostring(record.language or ""):lower()
    return not (ctx.skip or {})[record.path] and ctx.status_of(record.path) == "new"
        and (model.language == nil or lang == "" or lang == model.language)
end

local function better(score, record, best_score, best)
    return best == nil or score > best_score or (score == best_score and record.path < best.path)
end

function Taste.pick(ctx)
    local model = build(ctx)
    if model.liked < MIN_LIKED then return nil end
    local pick, pick_score
    for _i, r in ipairs(ctx.library or {}) do
        if offerable(ctx, model, r) then
            local score, top = fit(model, r)
            if score > 0 and better(score, r, pick_score, pick) then pick, pick_score = { path = r.path, tags = top }, score end
        end
    end
    return pick
end

function Taste.contrast(ctx)
    local model = build(ctx)
    if model.liked < MIN_LIKED or not ctx.current then return nil end
    local mine = {}
    for _i, t in ipairs(model.tags[ctx.current] or {}) do mine[t.key] = true end
    if next(mine) == nil then return nil end -- nothing to be the opposite of
    local pick, pick_score
    for _i, r in ipairs(ctx.library or {}) do
        if offerable(ctx, model, r) and r.path ~= ctx.current then
            local list = model.tags[r.path]
            local clear = #list > 0
            for _j, t in ipairs(list) do
                if mine[t.key] or (model.profile[t.key] or 0) < 0 then clear = false; break end
            end
            if clear then
                local score, top = fit(model, r)
                if score > 0 and better(score, r, pick_score, pick) then pick, pick_score = { path = r.path, tags = top }, score end
            end
        end
    end
    return pick
end

return Taste
