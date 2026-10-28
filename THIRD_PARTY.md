# Shattered Pixel Dungeon resources and rendering rules

The background tracks `assets/audio/theme.ogg` and `assets/audio/game.ogg`
were supplied by the project owner as `Theme.ogg` and `Game.ogg` in the workspace
on 2026-10-28. They are separate from the upstream sound effects described here.

The PNG files in `assets/environment/` are copied unchanged from the supplied
Shattered Pixel Dungeon 4.0.2 source tree (`core/src/main/assets/environment/`).
The rendering rules in `scripts/dungeon_map.gd` and terrain IDs in
`scripts/dungeon_terrain.gd` are ported from its Java terrain/tilemap classes.
`scripts/ballistica.gd` ports `mechanics/Ballistica.java` without changing its
ray stepping or collision ordering. `scripts/ballistic_level.gd` ports the
relevant `Level.java` flag-map and boundary semantics.

`scripts/maps/map_canvas.gd` reuses the native terrain renderer and unchanged
terrain atlases for the player-authored 12x12 map editor, thumbnails and public
submission viewer. Grid and spawn markers are drawn in code, with no new bitmap
art. These editor/menu adapters retain GPL-3.0-or-later attribution for the reused
rendering and UI resources.

Upstream: https://github.com/00-Evan/shattered-pixel-dungeon

`assets/ui/fonts/droid_sans.ttf` is the unchanged Droid Sans Fallback font from
the supplied Shattered Pixel Dungeon 4.0.2 desktop assets. Its embedded metadata
credits Google Corporation (2006), Ascender Corporation and Steve Matteson, and
specifies Apache License 2.0. The full license and attribution are included in
`assets/ui/fonts/LICENSE-DroidSansFallback.txt` and `NOTICE-DroidSansFallback.txt`;
source details and SHA-256 are recorded in `assets/ui/fonts/README.md`. The font
is bundled with clients for portable Chinese text rendering on Android and desktop.

The About page in `scripts/menu/about_scene.gd` and `about_credit_block.gd`
adapts the supplied `AboutScene.java`, `ExitButton.java`, `CreditsBlock` and
`Flare.java`. Original author credits, links, sound sample attributions and
icon crops are preserved in `assets/menu/about_credits.json`, with source hashes.
The page distinguishes ChaoticDungeon's Godot engine from upstream libGDX.
These adaptations are distributed under GPL-3.0-or-later.

The main-menu journal in `scripts/menu/journal_scene.gd` adapts the supplied
`scenes/JournalScene.java`, `windows/IconTitle.java` and `ui/ExitButton.java`.
Its two icon tabs use the original `Icons.JOURNAL`, `BADGES`, `CATALOG`,
`WARNING` and `EXIT` crops from the unchanged interfaces atlas; source hashes
and crop rectangles are recorded in `assets/menu/source_catalog.json`.
The badges page retains its construction placeholder. Equipment previews share
WndInfoItem content, with text and demonstrations in one content-sized window. The melee sandbox uses
the unchanged caves special-floor tiles and warrior animations already credited
above. `assets/menu/showcase/rat.png` is copied unchanged from the supplied
`core/src/main/assets/sprites/rat.png`; `equipment_rat_sprite.gd` adapts
`sprites/RatSprite.java`'s original 16x15 idle and attack frames. The new texture and Java
source SHA-256 hashes are recorded in `assets/menu/showcase/source_catalog.json`.
These adaptations are distributed under GPL-3.0-or-later.

The scroll previews reuse the existing ScrollWorld, ScrollEffects, MirrorSprite
and HeroSprite.read adaptations. `assets/menu/showcase/statue.png` is copied
unchanged from upstream `core/src/main/assets/sprites/statue.png`;
`equipment_statue_sprite.gd` follows StatueSprite.java's 12x15 idle sequence.
Its image and Java SHA-256 hashes are recorded in the showcase source catalog.
The sleep symbol uses the original Icons.SLEEP crop (7,88,9,8) and
EmoIcon.Sleep pulse; blindness/paralysis use BuffIndicator's 7px source icons.
These adaptations are distributed under GPL-3.0-or-later.

The settings window and client preferences in `scripts/menu/` adapt
`WndSettings.java`, `OptionSlider.java`, `CheckBox.java`, `SPDSettings.java`
and the Chinese settings messages from the supplied 4.0.2 tree. Settings
icons use the unchanged interfaces atlas; crop rectangles and Java hashes
are recorded in `assets/menu/source_catalog.json`. The visual grid uses the
unchanged `assets/environment/visual_grid.png` and `GridTileMap.java` rules.
These adaptations are distributed under GPL-3.0-or-later.

`scripts/pvp/item_pricing.gd` derives identified market bundle prices from
the supplied 4.0.2 `value()` implementations in MeleeWeapon, MissileWeapon,
ThrowingStone, Armor, Wand, Ring, Potion/Scroll subclasses, Plant.Seed,
Rotberry.Seed, Starflower.Seed, Runestone and its price-overriding subclasses.
The market cells reuse InventorySlot art, type icons and SpdPixelText counters;
their orange frame retains the original Chrome geometry. GPL-3.0-or-later.

The unchanged `step.mp3`, `water.mp3`, `grass.mp3`, `trample.mp3` and
`sturdy.mp3` in `assets/heroes/source/` are copied from upstream
`core/src/main/assets/sounds/`. Surface selection and pitch ranges follow
`Hero.move(int, boolean)`; PvP plays travelling audio on the matching jump landing.

Pixel Dungeon: Copyright (C) 2012–2015 Oleg Dolya.
Shattered Pixel Dungeon: Copyright (C) 2014–2026 Evan Debenham.

The unchanged `assets/items/source/items.png`, `item_icons.png` and `amulet.png`
come from upstream `core/src/main/assets/sprites/`. Item IDs, category names,
crop rectangles and placement rules are derived from `ItemSpriteSheet.java`
and `ItemSprite.java`. Generated item/icon `.tres` resources refer to the
original atlases. `source_catalog.json` records the upstream source SHA-256
and references in its item classes. `tools/item_assets/` executes the original
ItemSpriteSheet with a rectangle-capturing TextureFilm dependency to reproduce
its exact crop initialization, including loops and overrides.

These upstream-derived files are distributed under GNU GPL version 3 or later.
The yellow surprise marker in `scripts/melee/melee_effects.gd` adapts
`effects/Surprise.java` (SHA-256 `B925622C095C986718BB33475B259CFE658A519A8A27713FC8A430CBB58D490E`)
and the `Effects.EXCLAMATION` crop from the supplied 4.0.2 source, reusing
the unchanged `assets/wands/source/effects.png` atlas under GPL-3.0-or-later.
The unchanged `assets/effects/specks.png` is from upstream `core/src/main/assets/effects/`.
`scripts/environment/` adapts Blob and its 30 concrete environmental subclasses,
terrain interactions from Level, and particle behavior from BlobEmitter, Speck,
MagicMissile and particle classes. See `docs/environment.md`
for the exact port scope, host integration points and visual differences.

The full license is included as `LICENSE-SPD.txt`. Preserve this attribution
and the license when redistributing these files.

`assets/inventory/description_catalog.json` and `scripts/inventory/item_text.gd`
derive equipment detail templates, inherited message lookup, parameter formatting
and highlighted text from the supplied SPD 4.0.2 `items_zh.properties`, `Messages`,
`RenderedTextBlock`, and the item `info()` / `statsInfo()` methods. The text-only
importer is `tools/inventory/import_descriptions.mjs`; source hashes are recorded
in its output. PvP deliberately omits strength requirements, unidentified-item
branches and Duelist abilities. These adaptations use GPL-3.0-or-later.

The 21 PNGs in `assets/ui/source/` are copied unchanged from upstream
`core/src/main/assets/interfaces/`. `assets/ui/styles/`, `assets/ui/textures/`
and the UI theme derive from Chrome.java, NinePatch.java, StyledButton.java,
StatusPane.java, MenuPane.java, BossHealthBar.java and Toolbar.java. The Java
extraction tool executes the unchanged Chrome.java with recording dependency
stubs. Source hashes and extracted definitions are in `assets/ui/source_catalog.json`.
See `docs/ui_assets.md` for the resource index, integration and resource generation.

`scripts/vision/` derives from the supplied SPD 4.0.2 ShadowCaster.java,
Level.updateFieldOfView, Dungeon.observe, FogOfWar.java and WallBlockingTilemap.java.
The existing `assets/environment/wall_blocking.png` is used unchanged.
See `docs/vision.md` for scope and integration.

`scripts/inventory/` adapts the supplied SPD 4.0.2 `Item.java`, `Bag.java`,
`VelvetPouch.java`, `ScrollHolder.java`, `PotionBandolier.java`, `MagicalHolster.java`,
`Belongings.Backpack`, `EquipableItem.java`, `KindofMisc.java`, `Artifact.java`,
`QuickSlot.java`, `ItemSlot.java`, `InventorySlot.java`, `WndBag.java`,
`WndUseItem.java`, `WndInfoItem.java`, `WndQuickBag.java`, `RightClickMenu.java`,
`QuickSlotButton.java` and `Icons.java`. `assets/inventory/definitions.json` derives
from the supplied Java item classes and `messages/items/items_zh.properties`
and `messages/plants/plants_zh.properties`. `pixel_font.png` and `click.mp3`
are copied unchanged from upstream fonts/ and sounds/. The reproducible import
tool is `tools/inventory/import_source.ps1`. These files use GPL-3.0-or-later;
see `docs/inventory.md` for integration, demo behavior and scope limitations.
`scripts/inventory/spd_pixel_text.gd` adapts `BitmapText.Font.colorMarked`,
`BitmapText` measurements and `PixelScene.pixelFont` tracking/baseline to draw
the unchanged bitmap glyphs directly.

The unchanged six hero sheets in `assets/heroes/source/` come from upstream
`core/src/main/assets/sprites/`. `scripts/heroes/` adapts `HeroSprite.java`,
`CharSprite.java`, `HeroClass.spritesheet()`, `Hero.tier()` and `TextureFilm.java`.
The 42 `SpriteFrames` resources derive from the source animation definitions;
`tools/heroes/import_source.ps1` records source PNG and Java hashes, and
`tools/heroes/build_resources.gd` regenerates these resources. See `docs/heroes.md`
for frame mapping, scope and integration. These files use GPL-3.0-or-later.
The PvP one-cell movement uses HeroicLeap.java's jump call and CharSprite's
parabolic jump/shadow formulas and unmodified distance-scaled height/duration,
including Tweener's half-frame completion rule. The blast wave, screen shake
and gameplay ability effects are omitted.

The four unchanged PNGs in `assets/menu/source/` are from upstream
`core/src/main/assets/splashes/title/`. `scripts/menu/` adapts `TitleScene.java`,
`TitleBackground.java`, `StyledButton.java`, `ChangesScene.java` and `Icons.java`. Menu chrome and
icons use the previously imported original interface atlases, and button audio
uses the original click sound. `tools/menu/import_source.ps1` extracts source
crop/weight definitions and records SHA-256 hashes. See `docs/main_menu.md`.
These upstream-derived files are distributed under GPL-3.0-or-later.

`assets/ui/palettes/claude/` contains modified Godot texture resources derived
from the original chrome/status/menu/boss interface atlases. Red pixels use a
warm orange palette with the original shading and alpha; original PNGs remain
unchanged. `tools/ui/build_palette.gd` reproduces these resources. The orange
accent #D97757 is referenced from Claude Academy's published color example:
https://academy.claude.com/use-cases/package-your-brand-guidelines-in-a-skill
These derived artwork resources retain the upstream GPL-3.0-or-later license.

`scripts/status/` adapts `StatusPane.java`, `BuffIndicator.java`, `BuffIcon.java`,
`BusyIndicator.java`, `effects/CircleArc.java`,
`WndInfoBuff.java`, `HeroSprite.avatar()` and Noosa `Visual.tint()` from the
supplied Shattered Pixel Dungeon 4.0.2 source. It reuses the unchanged status,
large buff atlas and original bitmap font previously imported above.
`assets/status/source_catalog.json` derives 86 named icon IDs and five example
Chinese descriptions from `messages/actors/actors_zh.properties`; example icon
tints/text display derive from Burning, Poison, Haste, Paralysis and Barrier.
`tools/status/import_source.ps1` reproduces the catalog and records source hashes.
Experience/level UI is omitted and status chrome uses the existing orange palette.
These upstream-derived files use GPL-3.0-or-later; see `docs/character_status.md`.

`scripts/combat/` adapts upstream `effects/FloatingText.java`,
`sprites/CharSprite.showStatusWithIcon()`, `actors/Char.damage()`,
`RenderedTextBlock` and Noosa `RenderedText` logical text height. The unchanged
`assets/combat/source/text_icons.png` comes from upstream `effects/text_icons.png`.
The catalog includes 47 source icon constants and original Chinese dodge/block/parry
words from `messages/actors/actors_zh.properties`, with hashes recorded by
`tools/combat/import_source.ps1`. The unchanged `assets/ui/fonts/pixel_font.ttf`
comes from upstream `fonts/pixel_font.ttf`. Combat text uses this font for supported
Latin/numeric glyphs, following PlatformSupport with systemfont disabled; CJK uses
the project's existing MSDF font. Negative text uses the current orange theme. The adapter and derived catalog
use GPL-3.0-or-later. See `docs/combat_text.md` for scope and integration.

`scripts/status/buff_announcements.gd` and the status-added presentation path
adapt `actors/Char.add(Buff)`, `actors/buffs/Buff.attachTo()` and the original
`sprites/CharSprite` positive/warning/neutral colors. Named gameplay states use
the existing localized buff catalog; the game's announcement set includes states
whose upstream `announced` flag is disabled. Pool-backed buff gains use the same
first-attachment notification. The floating text adapter adds rendered-bounds
spacing across adjacent cells to keep status names and damage/healing apart.
These adapters retain GPL-3.0-or-later.

The client buff-name spacing in `CombatTextLayer` follows
`FloatingText.push` and `RenderedText.measure` from the supplied SPD 4.0.2
source: logical line height is round(size * 0.75) with a four-pixel stack gap.
Same-actor buff names retain that layout while mixed numeric/icon messages
and adjacent actors keep the additional collision avoidance described above.

`scripts/wands/` adapts the thirteen normal wand classes, Wand / DamageWand,
ConeAOE, MagicMissile / particle factories, Beam, Lightning, Effects and the
Ward / EarthGuardian / Lotus sprites from the supplied SPD 4.0.2 source.
`assets/wands/source/` contains eleven unchanged source images/audio files.
`tools/wands/import_source.ps1` records SHA-256 hashes and original Chinese stats.
These adapters, catalogs and source-derived data use GPL-3.0-or-later.
See `docs/wands.md` for integration and the boundary with independent game systems.

`scripts/menu/wand_sandbox.gd` stages the ten enabled wands in an isolated
journal preview using those wand rules, MagicMissile / Beam / Lightning,
PotionEffects status particles, the original BuffIndicator crops in
`assets/ui/source/buffs.png`, and CharHealthIndicator's shield bar. It reuses
the unchanged cave terrain and RatSprite assets documented above. These
source-derived adapters retain GPL-3.0-or-later; no new artwork is imported.

`scripts/menu/seed_sandbox.gd` stages the twelve seeds using the same local
world, `Plant.Seed.onThrow`/plant activation rules, native MissileSprite flight,
TerrainFeaturesTilemap growth, nature particles, ScrollEffects appear/flares,
and BuffIndicator icon crops. It reuses the unchanged seed item textures and
`assets/environment/terrain_features.png`; no new art is imported. This preview
adapter retains GPL-3.0-or-later.

`scripts/menu/stone_sandbox.gd` stages the six enabled runestones using the
same local NatureRules inventory/throw rules, NatureEffects, Lightning,
MeleeRules augmentation, Enchantment/Glyph rolls and ItemSprite.Glowing.
Sheep reuse `WandSummonSprite` and the unchanged original SheepSprite atlas
`assets/nature/source/sheep.png`. Existing item, cave, particle and buff
textures are reused; no new art is imported. This preview adapter retains
GPL-3.0-or-later.

`scripts/menu/missile_sandbox.gd` stages the fifteen enabled thrown weapons
with the existing MissileWorld resolve/return rules, MissileSprite rotation
and velocity, damage popups, native bleeding particles and BuffIndicator crops.
FishingSpear uses the unchanged `assets/menu/showcase/piranha.png` and native
PiranhaSprite idle sequence (including its submerged silhouette, 8 fps and
0.2-tile perspective raise), adapted by `equipment_piranha_sprite.gd`.
Texture and Java SHA-256 provenance is in `assets/menu/showcase/source_catalog.json`.
These preview adapters retain GPL-3.0-or-later. Seed movement now reuses the
existing battle client's HeroicLeap-style neighbouring-cell hop.

`scripts/menu/enchantment_sandbox.gd` stages the twelve retained weapon
enchantments with the actual local MeleeWorld / RunicGear rules. Catalog icons
follow WndJournal's Weapon.Enchantment branch: WORN_SHORTSWORD with the native
enchantment glow and localized enchantment name/description. It reuses the
existing ItemSprite.Glowing, nature particles, Lightning, BuffIndicator crops,
CharHealthIndicator and unchanged hero, rat and cave assets. Rat death uses
RatSprite.java's frames 11,12,13,14 at 10 fps. Local deterministic RNG only
stages native procs; Crystal reflects this project's five-hit PvP exception.
These source-derived adapters retain GPL-3.0-or-later; no new art is imported.

`scripts/menu/glyph_sandbox.gd` stages the twelve retained armor glyphs in
an isolated local rules world, sharing the enchantment preview's lifecycle
and native effects. Icons and localized titles/descriptions follow WndJournal's
Armor.Glyph branch (ARMOR_CLOTH with ItemSprite.Glowing). Movement, delayed
damage, charging, terrain and combat use the existing PvP rule adapters. It
reuses unchanged cloth, hero, rat, cave, wand and BuffIndicator artwork;
Swiftness/Flow specks reuse Speck.LIGHT's native frame, rotation/fade and
Speck.YELLOW_LIGHT/BLUE_LIGHT tints. These source-derived adapters retain
GPL-3.0-or-later; no new art is imported.

`scripts/potions/` adapts Potion.java, the twelve base PotionOf classes, Healing,
Haste / Invisibility / Levitation / MindVision / BlobImmunity / Frost, MissileSprite,
Splash / Speck / SpellSprite / Flare / IceBlock and SnowParticle from SPD 4.0.2.
`assets/potions/source/` contains six unchanged source image/audio files and reuses
the previously imported item, speck and environment art. Hashes and extracted
duration/concentration profiles are recorded by `tools/potions/import_source.ps1`.
The healing oracle compiles the actual original method body and amount expression.
These adapters and source-derived data use GPL-3.0-or-later. See `docs/potions.md`.

`scripts/navigation/dungeon_pathfinder.gd` ports the complete supplied
`SPD-classes/src/main/java/com/watabou/utils/PathFinder.java` (Oleg Dolya / Evan
Debenham), including full/bounded/target/multi-goal distance maps and escape rules.
Its instance workspace replaces Java static arrays. This port uses
GPL-3.0-or-later. The simple seeded room/corridor demonstration generator is
project code. See `docs/pathfinding.md` for integration.

`scripts/scrolls/` adapts Scroll.java / InventoryScroll and all twelve normal
ScrollOf classes from the supplied SPD 4.0.2 source, plus Drowsy / MagicalSleep /
Terror / Recharging, MirrorImage / MirrorSprite, Speck, Identification,
Transmuting, EnergyParticle, ShadowParticle.UP, Flare and PixelScene.Fader.
The known-item confirmation UI follows WndUpgrade; random transmutation pools
and exotic counterpart mappings derive from Generator / ExoticScroll / ExoticPotion.
`assets/scrolls/source/` contains seven unchanged source audio files; sprites reuse
previously imported original hero, item, speck and spell icon atlases.
`tools/scrolls/import_source.ps1` records SHA-256 hashes and extracted data.
These adapters, source-derived data and source resources use GPL-3.0-or-later.
See `docs/scrolls.md` for integration and the scope of the base scroll system.

`PotionOfSnapFreeze` now follows the supplied PotionOfSnapFreeze.java,
ExoticPotion.value, Freezing.affect, Frost and Roots rules, with the requested
PvP durations of 5 turns on land, 10 in water, and 5 for roots. It reuses the
unchanged EXOTIC_AZURE bottle, POTION_SNAPFREEZ icon and SnowParticle renderer.
`snap_freeze_sandbox.gd` stages the same real rules for journal and market
previews. The potion importer records Java source hashes and keeps original
and PvP durations separate. These adapters retain GPL-3.0-or-later; no new
art is imported. See `docs/potions.md` for behavior and validation.

`PotionOfStamina` and `PotionOfShielding` adapt the supplied exotic potion
classes, Stamina, Char.speed, Barrier and ShieldBuff. Requested PvP overrides
are 20 turns of Stamina and a fixed 20-point ordinary Barrier. They reuse
EXOTIC_SILVER / EXOTIC_CRIMSON, POTION_STAMINA / POTION_SHIELDING, native
HASTE / ARMOR icons, SpellSprite, CharHealthIndicator and floating text.
`restorative_potion_sandbox.gd` stages real movement, decay and damage rules
for journal and market previews. Source hashes, original values and separate
PvP overrides are recorded by `tools/potions/import_source.ps1`. These
adapters and derived data retain GPL-3.0-or-later; no new art is imported.

`PotionOfShroudingFog` ports the supplied PotionOfShroudingFog.shatter,
SmokeScreen, Blob diffusion and Level.updateFieldOfView. It uses the native
9 x 180 smoke volume and solid-neighbour redistribution, unchanged
EXOTIC_MAGENTA / POTION_SHROUDFOG art and existing Speck.SMOKE particles.
Both PvP observers use the existing p0 / p1 view calculation, so the thrower
also loses normal sight. `shrouding_fog_sandbox.gd` previews both actual
fields of view. The importer records these Java hashes and source values;
the adapters and derived data retain GPL-3.0-or-later.

`PotionOfStormClouds` and `PotionOfDragonsBreath` port the supplied exotic
potion classes, StormCloud, Fire, Burning, Cripple, ConeAOE, Ballistica and
MagicMissile.FIRE_CONE / FlameParticle. Storm uses native 9 x 120 volume;
Dragon's Breath uses aimed drinking, a 6-tile / 60-degree cone, five-volume
fires, eight-turn base Burning and five-turn Cripple. The existing terrain,
particles, EXOTIC_TURQUOISE / EXOTIC_BISTRE bottles and identified symbols
are unchanged. `elemental_potion_sandbox.gd` stages the real rules; the shared
PotionEffects drink/fire sequence retains native missile timing. Source
hashes and values are recorded by the potion importer. These adapters and
derived data retain GPL-3.0-or-later; no new artwork is imported.

`PotionOfEarthenArmor` / `Barkskin` / `Char.drRoll` and
`PotionOfCleansing` / `Char.add` are adapted from the supplied SPD 4.0.2
source. Requested Barkskin balance is a fixed initial eight-point physical
attack reduction, decreasing by one every three turns. Cleansing keeps the
native five-turn negative-buff protection and AllyBuff / LostInventory
exceptions, and reuses the native pink Flare. The original BARKSKIN / IMMUNITY
icons, EXOTIC_CHARCOAL / EXOTIC_IVORY bottles and identified symbols are
unchanged. `protective_potion_sandbox.gd` demonstrates actual mitigation,
decay, drinking and thrown cleansing. Source hashes, original and PvP values
are recorded by the potion/status importers. Adapters and derived data
retain GPL-3.0-or-later; no new artwork is imported.

`scripts/rings/` adapts Ring.java and all twelve RingOf classes from the supplied
SPD 4.0.2 source, including effective/raw bonuses, Degrade / EnhancedRings /
MagicImmune, Hero and Char stat/damage queries, BrawlersStance, Blazing,
MissileWeapon durability and RingOfWealth counters / rewards / Flare colors.
Ring sprites reuse the unchanged imported item atlases. Original Chinese stats,
Generator pools, equipment tiers and enchantment/glyph weights are extracted by
`tools/rings/import_source.ps1`, with SHA-256 recorded in the derived catalog.
These adapters and source-derived data use
GPL-3.0-or-later. See `docs/rings.md` for integration and independent equipment
system boundaries.

The scripts/missiles adapter ports SPD 4.0.2 MissileWeapon.java, fifteen normal
projectile classes, Dart.java, twelve TippedDart subclasses, PinCushion, Bleeding,
HeavyBoomerang.CircleBack, ShurikenInstantTracker, Crossbow dart queries,
UpgradedSetTracker and MissileSprite. It reuses the unchanged item / hero /
effect atlases. Six unchanged hit/crossbow MP3s are copied to assets/missiles/source.
tools/missiles/import_source.ps1 extracts profiles, seed recipes and source hashes.
These adapters, source-derived data and
resources use GPL-3.0-or-later. See docs/missiles.md for integration and PvP adaptations.
