#!/usr/bin/env python3
"""Seeds a KOReader desktop-emulator library with reading history, ratings and progress, so Afterword's picks have something
to work from. Three profiles:

  rich     a distinct taste (loves romantasy and sci-fi, dislikes mystery and thriller), a few books part-read, one on hold,
           and a history led by tagged books
  thin     one rated book and one in the history: not enough to guess from
  restore  every file back exactly as it was before the first seed

Switching between profiles is safe: the first thing a seed does is restore the last one. Only sidecars of books in
<volume>/Library and history.lua are touched, and the originals are kept in .adds/koreader/.afterword-seed.json.

Quit the emulator first (it rewrites history.lua when it exits).

  tools/seed-emulator.py rich [--volume PATH] [--dry-run]
"""
import argparse
import json
import os
import sqlite3
import shutil
import subprocess
import sys
import tempfile
import time

DEFAULT_VOLUME = os.path.expanduser("~/Development/shelfspace.koplugin/.emulator/volume")


def paths(volume):
    root = os.path.join(volume, ".adds", "koreader")
    return {
        "history": os.path.join(root, "history.lua"),
        "db": os.path.join(root, "settings", "bookinfo_cache.sqlite3"),
        "state": os.path.join(root, ".afterword-seed.json"),
        "library": os.path.join(volume, "Library") + "/",
    }


def library(p):
    """Every tagged book in the library: [(path, set(tags))], in a fixed order."""
    # A copy: the cache is in WAL mode, and a read-only open of that fails when KOReader is not running to own its -shm file.
    tmp = tempfile.mkdtemp()
    copy = os.path.join(tmp, "bookinfo.sqlite3")
    shutil.copy(p["db"], copy)
    for suffix in ("-wal", "-shm"):
        if os.path.exists(p["db"] + suffix):
            shutil.copy(p["db"] + suffix, copy + suffix)
    conn = sqlite3.connect(copy)
    rows = conn.execute(
        "SELECT directory, filename, keywords FROM bookinfo WHERE directory LIKE ? AND has_meta = 'Y' "
        "AND keywords IS NOT NULL AND keywords != '' ORDER BY directory, filename", (p["library"] + "%",)).fetchall()
    conn.close()
    shutil.rmtree(tmp, ignore_errors=True)
    out = []
    for directory, filename, keywords in rows:
        path = directory + filename
        if os.path.isfile(path):
            out.append((path, {t.strip() for t in keywords.split("\n") if t.strip()}))
    return out


def take(books, n, has, lacks=(), used=()):
    """The first n books that have all of `has`, none of `lacks`, and are not already used."""
    chosen = []
    for path, tags in books:
        if path in used or not set(has) <= tags or tags & set(lacks):
            continue
        chosen.append(path)
        if len(chosen) == n:
            break
    return chosen


def plan(profile, books):
    """-> ({path: (status, rating, percent)}, [history paths, most recent first])."""
    used, sidecars, history = set(), {}, []

    def add(group, status, ratings=(None,), percents=(1,)):
        for i, path in enumerate(group):
            used.add(path)
            sidecars[path] = (status, ratings[i % len(ratings)], percents[i % len(percents)])
        return group

    if profile == "thin":
        liked = take(books, 1, ["Fantasy"])
        add(liked, "complete", (5,))
        return sidecars, liked

    # rich: loves romantasy and sci-fi, dislikes mystery and thriller, indifferent to classics
    loved = add(take(books, 6, ["Romantasy"]), "complete", (5, 5, 4, 5, 4, 5))
    scifi = add(take(books, 4, ["Science Fiction"], lacks=["Fantasy", "Romantasy", "Mystery", "Thriller", "Suspense", "Horror"], used=used),
              "complete", (5, 4, 4, 5))
    noise = ["Science Fiction", "Fantasy", "Romantasy", "Horror"]
    disliked = add(take(books, 3, ["Mystery"], lacks=noise, used=used) + take(books, 2, ["Thriller"], lacks=noise, used=used),
                   "complete", (1, 2, 2, 1, 2))
    meh = add(take(books, 2, ["Classics"], lacks=["Mystery", "Fantasy", "Science Fiction"], used=used), "complete", (3, 3))
    add(take(books, 2, ["Horror"], lacks=["Science Fiction", "Fantasy"], used=used), "abandoned")
    reading = []
    for has, pct in ((["Fantasy"], 0.12), (["Science Fiction"], 0.38), (["Contemporary"], 0.61), (["Adventure"], 0.85)):
        reading += add(take(books, 1, has, lacks=["Romantasy"], used=used), "reading", (None,), (pct,))
    # most recent first: what is being read, then what was finished last
    history = reading + loved[:2] + scifi[:2] + disliked[:1] + meh[:1]
    return sidecars, history


def sidecar_path(book):
    stem, ext = os.path.splitext(book)
    return os.path.join(stem + ".sdr", "metadata" + ext + ".lua")


def sidecar_text(book, status, rating, percent):
    summary = ['        ["status"] = "%s",' % status]
    if rating:
        summary.append('        ["rating"] = %d,' % rating)
    summary.append('        ["modified"] = "%s",' % time.strftime("%Y-%m-%d"))
    return ('-- %s\nreturn {\n    ["doc_path"] = "%s",\n    ["percent_finished"] = %s,\n    ["summary"] = {\n%s\n    },\n}\n'
            % (sidecar_path(book), book, repr(percent) if percent != 1 else "1", "\n".join(summary)))


def history_text(history_file, books):
    now = int(time.time())
    entries = "".join('    [%d] = {\n        ["time"] = %d,\n        ["file"] = "%s",\n    },\n' % (i + 1, now - i * 3600, b)
                      for i, b in enumerate(books))
    return "-- %s\nreturn {\n%s}\n" % (history_file, entries)


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except FileNotFoundError:
        return None


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def restore(p):
    state = read(p["state"])
    if state is None:
        return 0
    state = json.loads(state)
    for path, original in state["files"].items():
        if original is None:
            if os.path.exists(path):
                os.remove(path)
                try:
                    os.rmdir(os.path.dirname(path))  # the .sdr folder, if the seed made it and it is now empty
                except OSError:
                    pass
        else:
            write(path, original)
    os.remove(p["state"])
    return len(state["files"])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("profile", choices=["rich", "thin", "restore"])
    ap.add_argument("--volume", default=DEFAULT_VOLUME)
    ap.add_argument("--dry-run", action="store_true", help="say what would change, change nothing")
    args = ap.parse_args()
    p = paths(args.volume)
    if not os.path.isfile(p["db"]):
        sys.exit("no book cache at %s: is --volume the emulator's volume?" % p["db"])
    if subprocess.run(["pgrep", "-f", "MacOS/[k]oreader"], capture_output=True).returncode == 0 and not args.dry_run:
        sys.exit("the emulator is running; quit it first (it rewrites history.lua on exit)")

    if args.profile == "restore":
        if args.dry_run:
            print("would restore %s files" % len(json.loads(read(p["state"]) or '{"files":{}}')["files"]))
        else:
            print("restored %d files" % restore(p))
        return

    books = library(p)
    sidecars, history = plan(args.profile, books)
    by_path = dict(books)
    print("%s: %d books marked, %d in the history" % (args.profile, len(sidecars), len(history)))
    for path, (status, rating, percent) in sidecars.items():
        print("  %-9s %s %-4s %s  [%s]" % (status, ("%d*" % rating) if rating else "  ", "%d%%" % round(percent * 100) if percent != 1 else "",
                                           os.path.basename(path)[:44], ", ".join(sorted(by_path[path]))[:40]))
    if args.dry_run:
        return

    restore(p)  # start from the originals, whichever profile was seeded last
    files = {}
    for path, (status, rating, percent) in sidecars.items():
        target = sidecar_path(path)
        files[target] = read(target)
        write(target, sidecar_text(path, status, rating, percent))
    files[p["history"]] = read(p["history"])
    write(p["history"], history_text(p["history"], history))
    write(p["state"], json.dumps({"profile": args.profile, "files": files}))
    print("seeded; `restore` puts everything back")


if __name__ == "__main__":
    main()
