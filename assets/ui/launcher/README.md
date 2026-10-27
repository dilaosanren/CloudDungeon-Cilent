# Android launcher icon

Two crossed original greatswords over the original sewer dungeon floor.
The rear sword uses 65% RGB brightness; the front sword keeps its original colors.
Sources: `assets/items/source/items.png`, region (0, 128, 16, 16), matching
`greatsword.tres`; `assets/environment/tiles_sewers.png`, tile 0 (EMPTY).
Original Shattered Pixel Dungeon art remains covered by `LICENSE-SPD.txt`
and `THIRD_PARTY.md`. No generated or replacement artwork is used.

Regenerate from the full project root:

```
godot --headless --path . --script tools/menu/build_android_icon.gd
```

`export_presets.cfg` selects `crossed_greatswords.png` (192px legacy), plus
`crossed_greatswords_foreground.png`, `crossed_greatswords_background.png`,
and `crossed_greatswords_monochrome.png` (432px adaptive layers).
The adaptive swords fit inside Android's centered 264px safe circle.
Nearest-neighbor scaling preserves the original pixels. Legacy statue files
are retained for history but are no longer selected for Android export.