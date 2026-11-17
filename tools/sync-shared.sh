#!/usr/bin/env bash
# Copies the files Afterword shares with ShelfSpace from a pinned ShelfSpace commit (tools/shared-from), renaming the plugin
# ("shelfspace" to "afterword", "ShelfSpace" to "Afterword"), so the two plugins stay alike and a fix is made once.
#
#   tools/sync-shared.sh           rewrites the shared files from the pinned commit
#   tools/sync-shared.sh --check   changes nothing; fails if a shared file differs from what a sync would write (CI runs this)
#
# To change a shared file: change it in ShelfSpace, then put the new commit in tools/shared-from and run this.
# Never edit a shared file here: the check fails, and a sync overwrites it.
#
# The commit is fetched from GitHub. SHELFSPACE_DIR=<a ShelfSpace checkout> reads it from there instead (it must have the commit).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
sha="$(tr -d '[:space:]' < "$root/tools/shared-from")"
repo="ghepting/shelfspace.koplugin"
check=0
[ "${1:-}" = "--check" ] && check=1

# Modules (with the header added) and their tests, as the paths they have in ShelfSpace.
modules="version updater installer"
src_dir="shelfspace.koplugin/shelfspace"
dst_dir="afterword.koplugin/afterword"

fetch() {
    if [ -n "${SHELFSPACE_DIR:-}" ]; then
        git -C "$SHELFSPACE_DIR" show "$sha:$1"
    else
        curl -fsSL "https://raw.githubusercontent.com/$repo/$sha/$1"
    fi
}
rename() { sed -e 's/shelfspace/afterword/g' -e 's/ShelfSpace/Afterword/g'; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
status=0

# write <destination in this repo> <content file>
place() {
    local dest="$1" new="$2"
    if [ "$check" = 1 ]; then
        if ! cmp -s "$new" "$root/$dest"; then
            echo "differs from ShelfSpace at ${sha:0:7}: $dest"
            status=1
        fi
    else
        mkdir -p "$(dirname "$root/$dest")"
        cp "$new" "$root/$dest"
    fi
}

for m in $modules; do
    {
        echo "-- Synced from ShelfSpace at ${sha:0:7} by tools/sync-shared.sh. Change it in ShelfSpace, then sync; edits here are overwritten."
        fetch "$src_dir/$m.lua" | rename
    } > "$tmp/$m.lua"
    place "$dst_dir/$m.lua" "$tmp/$m.lua"
    fetch "tests/unit/${m}_test.lua" | rename > "$tmp/${m}_test.lua"
    place "tests/unit/${m}_test.lua" "$tmp/${m}_test.lua"
done

if [ "$check" = 1 ]; then
    [ "$status" = 0 ] && echo "shared files match ShelfSpace at ${sha:0:7}"
    exit "$status"
fi
echo "synced from ShelfSpace at ${sha:0:7}"
