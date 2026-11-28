# Afterword

A KOReader plugin in Lua. `tests/run.sh` runs the tests under plain `luajit`.

## Every pull request

- Before opening a pull request, check `README.md` against the change and update whatever it makes wrong: what the plugin shows, the settings, install, the development commands. If nothing in the README is affected, say so in the PR description.
- Do not describe something the plugin does not do. Read the code if unsure.
- The PR title is a conventional commit (`feat:`, `fix:`, `docs:`, `chore:`, `test:`, `refactor:`); pull requests are squash-merged.

## Wording

- The name is **Afterword**, one word, in all user-visible text, comments, README and PR text.
- Say "select" and "selected" for choosing a box or an item, never "tick".

## Where things go

- `afterword.koplugin/afterword/series.lua`, `stats.lua`, `finish.lua`, `wanted.lua` and `suggest.lua` are pure logic with no KOReader in them. Keep it that way and test it.
- `store.lua` reads KOReader's databases, `screen.lua` is the widget, and `main.lua` is the wiring: the menu, the end-of-book handler, the picker.
- The tests stub the few KOReader modules the logic loads (`tests/unit/helper.lua`).

## Shared with ShelfSpace

`afterword/version.lua`, `updater.lua`, `installer.lua` and their tests are ShelfSpace's, synced here with only the names changed, so the update check works the same in both. **Do not edit them here**: CI fails (`tools/sync-shared.sh --check`), and a sync overwrites them. To change one, change it in ShelfSpace, put the new ShelfSpace commit in `tools/shared-from`, and run `tools/sync-shared.sh`.

## Seeding the emulator

`tools/seed-emulator.py rich|thin|restore` writes ratings, progress and a reading history into the desktop emulator's library, so the picks have a taste to work from (`thin` is one rated book, to see the too-little-to-go-on case). It backs up what it touches in `.adds/koreader/.afterword-seed.json`, and `restore` puts every file back exactly. Quit the emulator first.

## The list

The Pick next list is drawn by `afterword/picklist.lua`: KOReader's own `Menu` (paging; the page arrows show only when a second page is needed) under Afterword's own header (`afterword/header.lua`: the mark, the name, close) with its own rows: the two single picks side by side, then the other groups as columns of small-cover rows, three to a row. The picks' covers take whatever height the lists leave, so the same layout fits portrait and landscape. `PickMenu:setupItemHeights` sizes the rows and decides which fit on a page, so the paging stays KOReader's. Tapping a cover or a Start button opens the book; pressing and holding one raises a sheet (`afterword/sheet.lua`: the book, then "don't suggest", "not now" (30 days) and "fewer like this", which asks for the author, the series or the row), and a Toast with Undo follows. The header's mark opens a small menu (Preferences, Check for updates, Close). Everything hidden is kept by `afterword/exclusions.lua` (one table per kind in `G_reader_settings`, unit-tested with a fake settings object) and handed to `Suggest.groups` as `ctx.hidden` (books, snoozes and skipped collections' books by path), `ctx.hidden_authors`, `ctx.hidden_series` and `ctx.hidden_groups`. A book that skips ahead in its series gets a black badge ("Book 4 missing", "3 books missing"): `Series.missing` finds the whole numbers before it that are not in the library, `Suggest` puts them on the book as `missing` (not on the On hold row), and `picklist.lua` draws the pill on a card, and a shorter, outlined one ("2 missing") on the "Book 8" line of a list column (a started book shows its percentage at the end of its bar, never on the "Book 8" line, so a badge always has room). A list row is as tall as the tallest book in it (`row_hs` per list, so the columns line up), not the tallest on the screen: a badge with a percentage makes only its own row taller, and the picks above take what the lists leave. The On hold row carries `note_line` ("4 months ago"), from the date KOReader keeps in the book's own settings (`put_down_of` in main.lua). When the list has nothing in it, `afterword/empty.lua` shows a screen with buttons instead of a message: Close, and Open Preferences when things are hidden. The Preferences screens are `afterword/prefs.lua`: an overview, then a screen per kind, all KOReader's `Menu` with rows of their own (`PrefMenu` extends `PickMenu`; its rows keep their own heights, so it names its packing method `layoutRows`, because Menu keeps a table called `layout`; and it needs `items_max_lines` set for Menu to ask for the page layout at all). Selecting follows ShelfSpace: a checkbox per row, a Select all line, and a bar the menu paints itself and answers taps for (a separate widget would take every tap with it). The pickers, the confirm before bringing things back and the filter dialog are in the same file. The list has no unit tests, because it is made of KOReader widgets: look at them in the emulator, at a short screen too so the list pages, and seed it with `tools/seed-emulator.py` so there is a taste to show. What goes in them (the groups, their order, why a book was picked) is `suggest.lua` and `taste.lua`, which are tested.

## Want to read

`afterword/wanted.lua` is pure logic: `from_csv` reads a Goodreads, StoryGraph or generic CSV (only the to-read shelf, series taken out of Goodreads titles), `match` pairs a list with the library by `title_key` and the author's `surname` (never an id: the library has none), and `lists` / `save` / `forget` / `merged` keep one list per source in `G_reader_settings` (`afterword_wanted`), with the boost and "show books I don't own" switches beside it. `Suggest` takes `ctx.wanted` (owned books on a list: tagged `listed`, `listed_pick` for the pick made for it, ranked first in Recently added), `ctx.boost` and `ctx.unowned` (an opt-in "Want to read" row of books with no path, `unowned = true`). `picklist.lua` draws a book with no path as an empty "+" frame and the TBR pill on the "Book 8" line; main.lua sends a tap or hold on one to `askAboutUnowned`. The screens are in `prefs.lua` (`wanted_screen`, `browse_screen`, with the `tabs`, `listing` and `pair` row kinds, and `Prefs.import_file` using KOReader's `PathChooser`). A source with no list shows nothing: nothing about a service appears until it is set up.

`afterword/hardcover.lua` reads the Hardcover want-to-read shelf: the token is pasted into a masked `InputDialog` (`Prefs.ask_token`, tried at once and dropped if refused) and kept in `afterword_sources.lua` in KOReader's settings folder (loaded with an empty environment, so the file cannot run anything), the request goes through an injected `io.post` so the tests need no network, and `fetch_now` uses `socket.http` as `updater.lua` does. The token is never shown, logged or put in a message. Hardcover is named in the UI only in "Connect a service", its own screen, and, once a token exists, its card and tab (`wanted_screen` hides "Connect a service…" then). The query (status 1 = Want to read) was checked against a real account on 2026-11-28 with a key holding `read:library`, `read:catalog` and `read:me:content` (the email and roles scopes are not needed); adding a book will also need `write:library`.
