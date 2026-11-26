-- What the person has told Afterword not to suggest, kept in KOReader's settings (`settings` is G_reader_settings, or any object with
-- readSetting / saveSetting / delSetting). Every kind is a table { [key] = value }; the plain data is read by suggest.lua through main.lua.
local Exclusions = {}
Exclusions.__index = Exclusions

local KEYS = {
    book = "afterword_hidden",                   -- { [path] = true }
    author = "afterword_hidden_authors",         -- { [name] = true }
    series = "afterword_hidden_series",          -- { [name] = true }
    group = "afterword_hidden_groups",           -- { [group name] = true }: whole rows of the list
    collection = "afterword_skipped_collections", -- { [collection name] = true }: nothing in them is suggested
    snooze = "afterword_snoozed",                -- { [path] = time it comes back }
}
Exclusions.DAY = 24 * 60 * 60

function Exclusions.new(settings) return setmetatable({ settings = settings }, Exclusions) end

function Exclusions:get(kind)
    local set = self.settings:readSetting(KEYS[kind])
    return type(set) == "table" and set or {}
end

function Exclusions:add(kind, key, value)
    local set = self:get(kind)
    set[key] = value == nil and true or value
    self.settings:saveSetting(KEYS[kind], set)
end

function Exclusions:remove(kind, key)
    local set = self:get(kind)
    set[key] = nil
    if next(set) then self.settings:saveSetting(KEYS[kind], set) else self.settings:delSetting(KEYS[kind]) end
end

function Exclusions:has(kind, key) return self:get(kind)[key] ~= nil end

function Exclusions:keys(kind)
    local keys = {}
    for key in pairs(self:get(kind)) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
    return keys
end

function Exclusions:count(kind)
    local n = 0
    for _key in pairs(self:get(kind)) do n = n + 1 end
    return n
end

-- Snoozed books come back by themselves: `days` from `now`.
function Exclusions:snooze(path, now, days) self:add("snooze", path, now + days * Exclusions.DAY) end

-- The snoozes still running at `now`, { [path] = comes back at }. Ended ones are dropped from the settings.
function Exclusions:live_snoozes(now)
    local live, ended = {}, {}
    for path, back in pairs(self:get("snooze")) do
        if back > now then live[path] = back else ended[#ended + 1] = path end
    end
    for _i, path in ipairs(ended) do self:remove("snooze", path) end
    return live
end

-- Everything that keeps a book out by its path: hidden, snoozed, or in a skipped collection (`collection_paths(name)` -> list).
function Exclusions:hidden_paths(now, collection_paths)
    local set = {}
    for path in pairs(self:get("book")) do set[path] = true end
    for path in pairs(self:live_snoozes(now)) do set[path] = true end
    for name in pairs(self:get("collection")) do
        for _i, path in ipairs(collection_paths and collection_paths(name) or {}) do set[path] = true end
    end
    return set
end

function Exclusions:total()
    local n = 0
    for kind in pairs(KEYS) do n = n + self:count(kind) end
    return n
end

-- Forgets every exclusion.
function Exclusions:clear()
    for _kind, key in pairs(KEYS) do self.settings:delSetting(key) end
end

return Exclusions
