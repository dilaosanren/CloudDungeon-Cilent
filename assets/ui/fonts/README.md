# UI fonts

`pixel_font.ttf` is the unchanged Shattered Pixel Dungeon font for Latin text and
numbers. See the project's `THIRD_PARTY.md` and `LICENSE-SPD.txt`.

`droid_sans.ttf` is the unchanged Droid Sans Fallback font used by the supplied
Shattered Pixel Dungeon 4.0.2 desktop build:

- Source: `shattered-pixel-dungeon-4.0.2backup/desktop/src/main/assets/fonts/droid_sans.ttf`.
- Upstream: https://github.com/00-Evan/shattered-pixel-dungeon
- Size: 3,611,232 bytes, 50,841 glyphs.
- SHA-256: `a20c729bc1c91cefcf6e227cba675fff2761968fb7f8f2ae30cd58fec85f6867`.
- Font metadata credits Google Corporation (2006), Ascender Corporation and
  designer Steve Matteson, and identifies the license as Apache License 2.0.
- License: `LICENSE-DroidSansFallback.txt`; attribution: `NOTICE-DroidSansFallback.txt`.

The imported FontFile disables system fallback, so CJK glyphs are available from
the game package on Android as well as desktop. The shared UI variation uses
MSDF; native-sized rich text duplicates the same font data for raster rendering.

The previous Noto font and its metadata/license are backed up outside the Godot
project at workspace `.validation/font-before-droid-0.0.5/` and are not exported.
