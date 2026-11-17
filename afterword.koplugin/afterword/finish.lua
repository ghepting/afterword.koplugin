-- Whether the book ends up marked as finished. No KOReader in here.
--
-- The screen has a checkbox. Its starting state follows what the reader has already set up: ticked when KOReader's own "mark a book
-- finished at its end" setting is on, or when the book is already marked finished; unticked otherwise. What is done when the reader
-- leaves is decided here.
local Finish = {}

-- default(auto_mark, status) -> whether the box starts ticked.
function Finish.default(auto_mark, status)
    return auto_mark == true or status == "complete"
end

-- status_after(was, checked) -> the status to write, or nil to leave it alone. `was` is the status the book had.
--   ticked: finished (nothing to write when it is already)
--   unticked on a book that was finished: back to "reading"
--   unticked on any other book: untouched
function Finish.status_after(was, checked)
    if checked then
        if was == "complete" then return nil end
        return "complete"
    end
    if was == "complete" then return "reading" end
    return nil
end

return Finish
