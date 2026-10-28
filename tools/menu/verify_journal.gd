extends Node
## Offline real input/navigation checks, including narrow/landscape/notched layouts.
const Journal = preload("res://scripts/menu/journal_scene.gd")
const L10n = preload("res://scripts/menu/game_locale.gd")
var _failed := false

func _ready() -> void: _run.call_deferred()
func _expect(ok: bool,message: String) -> void:
	if not ok:
		_failed = true
		push_error(message)
func _settle() -> void:
	for frame in 5: await get_tree().process_frame
func _resize(dimensions: Vector2i,notched: bool) -> void:
	get_window().min_size = Vector2i(240,320)
	get_window().content_scale_size = dimensions
	get_window().size = dimensions
	ScreenLayout.safe_area_override = Rect2i(get_window().position+Vector2i(10,24),dimensions-Vector2i(20,40)) if notched else Rect2i()
	await _settle()
func _tap(button: Control) -> void:
	var position := button.get_global_transform_with_canvas()*(button.size/2)
	var motion := InputEventMouseMotion.new()
	motion.position = position
	Input.parse_input_event(motion)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame
	await _settle()
func _capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/pvp-runtime/journal-ui/%s.png" % name)
func _screen_rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,control.size)
func _menu(menu: Control) -> void:
	var safe := ScreenLayout.safe_rect(get_viewport()).grow(1)
	_expect(menu.buttons.has("journal") and not menu.buttons.journal.disabled,"The new Journal entry is available while offline")
	_expect(menu.buttons.journal.caption_view.text==L10n.text("日志"),"The menu journal caption follows the selected language")
	for id in menu.buttons:
		_expect(safe.encloses(_screen_rect(menu.buttons[id])),"Every existing menu entry remains inside the safe area: "+id)
		for other in menu.buttons:
			if id!=other: _expect(not _screen_rect(menu.buttons[id]).intersects(_screen_rect(menu.buttons[other])),"The added journal button cannot overlap another entry")
	_expect(menu.destinations.history=="res://scenes/battle_history.tscn" and menu.destinations.changes=="res://scenes/changes.tscn","Existing history and changelog destinations are preserved")
func _page(screen: Control,index: int) -> void:
	var safe := ScreenLayout.safe_rect(get_viewport()).grow(1)
	_expect(screen.current_tab==index and screen._pages.size()==2 and screen._tabs.size()==2,"Exactly the two requested journal pages are available")
	_expect(screen._heading.text==L10n.text("日志"),"The independent journal screen retains its journal heading")
	for control in [screen._panel,screen._back,screen._heading,screen._heading_icon]+screen._tabs:
		_expect(safe.encloses(_screen_rect(control)),"The journal panel, title, back button and tabs fit the safe area")
	for i in 2:
		_expect(screen._pages[i].visible==(i==index) and screen._tabs[i].button_pressed==(i==index),"Real icon taps select one page and one icon")
		_expect(screen._tabs[i].caption_view.text.is_empty(),"Bottom navigation uses only icons")
		_expect(screen._tabs[i].size.y==(25 if i==index else 20),"The selected tab has the source JournalScene's taller shape")
		if i==Journal.BADGES_TAB:
			_expect(screen._pages[i].get_rect().encloses(screen._notices[i].get_rect()),"The badges construction notice fits inside its page")
			_expect((screen._notices[i].position+screen._notices[i].size/2).distance_to(screen._pages[i].size/2)<1.5,"The badges placeholder is centered")
			_expect(screen._messages[i].text==L10n.text("正在施工"),"Badges retain the requested construction message")
			_expect(screen._warning_icons[i].texture is AtlasTexture and screen._warning_icons[i].texture.region==Rect2(32,32,14,14),"The construction message uses the original WARNING crop")
		else:
			_expect(not screen._notices[i].visible,"Equipment replaces its construction notice")
		_expect(screen._page_headings[i].text==L10n.text("装备预览" if i==Journal.EQUIPMENT_TAB else "徽章"),"Page headings make the two icon destinations clear")
		_expect(screen._tabs[i].icon_view.texture==MenuAssets.icon("CATALOG" if i==Journal.EQUIPMENT_TAB else "BADGES"),"Tab icons follow the requested equipment-first order")
	_expect(not get_tree().quit_on_go_back,"Android Back is handled by the journal screen")
	if index==Journal.EQUIPMENT_TAB: _catalog(screen)

func _catalog_pool(category: String) -> Array:
	var pool: Array = []
	match category:
		"weapon":
			pool = MeleeRules.types().duplicate()
			pool.erase("MagesStaff")
			pool.erase("Pickaxe")
		"armor": pool = ArmorRules.TYPES.duplicate()
		"missile": pool = MissileRules.NORMAL_TYPES.duplicate()
		"wand": pool = WandState.TYPES.duplicate()
		"seed": pool = preload("res://scripts/nature/nature_rules.gd").SEEDS.duplicate()
		"stone": pool = preload("res://scripts/nature/nature_rules.gd").STONES.duplicate()
	return preload("res://scripts/pvp/item_availability.gd").filter_types(pool)

func _catalog(screen: Control) -> void:
	var catalog: Control = screen._equipment
	_expect(catalog._groups.size()==11,"Equipment, potions, separate exotic potions, enchantments and glyphs are listed")
	_expect(Rect2(Vector2.ZERO,screen._pages[Journal.EQUIPMENT_TAB].size).encloses(catalog.get_rect()),"The equipment catalog fits below its page heading")
	_expect(catalog.position.y>=screen._page_headings[Journal.EQUIPMENT_TAB].get_rect().end.y,"Catalog does not overlap its page heading")
	var expected_counts := [31,5,15,10,10,9,12,6,10,12,12]
	var categories := ["weapon","armor","missile","wand","potion","scroll","seed","stone","exotic_potion","enchantment","glyph"]
	var titles := ["近战武器","护甲","投掷武器","法杖","药剂","卷轴","种子","符石","合剂","武器附魔","护甲刻印"]
	_expect(preload("res://scripts/pvp/item_availability.gd").filter_types(PotionWorld.TYPES).size()==20,"Journal grouping preserves all twenty available potions")
	var previous_bottom := 0.0
	for index in categories.size():
		var group: Dictionary = catalog._groups[index]
		var heading: Label = group.title
		_expect(heading.text=="%s (%d)"%[L10n.text(titles[index]),expected_counts[index]],"Category titles, counts and language match the current equipment")
		_expect(heading.position.y>=previous_bottom,"Category headings do not overlap preceding equipment")
		_expect(heading.get_minimum_size().x<=heading.size.x,"Category headings fit even on narrow screens")
		var actual: Array = []
		for tile in group.tiles:
			actual.append(str(tile.get_meta("type_id")))
			_expect(tile.get_rect().end.x<=catalog._content.size.x and tile.position.y>=heading.get_rect().end.y,"Equipment grid tiles fit their category and available width")
			_expect(tile.size==Vector2(17,17),"Grid uses the source 17px equipment tiles")
			_expect(tile.get_child(0).texture!=null,"Every listed item has its original sprite")
			_expect(tile.tooltip_text.is_empty() and tile is BaseButton,"Equipment tiles open previews without adding tooltips")
			previous_bottom=maxf(previous_bottom,tile.get_rect().end.y)
		var expected: Array = _catalog_pool(categories[index])
		if categories[index]=="potion":
			expected = ["PotionOfHealing","PotionOfHaste","PotionOfInvisibility","PotionOfLevitation","PotionOfMindVision","PotionOfPurity","PotionOfToxicGas","PotionOfParalyticGas","PotionOfLiquidFlame","PotionOfFrost"]
		elif categories[index]=="exotic_potion":
			expected = ["PotionOfSnapFreeze","PotionOfStamina","PotionOfShielding","PotionOfShroudingFog","PotionOfStormClouds","PotionOfDragonsBreath","PotionOfEarthenArmor","PotionOfCleansing","PotionOfCorrosiveGas","PotionOfMagicalSight"]
		elif categories[index]=="scroll":
			expected = ["ScrollOfLullaby","ScrollOfMagicMapping","ScrollOfMirrorImage","ScrollOfRecharging","ScrollOfRetribution","ScrollOfTeleportation","ScrollOfTerror","ScrollOfTransmutation","ScrollOfUpgrade"]
		elif categories[index]=="enchantment":
			expected = ["Enchantment_blazing","Enchantment_chilling","Enchantment_shocking","Enchantment_venomous","Enchantment_blocking","Enchantment_blooming","Enchantment_elastic","Enchantment_projecting","Enchantment_vorpal","Enchantment_crystal","Enchantment_grim","Enchantment_vampiric"]
		elif categories[index]=="glyph":
			expected = ["Glyph_swiftness","Glyph_viscosity","Glyph_potential","Glyph_brimstone","Glyph_stone","Glyph_entanglement","Glyph_repulsion","Glyph_camouflage","Glyph_flow","Glyph_affection","Glyph_antimagic","Glyph_thorns"]
		actual.sort()
		expected.sort()
		_expect(actual==expected and actual.size()==expected_counts[index],"Catalog lists exactly the current selectable equipment, without excluded or quest items")
	_expect(catalog._content.custom_minimum_size.y>=previous_bottom,"All equipment is included in the scroll range")

func _catalog_input(screen: Control) -> void:
	var catalog: Control = screen._equipment
	catalog._scroll.scroll_vertical=0
	await _settle()
	# The animated background can add sprites while input is being tested.
	# Check the UI/modal hosts rather than counting those unrelated nodes.
	var hosts: Array[Node] = [get_tree().root,screen,screen._canvas,screen._panel,screen._pages[Journal.EQUIPMENT_TAB],catalog]
	var before: Array = hosts.map(func(host: Node): return host.get_child_count())
	var first: Control = catalog._groups[0].tiles[0]
	await _tap(first)
	_expect(is_instance_valid(screen._equipment_preview) and screen._equipment_preview.item.type_id==str(first.get_meta("type_id")),"Tapping equipment opens its own preview")
	_expect(get_tree().current_scene==screen and screen.current_tab==Journal.EQUIPMENT_TAB,"Opening equipment keeps the catalog selected")
	if is_instance_valid(screen._equipment_preview):
		screen._equipment_preview.close()
		await _settle()
	_expect(hosts.map(func(host: Node): return host.get_child_count())==before,"Closing a preview restores the catalog without leaked windows")
	# Click each moved entry through the actual new group. The item keeps its
	# potion category and its existing animated preview, including type symbols.
	if not L10n.is_english() and get_window().size==Vector2i(360,640):
		for tile in catalog._groups[8].tiles:
			catalog._scroll.scroll_vertical = maxi(0,int(tile.position.y-catalog._scroll.size.y/2))
			await _settle()
			await _tap(tile)
			var preview: Control = screen._equipment_preview
			_expect(is_instance_valid(preview) and preview.item.type_id==str(tile.get_meta("type_id")),"A moved exotic entry opens its own preview")
			if is_instance_valid(preview):
				_expect(preview.item.category=="potion" and preview.sandbox!=null and preview.sandbox._active,"Exotic grouping retains the native potion type and animation")
				preview.close()
				await _settle()
		catalog._scroll.scroll_vertical = 0
		await _settle()
	var origin := _screen_rect(catalog._scroll).get_center()
	for step in 5:
		var wheel := InputEventMouseButton.new()
		wheel.position=origin
		wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed=true
		Input.parse_input_event(wheel)
		wheel=wheel.duplicate()
		wheel.pressed=false
		Input.parse_input_event(wheel)
	await _settle()
	if catalog._content.size.y>catalog._scroll.size.y:
		_expect(catalog._scroll.scroll_vertical>0,"Mouse wheel scrolls over equipment tiles")
	# Also exercise dragging through the tiles, as on an Android touch screen.
	catalog._scroll.scroll_vertical=0
	await _settle()
	var touch := InputEventScreenTouch.new()
	touch.index=0
	touch.position=origin+Vector2(0,35)
	touch.pressed=true
	Input.parse_input_event(touch)
	for step in 6:
		var drag := InputEventScreenDrag.new()
		drag.index=0
		drag.position=origin+Vector2(0,35-step*12)
		drag.relative=Vector2(0,-12)
		Input.parse_input_event(drag)
		await get_tree().process_frame
	var release := InputEventScreenTouch.new()
	release.index=0
	release.position=origin-Vector2(0,25)
	release.pressed=false
	Input.parse_input_event(release)
	# End any mouse emulation of the synthetic touch on a desktop viewport.
	var mouse_release := InputEventMouseButton.new()
	mouse_release.position=release.position
	mouse_release.button_index=MOUSE_BUTTON_LEFT
	mouse_release.pressed=false
	Input.parse_input_event(mouse_release)
	await _settle()
	if catalog._content.size.y>catalog._scroll.size.y:
		_expect(catalog._scroll.scroll_vertical>0,"Touch dragging scrolls through equipment tiles")
	_expect(not is_instance_valid(screen._equipment_preview),"Scrolling across clickable tiles must not open a preview")
	catalog._scroll.scroll_vertical=100000
	await _settle()
	var last: Control = catalog._groups.back().tiles.back()
	_expect(_screen_rect(last).end.y<=_screen_rect(catalog._scroll).end.y+1,"The final wand can be reached at the scroll bottom")
	await _capture("equipment-bottom-%s-%dx%d"%["en" if L10n.is_english() else "zh",get_window().size.x,get_window().size.y])
	catalog._scroll.scroll_vertical=0
	await _settle()

func _run() -> void:
	PvpNet._endpoint_loaded = true
	PvpNet._endpoint = {}
	Journal.last_tab = Journal.EQUIPMENT_TAB
	var previous_back := get_tree().quit_on_go_back
	var original_name := ClientPrefs.session_player_name()
	# Keep this test harness alive while the real current scene changes.
	get_tree().current_scene = null
	var menu := load("res://scenes/main_menu.tscn").instantiate() as Control
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	var count := 0
	for language in ["zh","en"]:
		L10n.set_language(language)
		for dimensions in [Vector2i(360,640),Vector2i(240,320),Vector2i(960,540)]:
			for notched in [false,true]:
				await _resize(dimensions,notched)
				menu = get_tree().current_scene
				_menu(menu)
				if dimensions==Vector2i(360,640) and not notched: await _capture("menu-%s"%language)
				await _tap(menu.buttons.journal)
				var screen := get_tree().current_scene as Control
				_expect(screen!=null and screen.scene_file_path=="res://scenes/journal.tscn","A real main-menu tap opens the journal scene")
				if screen==null or screen.scene_file_path!="res://scenes/journal.tscn": get_tree().quit(1); return
				_expect(screen.current_tab==Journal.EQUIPMENT_TAB,"The journal initially opens on its first equipment page")
				for index in [Journal.BADGES_TAB,Journal.EQUIPMENT_TAB,Journal.BADGES_TAB,Journal.EQUIPMENT_TAB]:
					await _tap(screen._tabs[index])
					_page(screen,index)
					if dimensions==Vector2i(360,640) and not notched: await _capture("journal-%s-%d"%[language,index])
				if not notched: await _catalog_input(screen)
				# Live language switching keeps the same active page and valid layout.
				L10n.set_language("en" if language=="zh" else "zh")
				await _settle()
				_page(screen,Journal.EQUIPMENT_TAB)
				L10n.set_language(language)
				await _settle()
				if dimensions==Vector2i(960,540) and not notched: await _capture("journal-landscape-%s"%language)
				if count%3==0: await _tap(screen._back)
				elif count%3==1:
					var escape := InputEventKey.new()
					escape.keycode = KEY_ESCAPE
					escape.pressed = true
					Input.parse_input_event(escape)
					await _settle()
				else:
					screen.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
					await _settle()
				menu = get_tree().current_scene
				_expect(menu!=null and menu.scene_file_path=="res://scenes/main_menu.tscn","Exit icon, Escape and Android Back all return to the main menu")
				_expect(get_tree().quit_on_go_back==previous_back and ClientPrefs.session_player_name()==original_name,"Journal navigation restores Back behavior and preserves the player name")
				await _tap(menu.buttons.journal)
				screen = get_tree().current_scene
				_page(screen,Journal.EQUIPMENT_TAB)
				_expect(screen.current_tab==Journal.EQUIPMENT_TAB,"The journal remembers its selected page within the session like SPD")
				await _tap(screen._back)
				count += 1
	ScreenLayout.safe_area_override = Rect2i()
	L10n.set_language("zh")
	var current := get_tree().current_scene
	get_tree().current_scene = null
	current.free()
	print("JOURNAL_UI_LAYOUT_CASES ",count)
	print("JOURNAL_UI_CHECKS ","FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)
