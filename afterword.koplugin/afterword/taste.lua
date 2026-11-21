-- One unread book that fits what you have liked, judged by the genre tags KOReader keeps for each book. No KOReader in here.
--
--   ctx.library    { { path, keywords, language }, ... }; keywords is one tag per line
--   ctx.status_of  function(path) -> "new" | "reading" | "complete" | "abandoned"
--   ctx.rating_of  function(path) -> 0 (none) to 5
--   ctx.skip       { [path] = true } books not to offer (the current one, ones already suggested)
--
-- pick(ctx) -> { path, tags } where tags are the two that matched best, or nil when there is too little to go on.
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

function Taste.pick(ctx)
    local library = ctx.library or {}
    local skip = ctx.skip or {}
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
    if liked < MIN_LIKED then return nil end

    local mine, best = nil, 0
    for lang, n in pairs(languages) do
        if n > best then mine, best = lang, n end
    end

    local pick, pick_score
    for _i, r in ipairs(library) do
        local lang = tostring(r.language or ""):lower()
        if not skip[r.path] and ctx.status_of(r.path) == "new" and (mine == nil or lang == "" or lang == mine) then
            local score, matched = 0, {}
            for _j, t in ipairs(tags[r.path]) do
                local p = profile[t.key] or 0
                if p > 0 then
                    local value = p * math.log(1 + tagged / df[t.key])
                    score = score + value
                    matched[#matched + 1] = { key = t.key, value = value }
                end
            end
            score = score / math.sqrt(math.max(#tags[r.path], 1))
            if score > 0 and (pick == nil or score > pick_score or (score == pick_score and r.path < pick.path)) then
                table.sort(matched, function(a, b)
                    if a.value ~= b.value then return a.value > b.value end
                    return a.key < b.key
                end)
                local top = {}
                for i = 1, math.min(2, #matched) do top[i] = label[matched[i].key] end
                pick, pick_score = { path = r.path, tags = top }, score
            end
        end
    end
    return pick
end

return Taste
