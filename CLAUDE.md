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

- `afterword.koplugin/afterword/series.lua`, `stats.lua`, `finish.lua` and `suggest.lua` are pure logic with no KOReader in them. Keep it that way and test it.
- `store.lua` reads KOReader's databases, `screen.lua` is the widget, and `main.lua` is the wiring: the menu, the end-of-book handler, the picker.
- The tests stub the few KOReader modules the logic loads (`tests/unit/helper.lua`).

## Shared with ShelfSpace

`afterword/version.lua`, `updater.lua`, `installer.lua` and their tests are ShelfSpace's, synced here with only the names changed, so the update check works the same in both. **Do not edit them here**: CI fails (`tools/sync-shared.sh --check`), and a sync overwrites them. To change one, change it in ShelfSpace, put the new ShelfSpace commit in `tools/shared-from`, and run `tools/sync-shared.sh`.

## Seeding the emulator

`tools/seed-emulator.py rich|thin|restore` writes ratings, progress and a reading history into the desktop emulator's library, so the picks have a taste to work from (`thin` is one rated book, to see the too-little-to-go-on case). It backs up what it touches in `.adds/koreader/.afterword-seed.json`, and `restore` puts every file back exactly. Quit the emulator first.

## The list

The Pick next list is drawn by `afterword/picklist.lua`: KOReader's own `Menu` (title bar, page arrows, paging) with its own rows: a group heading, a hero or compact card, and a shelf of up to five covers. Rows have different heights, and `PickMenu:setupItemHeights` decides which fit on a page, so the paging stays KOReader's. Tapping a book opens `afterword/detail.lua`, a sheet in the style of the end-of-book screen. Neither has unit tests, because they are all KOReader widgets: look at them in the emulator, at a short screen too so the list pages, and seed it with `tools/seed-emulator.py` so there is a taste to show. What goes in them (the groups, their order, why a book was picked) is `suggest.lua` and `taste.lua`, which are tested.
