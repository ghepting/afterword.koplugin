#!/usr/bin/env python3
"""Writes Afterword's logo: two books, one leaning on the other, and a play badge beside them, on a shelf, over the name.

The layout, the shelf, the label bands on the books and the name's size follow ShelfSpace's and SideShelf's, so the plugins read as a set.
KOReader's SVG renderer ignores <text>, so the name is glyph outlines, drawn by tools/make-wordmark.py from KOReader's own Noto Sans Bold
(SIL Open Font License).

  tools/make-logo.py /path/to/NotoSans-Bold.ttf

writes assets/logo-light.svg and assets/logo-dark.svg, for the README. They cut the label bands, the gap between the books and the play
triangle out of the shapes with masks, so they show the page behind them.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
INK = {"light": "#2a363b", "dark": "#ffffff"}
NAME = "Afterword"
CANVAS = 195

# x, y, width, height and tilt of each book. The second leans on the first, resting on its bottom-left corner.
BOOKS = [(48, 66, 30, 68, 0), (82, 74, 30, 60, -12)]
BADGE = (134, 114, 15.5)   # centre x, centre y, radius: beside the books, clear of them, so nothing is cut out of either


def wordmark(font):
    # 88 wide is the width at which a nine-letter name has the letter size of ShelfSpace's name at 104.
    out = subprocess.run([sys.executable, os.path.join(HERE, "make-wordmark.py"), font, NAME, "88", "162", "95.6"],
                         capture_output=True, text=True, check=True)
    return out.stdout.strip()


def mask(mid, cuts):
    return ('<mask id="%s" maskUnits="userSpaceOnUse" x="0" y="0" width="%d" height="%d"><rect width="%d" height="%d" fill="#ffffff"/>%s</mask>'
            % (mid, CANVAS, CANVAS, CANVAS, CANVAS, cuts))


def books(ink):
    """Each book has a white label band near the top, as ShelfSpace's do. A gap is cut round a leaning book, so it stays a shape of its
    own beside the one it rests on."""
    defs, out = [], []
    for i, (x, y, w, h, tilt) in enumerate(BOOKS):
        tf = ' transform="rotate(%s %s %s)"' % (tilt, x, y + h) if tilt else ""
        cuts = '<g%s><rect x="%s" y="%s" width="%s" height="4.2" fill="#000000"/></g>' % (tf, x - 1, y + 13, w + 2)
        for (x2, y2, w2, h2, tilt2) in BOOKS[i + 1:]:
            if tilt2:
                cuts += ('<g transform="rotate(%s %s %s)"><rect x="%s" y="%s" width="%s" height="%s" rx="5" fill="#000000" '
                         'stroke="#000000" stroke-width="7"/></g>') % (tilt2, x2, y2 + h2, x2, y2, w2, h2)
        defs.append(mask("b%d" % i, cuts))
        out.append('<g mask="url(#b%d)"><g%s><rect x="%s" y="%s" width="%s" height="%s" rx="5.5" fill="%s"/></g></g>'
                   % (i, tf, x, y, w, h, ink))
    return "".join(defs), "".join(out)


def badge(ink):
    """A circle with a play triangle cut out of it. The triangle is drawn with a round-joined stroke so its corners are soft like
    everything else, and sits a little right of the middle so it looks centred."""
    bx, by, br = BADGE
    tri = "M%s %s L%s %s L%s %s Z" % (bx - 3.6, by - 7.2, bx + 7.6, by, bx - 3.6, by + 7.2)
    cut = '<path d="%s" fill="#000000" stroke="#000000" stroke-width="3.6" stroke-linejoin="round"/>' % tri
    return (mask("play", cut), '<g mask="url(#play)"><circle cx="%s" cy="%s" r="%s" fill="%s"/></g>' % (bx, by, br, ink))


def logo(ink, word):
    book_defs, book_shapes = books(ink)
    play_defs, play_shape = badge(ink)
    return ('<?xml version="1.0" encoding="UTF-8"?>'
            '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="137" viewBox="35.6 48 120 137"><defs>%s%s</defs>%s%s'
            '<rect x="41.6" y="140" width="108" height="9" rx="4.5" fill="%s"/>'
            '<path transform="translate(0 13)" d="%s" fill="%s"/></svg>'
            ) % (book_defs, play_defs, book_shapes, play_shape, ink, word, ink)


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    word = wordmark(sys.argv[1])
    for name, ink in INK.items():
        path = os.path.join(ROOT, "assets", "logo-%s.svg" % name)
        with open(path, "w") as f:
            f.write(logo(ink, word))
        print("wrote", os.path.relpath(path, ROOT))


main()
