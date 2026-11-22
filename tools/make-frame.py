#!/usr/bin/env python3
"""Puts a screenshot in an e-reader frame, for the README: a dark bezel, a soft shadow, a transparent background.

  tools/make-frame.py shot.png out.png [--width 900]

Needs rsvg-convert and ImageMagick (brew install librsvg imagemagick). The screenshot should be a whole screen, as the
emulator makes it; the frame is drawn around it at its own size and the result scaled down to --width.
"""
import argparse
import base64
import os
import struct
import subprocess
import tempfile


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def frame_svg(path, w, h):
    bezel = round(min(w, h) * 0.05)    # even on every side, like a Libra
    outer_r = round(bezel * 1.15)
    screen_r = round(bezel * 0.18)
    pad = round(bezel * 1.6)           # room for the shadow
    total_w, total_h = w + 2 * bezel + 2 * pad, h + 2 * bezel + 2 * pad
    x0, y0 = pad, pad
    data = base64.b64encode(open(path, "rb").read()).decode()
    return f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{total_w}" height="{total_h}" viewBox="0 0 {total_w} {total_h}">
  <defs>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="{bezel * 0.45}"/></filter>
    <linearGradient id="body" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#34363a"/><stop offset="1" stop-color="#1b1c1f"/></linearGradient>
    <clipPath id="screen"><rect x="{x0 + bezel}" y="{y0 + bezel}" width="{w}" height="{h}" rx="{screen_r}"/></clipPath>
  </defs>
  <rect x="{x0 + bezel * 0.2}" y="{y0 + bezel * 0.9}" width="{w + 2 * bezel}" height="{h + 2 * bezel}" rx="{outer_r}" fill="#000" opacity="0.28" filter="url(#shadow)"/>
  <rect x="{x0}" y="{y0}" width="{w + 2 * bezel}" height="{h + 2 * bezel}" rx="{outer_r}" fill="url(#body)"/>
  <rect x="{x0 + 2}" y="{y0 + 2}" width="{w + 2 * bezel - 4}" height="{h + 2 * bezel - 4}" rx="{outer_r - 2}" fill="none" stroke="#fff" stroke-opacity="0.14" stroke-width="3"/>
  <rect x="{x0 + bezel - 3}" y="{y0 + bezel - 3}" width="{w + 6}" height="{h + 6}" rx="{screen_r + 3}" fill="#0b0b0c"/>
  <image x="{x0 + bezel}" y="{y0 + bezel}" width="{w}" height="{h}" clip-path="url(#screen)" xlink:href="data:image/png;base64,{data}"/>
</svg>'''


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("shot")
    ap.add_argument("out")
    ap.add_argument("--width", type=int, default=900)
    a = ap.parse_args()
    w, h = png_size(a.shot)
    with tempfile.TemporaryDirectory() as tmp:
        svg, big = os.path.join(tmp, "f.svg"), os.path.join(tmp, "f.png")
        open(svg, "w").write(frame_svg(a.shot, w, h))
        subprocess.run(["rsvg-convert", svg, "-o", big], check=True)
        subprocess.run(["magick", big, "-resize", f"{a.width}x", a.out], check=True)


main()
