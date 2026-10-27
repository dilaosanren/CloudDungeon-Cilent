extends "res://tools/menu/verify_journal.gd"
const Catalog = preload("res://scripts/menu/equipment_catalog.gd")
const Preview = preload("res://scripts/menu/equipment_preview.gd")

func _capture_preview(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/pvp-runtime/equipment-sandbox/%s.png" % name)

func _wait_for_hit(sandbox: Control, count: int, timeout_msec: int = 2000) -> void:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while sandbox.attacks_resolved < count and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(sandbox.attacks_resolved == count, "The actual hero animation resolves exactly one hit")

func _check_layout(preview: Control) -> void:
	var safe := ScreenLayout.safe_rect(get_viewport()).grow(1)
	for control in [preview.panel, preview._back]:
		_expect(safe.encloses(_screen_rect(control)), "Preview frame and close button fit the safe area: %s rect=%s safe=%s" % [control.name, _screen_rect(control), safe])
	_expect(preview.panel.get_rect().size == preview._content.size, "The single content area fits its frame")
	_expect(preview._info.text.font_size == 6, "Combined preview retains native 6px item text")
	var expected: String = Catalog.entry_description(preview.item) if Catalog.is_runic(preview.item) else preview._details._item_description(preview.item)
	_expect(preview._info.text.text == InventoryUI.ItemText.markup(expected), "Description matches the inspected item or enchantment")
	var tail: Control = preview.sandbox if preview.sandbox != null else preview._notice
	_expect(is_equal_approx(tail.position.y, preview._info.scroll.get_rect().end.y + Preview.SECTION_GAP), "Animation follows directly after the description")
	_expect(is_equal_approx(preview.panel.size.y, tail.get_rect().end.y + Preview.BOTTOM_MARGIN), "The frame ends just below its content")
	_expect(Rect2(Vector2.ZERO, preview.panel.size).encloses(tail.get_rect()), "The animation remains inside the window")
	var content_height := ceilf(preview._info.text.get_content_height())
	_expect(preview._info.scroll.size.y <= maxf(12, content_height + 2) + 0.1, "Short descriptions never reserve an empty text page")
	if preview.sandbox != null:
		_expect(preview.sandbox._active and preview.sandbox.is_visible_in_tree(), "Description and animation are visible together without tab navigation")
		_expect(preview.sandbox.clip_contents, "Floating damage cannot overlap the description")
		var floor_extent: Vector2 = Vector2(preview.sandbox.map.map_size * 16) * preview.sandbox.map.scale
		_expect(floor_extent.x <= 64 and floor_extent.y <= 48, "The animation floor and characters use the requested smaller presentation")

func _check_content_fit(journal: Control) -> void:
	await _resize(Vector2i(360, 640), false)
	for language in ["zh", "en"]:
		L10n.set_language(language)
		journal._open_equipment("Dagger")
		for frame in 10: await get_tree().process_frame
		var preview: Control = journal._equipment_preview
		_check_layout(preview)
		var short_size: Vector2 = preview.panel.size
		var original_zoom: Vector2 = preview._canvas.scale
		await _capture_preview("combined-short-%s" % language)
		preview.item.note = ("这是测试用的长说明，用于检查文字滚动时窗口和动画的布局。\n" if language == "zh" else "Long description for checking scrolling, window sizing and animation layout.\n").repeat(40)
		preview.refresh_text()
		for frame in 10: await get_tree().process_frame
		_check_layout(preview)
		_expect(preview.panel.size.y > short_size.y, "Long descriptions expand the window")
		_expect(preview._canvas.scale == original_zoom, "Text length never shrinks the font or animation")
		_expect(preview._info.text.get_content_height() > preview._info.scroll.size.y, "Very long descriptions use a bounded scroll area")
		var long_size: Vector2 = preview.panel.size
		for frame in 8:
			await get_tree().process_frame
			_expect(preview.panel.size.is_equal_approx(long_size), "Auto sizing settles without frame-to-frame resizing")
		var origin := _screen_rect(preview._info.scroll).get_center()
		for step in 5:
			var wheel := InputEventMouseButton.new()
			wheel.position = origin
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
			wheel.pressed = true
			Input.parse_input_event(wheel)
			wheel = wheel.duplicate()
			wheel.pressed = false
			Input.parse_input_event(wheel)
		await _settle()
		_expect(preview._info.scroll.scroll_vertical > 0, "Mouse wheel reaches text beyond the visible description")
		_expect(preview.panel.size == long_size and preview.sandbox._active, "Scrolling text keeps the animation visible and running")
		await _capture_preview("combined-long-%s" % language)
		preview.item.note = ""
		preview.refresh_text()
		for frame in 10: await get_tree().process_frame
		_check_layout(preview)
		_expect(preview.panel.size.is_equal_approx(short_size), "Shortening the description removes the extra window height")
		preview.close()
		await _settle()
	L10n.set_language("zh")

func _check_armors(journal: Control) -> int:
	var count := 0
	for type_id in Catalog.types("armor"):
		journal._open_equipment(type_id)
		await _settle()
		var preview: Control = journal._equipment_preview
		var sandbox: Control = preview.sandbox
		_expect(sandbox != null and preview._notice == null, "Every current armor has a real animation page")
		if sandbox == null:
			preview.close()
			await _settle()
			continue
		_check_layout(preview)
		_expect(sandbox.hero_sprite.armor_tier == ArmorRules.tier(preview.item), "The warrior wears the inspected armor tier: " + type_id)
		_expect(sandbox.warrior.data.armor_item == preview.item and sandbox.world.weapon(sandbox.warrior) == null, "Armor protection is equipped without a melee weapon")
		_expect(sandbox.attacker == sandbox.rat and sandbox.defender == sandbox.warrior, "The rat attacks the warrior in armor demonstrations")
		_expect(MeleeRules.damage_range(null, sandbox.rat) == Vector2i(4, 4), "Rat base damage is fixed at exactly four")
		_expect(sandbox.world.grid_distance(sandbox.rat.cell, sandbox.warrior.cell) == 1, "Rat stands next to the warrior")
		var attack_frames: SpriteFrames = sandbox.rat_sprite.body.sprite_frames
		_expect(attack_frames.get_frame_count(&"attack") == 5 and attack_frames.get_animation_speed(&"attack") == 15, "Rat retains its original five-frame attack at 15 FPS")
		for index in 5:
			_expect(attack_frames.get_frame_texture(&"attack", index).region == Rect2([2, 3, 4, 5, 0][index] * 16, 0, 16, 15), "Original RatSprite attack frame order is preserved")
		var expected := maxi(0, 4 - ArmorRules.defense(preview.item, sandbox.warrior))
		preview.show()
		sandbox.demonstrate_attack()
		_expect(sandbox.rat_sprite.body.animation == &"attack" and sandbox.hero_sprite.body.animation == &"idle", "Only the rat plays an attack animation")
		_expect(sandbox.attacks_resolved == 0 and sandbox.warrior.hp == sandbox.warrior.max_hp, "Armor damage waits for the rat's animation")
		await _wait_for_hit(sandbox, 1)
		_expect(sandbox.last_result.get("hit", false) and sandbox.last_result.get("damage", -1) == expected, "Real armor mitigation from a four-point attack: " + type_id)
		_expect(sandbox.warrior.hp == sandbox.warrior.max_hp and sandbox.warrior in sandbox.world.actors, "The player is restored after every demonstration hit")
		_expect(sandbox.hero_sprite._flash_time > 0 and sandbox.rat_sprite._flash_time == 0, "Hit flash appears on the warrior rather than the attacking rat")
		var text_layer := sandbox.map.get_node_or_null("CombatText") as CombatTextLayer
		var found_damage := false
		if text_layer != null:
			for popup in text_layer.active_texts():
				if popup.text == str(expected):
					found_damage = true
					_expect(popup.position.x < 32, "Armor damage popup is anchored to the warrior")
		_expect(found_damage, "Armor shows actual received damage, including zero")
		if type_id in ["ClothArmor", "PlateArmor"]:
			await get_tree().create_timer(0.1).timeout
			await _capture_preview("armor-%s-zh" % type_id)
		if type_id == "ClothArmor":
			await _wait_for_hit(sandbox, 2, 6000)
			_expect(sandbox.last_result.get("damage", -1) == 3 and sandbox.warrior.hp == sandbox.warrior.max_hp, "Automatic repetition retains fixed damage and never kills the warrior")
			# Pausing halfway through a rat swing must not cause a hidden hit.
			sandbox.demonstrate_attack()
			preview.hide()
			await get_tree().create_timer(0.5).timeout
			_expect(sandbox.attacks_resolved == 2 and sandbox.rat_sprite.body.animation == &"idle", "Hiding the window cancels an unfinished rat attack")
			preview.show()
			sandbox.demonstrate_attack()
			await _wait_for_hit(sandbox, 3)
		L10n.set_language("en")
		await _settle()
		_check_layout(preview)
		_expect(preview._details._item_description(preview.item).contains(ArmorRules.stats(preview.item)), "English armor description includes current protection")
		if type_id == "PlateArmor": await _capture_preview("armor-text-PlateArmor-en")
		var world: MeleeWorld = sandbox.world
		preview.close()
		await _settle()
		_expect(world.actors.is_empty(), "Closing armor preview releases its simulation")
		L10n.set_language("zh")
		count += 1
	return count

func _run() -> void:
	PvpNet._endpoint_loaded = true
	PvpNet._endpoint = {}
	L10n.set_language("zh")
	await _resize(Vector2i(360, 640), false)
	var journal := load("res://scenes/journal.tscn").instantiate() as Control
	add_child(journal)
	journal._select_tab(Journal.EQUIPMENT_TAB)
	await _settle()
	await _tap(journal._equipment._groups[0].tiles[0])
	_expect(is_instance_valid(journal._equipment_preview), "Real catalog tile input opens the preview")
	if not is_instance_valid(journal._equipment_preview): get_tree().quit(1); return
	var preview: Control = journal._equipment_preview
	_expect(preview.sandbox._active and preview._info.scroll.visible, "Opening the item shows its text and starts the animation immediately")
	_check_layout(preview)
	journal._return_menu()
	await _settle()
	_expect(not is_instance_valid(journal._equipment_preview) and journal.is_inside_tree(), "Back closes the item before leaving the journal")
	var count := 0
	for type_id in Catalog.types("weapon"):
		journal._open_equipment(type_id)
		await _settle()
		preview = journal._equipment_preview
		_check_layout(preview)
		var sandbox: Control = preview.sandbox
		_expect(sandbox.map.map_size == Vector2i(4, 3) and sandbox.map.terrain.size() == 12, "Showcase has four columns and three rows")
		_expect(sandbox.map.region == 2, "Showcase uses the third region, caves")
		_expect(sandbox.map.layers.Ground.get_used_cells().size() == 12 and not sandbox.map.layers.Walls.visible, "All twelve special-floor tiles are fully visible without a boundary wall overhang")
		for tile in sandbox.map.terrain:
			_expect(tile == DungeonTerrain.Type.EMPTY_SP, "Every showcase cell is special floor")
		_expect(sandbox.rat.species == "rat" and sandbox.hero_sprite.hero_class == "warrior", "Original warrior and rat are present")
		_expect(sandbox.rat_sprite.body.sprite_frames.get_frame_texture(&"idle", 0).region == Rect2(0, 0, 16, 15), "Rat uses original RatSprite frame dimensions")
		_expect(sandbox.reach == MeleeRules.reach(preview.item, sandbox.warrior), "Range comes from the current weapon rules")
		_expect(sandbox.world.grid_distance(sandbox.warrior.cell, sandbox.rat.cell) == sandbox.reach, "Actors stand at the weapon's maximum normal range")
		_expect(sandbox.world.can_attack(sandbox.warrior, sandbox.rat, preview.item), "The displayed attack is legal in the real rules")
		for actor in [sandbox.warrior, sandbox.rat]:
			var position: Vector2i = sandbox.world.level.cell_coords(actor.cell) - Vector2i.ONE
			_expect(Rect2i(Vector2i.ZERO, Vector2i(4, 3)).has_point(position), "Both actors stand on the twelve floor cells")
		preview.show()
		sandbox.demonstrate_attack()
		_expect(sandbox.attacks_resolved == 0 and sandbox.rat.hp == sandbox.rat.max_hp, "Damage waits until attack animation finishes")
		await _wait_for_hit(sandbox, 1)
		_expect(sandbox.last_result.get("hit", false) and not sandbox.last_result.has("error"), "Every melee weapon actually strikes the target: " + type_id)
		_expect(sandbox.last_result.get("damage", -1) == MeleeRules.fixed_damage(preview.item, sandbox.warrior), "Showcase damage uses actual weapon balance: " + type_id)
		_expect(sandbox.rat.hp == sandbox.rat.max_hp and sandbox.rat in sandbox.world.actors, "The rat is restored without death or respawn")
		var text_layer := sandbox.map.get_node_or_null("CombatText") as CombatTextLayer
		_expect(text_layer != null and text_layer.active_texts().size() > 0, "A real damage popup is visible after impact")
		if type_id in ["Spear", "Glaive", "Whip"]:
			await get_tree().create_timer(0.1).timeout
			await _capture_preview("sandbox-%s-zh" % type_id)
		L10n.set_language("en")
		await _settle()
		_check_layout(preview)
		_expect(preview._description == preview._details._item_description(preview.item), "Live description follows the selected language")
		if type_id == "Whip":
			await _capture_preview("sandbox-Whip-en")
			# Verify timer-driven repetition, rather than only explicit test calls.
			await _wait_for_hit(sandbox, 2, 6000)
			_expect(sandbox.rat.hp == sandbox.rat.max_hp, "The rat survives repeated automatic attacks")
			# Stop mid-swing: neither a hidden hit nor an extra loop may fire.
			sandbox.demonstrate_attack()
			preview.hide()
			var resolved: int = sandbox.attacks_resolved
			await get_tree().create_timer(0.5).timeout
			_expect(sandbox.attacks_resolved == resolved and not sandbox._busy, "Leaving the sandbox cancels an unfinished attack")
			preview.show()
			sandbox.demonstrate_attack()
			await _wait_for_hit(sandbox, resolved + 1)
		if type_id == "Dagger": await _capture_preview("regular-Dagger-en")
		var world: MeleeWorld = sandbox.world
		preview.close()
		await _settle()
		_expect(world.actors.is_empty(), "Closing releases the local combat world and actors")
		L10n.set_language("zh")
		count += 1
	var armor_count := await _check_armors(journal)
	await _check_content_fit(journal)
	# All fifteen thrown weapons now have a live preview; effects have their own probe.
	for category in ["missile"]:
		for type_id in Catalog.types(category):
			journal._open_equipment(type_id)
			await _settle()
			preview = journal._equipment_preview
			_check_layout(preview)
			_expect(preview.sandbox != null and preview._notice == null, "Thrown weapons display a live animation below the description")
			preview.close()
			await _settle()
	journal._open_equipment("Whip")
	preview = journal._equipment_preview
	for language in ["zh", "en"]:
		L10n.set_language(language)
		for dimensions in [Vector2i(240, 320), Vector2i(360, 640), Vector2i(960, 540)]:
			await _resize(dimensions, true)
			preview._layout()
			await _settle()
			_check_layout(preview)
			await _capture_preview("layout-%s-%dx%d" % [language, dimensions.x, dimensions.y])
	# Android Back shares the same local close path; catalog scroll is retained.
	journal.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await _settle()
	_expect(not is_instance_valid(journal._equipment_preview), "Android Back closes the item preview")
	# Exercise the other close paths through real input, keeping the catalog.
	journal._open_equipment("Dagger")
	await _settle()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await _settle()
	_expect(not is_instance_valid(journal._equipment_preview), "Escape closes the item preview before the journal")
	journal._open_equipment("Spear")
	await _settle()
	await _tap(journal._equipment_preview._back)
	_expect(not is_instance_valid(journal._equipment_preview), "The preview's close icon responds to real input")
	journal._open_equipment("Whip")
	await _settle()
	for down in [true, false]:
		var mouse := InputEventMouseButton.new()
		mouse.position = ScreenLayout.safe_rect(get_viewport()).position + Vector2(2, 2)
		mouse.global_position = mouse.position
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = down
		Input.parse_input_event(mouse)
		await get_tree().process_frame
	await _settle()
	_expect(not is_instance_valid(journal._equipment_preview), "Tapping outside closes the preview without leaving the catalog")
	ScreenLayout.safe_area_override = Rect2i()
	journal.free()
	L10n.set_language("zh")
	print("EQUIPMENT_PREVIEW_MELEE_CASES ", count)
	print("EQUIPMENT_PREVIEW_ARMOR_CASES ", armor_count)
	print("EQUIPMENT_PREVIEW_CHECKS ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)
