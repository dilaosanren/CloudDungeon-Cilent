# SPD UI art / Chrome / StyledButton adaptation. GPL-3.0-or-later; see LICENSE-SPD.txt.
class_name UiAssets
extends RefCounted

static var _catalog: Dictionary = {}
static var _styles: Dictionary = {}
static var _textures: Dictionary = {}
static var _theme: Theme
static var _pixel_font: FontFile
static var _mixed_font: FontFile
static var _ui_font: FontVariation
static var _scaled_fonts: Dictionary = {}
static var _native_ui_font: FontVariation
const UI_FONT = preload("res://assets/ui/themes/ui_font.tres")
# Twice the previous size 2 stroke; the font's SDF range also accommodates it.
const TEXT_OUTLINE_SIZE := 4

## SPD uses the pixel font for Latin/numerals even inside Chinese text.
## Keep a stable resource shared by themes and explicit font overrides.
static func get_font() -> Font:
	if _ui_font == null:
		# Separate from combat text's native raster settings and glyph checks.
		_mixed_font = get_pixel_font().duplicate()
		# Binary pixel edges avoid gray fringes; retain the raster density needed
		# by 2x menus so narrow strokes and spaces are not lost at small sizes.
		_mixed_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_mixed_font.oversampling = 2.0
		_mixed_font.fallbacks = [UI_FONT]
		_ui_font = FontVariation.new()
		_ui_font.base_font = _mixed_font
	return _ui_font

## PixelScene.renderTextBlock rasterizes at the final UI/device pixel size.
## Control.scale is not included in FontFile's fixed oversampling factor.
static func get_font_at_scale(scale: float) -> Font:
	var density := clampi(ceili(scale), 2, 8)
	if density == 2: return get_font()
	if not _scaled_fonts.has(density):
		get_font()
		var raster: FontFile = _mixed_font.duplicate()
		raster.oversampling = float(density)
		var font := FontVariation.new()
		font.base_font = raster
		_scaled_fonts[density] = font
	return _scaled_fonts[density]

## Used when a text control already draws one font pixel per device pixel.
static func get_native_ui_font() -> Font:
	if _native_ui_font == null:
		get_font()
		var raster: FontFile = _mixed_font.duplicate()
		raster.oversampling = 1.0
		# Native-sized text needs a native-sized CJK outline as well. An MSDF
		# fallback uses its atlas-distance scale and makes this border too thin.
		# The bundled CJK font works on Android without system-font discovery.
		var cjk: FontFile = UI_FONT.base_font.duplicate()
		cjk.multichannel_signed_distance_field = false
		cjk.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		cjk.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		cjk.oversampling = 1.0
		raster.fallbacks = [cjk]
		_native_ui_font = FontVariation.new()
		_native_ui_font.base_font = raster
	return _native_ui_font

## Original PlatformSupport basicFontGenerator for Latin/numerals (systemfont=false).
## This TTF is distinct from the tiny pixel_font.png used by inventory counters.
static func get_pixel_font() -> FontFile:
	if _pixel_font == null:
		_pixel_font = load("res://assets/ui/fonts/pixel_font.ttf")
		# FreeType's original grayscale coverage, generated at the final display size.
		_pixel_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_pixel_font.hinting = TextServer.HINTING_NONE
		_pixel_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_pixel_font.allow_system_fallback = false
		_pixel_font.oversampling = 1.0
	return _pixel_font

static func apply_text_outline(control: Control) -> void:
	control.add_theme_color_override("font_outline_color", Color.BLACK)
	control.add_theme_constant_override("outline_size", TEXT_OUTLINE_SIZE)

static func apply_theme_text_outline(theme: Theme) -> void:
	for type in ["Label", "TooltipLabel", "RichTextLabel", "Button", "TextEdit", "LineEdit"]:
		theme.set_color("font_outline_color", type, Color.BLACK)
		theme.set_constant("outline_size", type, TEXT_OUTLINE_SIZE)

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/ui_catalog.json"))
	return _catalog.duplicate(true)

static func list_styles(category: String = "") -> Array[String]:
	var result: Array[String] = []
	for entry in catalog().styles:
		if category.is_empty() or entry.category == category:
			result.append(entry.name)
	return result

static func get_style(name: String) -> StyleBoxTexture:
	# Orange is the actual resource; the upstream red name is compatibility only.
	var key := "ORANGE_BUTTON" if name.to_upper() == "RED_BUTTON" else name.to_upper()
	if _styles.has(key): return _styles[key]
	# Explicit opt-in to the upstream red art, bypassing the orange palette.
	if key == "ORIGINAL_RED_BUTTON":
		_styles[key] = preload("res://assets/ui/styles/buttons/original_red_button.tres")
		return _styles[key]
	for entry in catalog().styles:
		if entry.name == key:
			var original: StyleBoxTexture = load(entry.resource)
			var style: StyleBoxTexture = original.duplicate()
			style.texture = UiPalette.texture(original.texture)
			_styles[key] = style
			return style
	return null

static func get_texture(name: String) -> Texture2D:
	var key := name.to_upper()
	if key == "RED_BUTTON": key = "ORANGE_BUTTON"
	if _textures.has(key): return _textures[key]
	for entry in catalog().textures:
		if entry.name == key:
			var texture: AtlasTexture = load(entry.resource).duplicate()
			texture.atlas = UiPalette.texture(texture.atlas)
			_textures[key] = texture
			return texture
	for entry in catalog().raw:
		if entry.name == name.to_upper():
			return load("res://assets/ui/source/" + entry.file)
	return null

static func get_theme() -> Theme:
	if _theme == null:
		var original: Theme = load("res://assets/ui/themes/dungeon_ui.tres")
		_theme = original.duplicate()
		_theme.default_font = get_font()
		for type in _theme.get_type_list():
			for style_name in _theme.get_stylebox_list(type):
				var style := original.get_stylebox(style_name, type).duplicate()
				if style is StyleBoxTexture: style.texture = UiPalette.texture(original.get_stylebox(style_name, type).texture)
				_theme.set_stylebox(style_name, type, style)
		_theme.set_type_variation("RedButton", "OrangeButton")
	return _theme

## Mirrors StyledButton: unchanged hover, 1.2 brightness on press, only text fades when disabled.
## Custom styles are duplicated so callers cannot accidentally mutate shared resource states.
static func apply_button_style(button: Button, name: String = "ORANGE_BUTTON") -> bool:
	var base := get_style(name)
	if base == null:
		return false
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for state in ["normal", "hover", "disabled", "hover_pressed"]:
		button.add_theme_stylebox_override(state, base.duplicate())
	var pressed: StyleBoxTexture = base.duplicate()
	pressed.modulate_color = Color(1.2, 1.2, 1.2, 1)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed.duplicate())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.3))
	apply_text_outline(button)
	return true

static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = get_font()
	theme.default_font_size = 18
	apply_theme_text_outline(theme)
	for entry in [["Button", "ORANGE_BUTTON"], ["OrangeButton", "ORANGE_BUTTON"],
		["GreyButton", "GREY_BUTTON"], ["TransparentButton", "GREY_BUTTON_TR"]]:
		if entry[0] != "Button":
			theme.set_type_variation(entry[0], "Button")
		var button := Button.new()
		apply_button_style(button, entry[1])
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			theme.set_stylebox(state, entry[0], button.get_theme_stylebox(state))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
			theme.set_color(state, entry[0], button.get_theme_color(state))
		button.free()
	# Old scenes using the original variation inherit the same orange states.
	theme.set_type_variation("RedButton", "OrangeButton")
	for type in ["Panel", "PanelContainer", "PopupPanel", "PopupMenu"]:
		theme.set_stylebox("panel", type, get_style("WINDOW"))
	for type in ["TabContainer", "TabBar"]:
		theme.set_stylebox("tab_selected", type, get_style("TAB_SELECTED"))
		theme.set_stylebox("tab_unselected", type, get_style("TAB_UNSELECTED"))
		theme.set_stylebox("tab_hovered", type, get_style("TAB_UNSELECTED"))
	theme.set_stylebox("panel", "TabContainer", get_style("TAB_SET"))
	return theme
