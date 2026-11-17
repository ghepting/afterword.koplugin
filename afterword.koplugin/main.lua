local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local Afterword = WidgetContainer:extend {
    name = "afterword",
    is_doc_only = true, -- it only matters while a book is open
}

-- KOReader sends this when the last page of a book is reached.
function Afterword:onEndOfBook()
    logger.info("afterword: end of book reached")
end

return Afterword
