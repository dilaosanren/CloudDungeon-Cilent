extends "res://tools/menu/verify_potion_previews.gd"
const GlyphPreview = preload("res://scripts/menu/glyph_sandbox.gd")

func _glyph_capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/pvp-runtime/glyph-preview/%s.png" % name)

func _find_seeds() -> void:
	for key in ["potential","entanglement","repulsion","affection","thorns","stone"]:
		var sandbox := GlyphPreview.new()
		sandbox.item = Catalog.create("Glyph_"+key)
		add_child(sandbox)
		for seed_value in 128:
			sandbox._reset_scene("seed")
			sandbox.world.rng.seed = seed_value
			var result := (sandbox.world as MeleeWorld).attack(sandbox.rat,sandbox.warrior)
			var success := false
			match key:
				"potential": success = sandbox.wand.charges > 0
				"entanglement": success = sandbox.warrior.data.get("earthroot_armor",0) > 0
				"repulsion": success = sandbox.rat_sprite.cell == Vector2i(3,2)
				"affection": success = sandbox.rat.is_charmed_by(sandbox.warrior)
				"thorns": success = sandbox.rat.has_status("bleeding")
				"stone":
					sandbox._set_glyph(false)
					sandbox.world.rng.seed = seed_value
					var plain := (sandbox.world as MeleeWorld).attack(sandbox.rat,sandbox.warrior)
					success = result.get("hit",false) and plain.get("hit",false) and result.damage < plain.damage
			if success:
				print("GLYPH_SEED ",key," ",seed_value)
				break
		sandbox.free()
	get_tree().quit()

func _check_effect(sandbox: Control) -> void:
	match sandbox.key:
		"swiftness", "flow":
			await _until(func(): return sandbox.movement_history.size() >= 6,"Both real movement speeds are demonstrated",12)
			var moves: Array = sandbox.movement_history
			for index in 6:
				_expect(is_equal_approx(moves[index].cost,1.0 if index < 3 else 1.0/1.2 if sandbox.key == "swiftness" else 0.5),"Actual movement cost matches the glyph")
			_expect(sandbox.hero_sprite.cell == Vector2i(0,2),"Native hops return to the start")
		"camouflage":
			await _until(func(): return sandbox.moves_completed > 0,"Warrior lands in actual high grass",4)
			_expect(sandbox.warrior.has_status("invisibility"),"Camouflage activates on landing")
			await get_tree().create_timer(0.5).timeout
			_expect(sandbox.hero_sprite.body.modulate.a <= 0.41,"Native invisibility fades the player")
		"brimstone":
			await _until(func(): return sandbox.world.environment.turn >= 4,"Fire advances actual turns",14)
			_expect(sandbox.warrior.hp == 70 and sandbox.rat.hp < 70,"Brimstone wearer is unharmed beside a burning unprotected target")
		"stone":
			await _until(func(): return sandbox.damage_history.size() >= 2,"Plain and Stone receive two actual attacks",10)
			var records: Array = sandbox.damage_history
			_expect(records[0].result.get("hit",false) and records[1].result.get("hit",false),"Comparison uses two actual hits")
			_expect(records[1].damage < records[0].damage and sandbox.warrior.effective_evasion() == 0,"Stone converts real evasion to damage absorption")
		"antimagic":
			await _until(func(): return sandbox.casts_completed >= 2,"Plain and AntiMagic receive actual missiles",10)
			_expect(sandbox.damage_history[1].damage < sandbox.damage_history[0].damage,"AntiMagic reduces magic damage")
		"potential":
			await _until(func(): return sandbox.attacks_resolved > 0,"Potential triggers on a real hit",5)
			_expect(sandbox.wand.charges == 1 and sandbox.damage_history[0].charge == 1,"Potential charges the carried empty wand by one")
			await _glyph_capture("potential-charged")
			await _until(func(): return sandbox.casts_completed > 0,"Charged wand can actually fire",10)
			_expect(sandbox.wand.charges == 0 and sandbox.rat.hp < 70,"Firing consumes the gained charge and damages the target")
		"viscosity":
			await _until(func(): return sandbox.attacks_resolved > 0,"Viscosity receives an actual hit",5)
			_expect(sandbox.damage_history[0].pool > 0 and sandbox.damage_history[0].damage < 11,"Viscosity stores part of the real hit")
			await _glyph_capture("viscosity-deferred")
			await _until(func(): return sandbox.world.environment.turn >= 3,"Deferred damage ticks",12)
			_expect(sandbox.warrior.hp == 59 and sandbox.warrior.data.deferred_damage == 0,"Stored damage is paid gradually by the actual PvP scheduler")
		"entanglement":
			await _until(func(): return sandbox.attacks_resolved > 0,"Entanglement receives an actual hit",5)
			_expect(sandbox.warrior.data.get("earthroot_armor",0) > 0 and sandbox.warrior.hp == 70,"Native earthroot armor absorbs the incoming attack")
			await _glyph_capture("entanglement-armor")
			await _until(func(): return sandbox.moves_completed > 0,"Player leaves the rooted position",10)
			_expect(not sandbox.warrior.data.has("earthroot_armor"),"Moving discards actual earthroot armor")
		"repulsion":
			await _until(func(): return sandbox.attacks_resolved > 0,"Repulsion receives an actual hit",5)
			_expect(sandbox.rat_sprite.cell == Vector2i(3,2),"Repulsion knocks the attacker two cells away")
			await get_tree().create_timer(0.2).timeout
			_expect(sandbox.rat_sprite.position.is_equal_approx(Vector2(56,40)),"Native knockback reaches the authoritative cell")
		"affection":
			await _until(func(): return sandbox.attacks_resolved > 0,"Affection receives an actual hit",5)
			_expect(sandbox.rat.is_charmed_by(sandbox.warrior),"Attacker is charmed by the armor wearer")
			await _glyph_capture("affection-charmed")
			await _until(func(): return sandbox.attacks_resolved >= 2,"A second attack is attempted",10)
			_expect(sandbox.last_result.has("error") and sandbox.damage_history[1].damage == 0,"Actual charm prevents the second direct attack")
		"thorns":
			await _until(func(): return sandbox.attacks_resolved > 0,"Thorns receives an actual hit",5)
			_expect(sandbox.rat.has_status("bleeding"),"Thorns makes the attacker bleed")
			await _until(func(): return sandbox.rat.hp < 70,"Bleeding damages the attacker",12)

func _check_cancel(journal: Control) -> void:
	for key in ["potential","camouflage","antimagic"]:
		journal._open_equipment("Glyph_"+key)
		await _settle()
		var preview: Control = journal._equipment_preview
		var sandbox: Control = preview.sandbox
		if key == "potential": sandbox._execute({"kind":"defend"})
		elif key == "camouflage": sandbox._execute({"kind":"step","cell":Vector2i(1,2)})
		else: sandbox._execute({"kind":"cast"})
		var original_hp: int = sandbox.warrior.hp
		preview.hide()
		await get_tree().create_timer(0.5).timeout
		_expect(sandbox.attacks_resolved == 0 and sandbox.moves_completed == 0 and sandbox.casts_completed == 0 and sandbox.warrior.hp == original_hp,"Hiding cancels active swing/hop/missile: "+key)
		preview.show()
		_expect(not sandbox.warrior.has_status("invisibility") and sandbox.warrior.hp == 70,"Showing restores a clean glyph scene")
		if key == "potential": sandbox._execute({"kind":"defend"})
		elif key == "camouflage": sandbox._execute({"kind":"step","cell":Vector2i(1,2)})
		else: sandbox._execute({"kind":"cast"})
		var retired: WeakRef = weakref(sandbox.world)
		preview.close()
		await _settle()
		await get_tree().create_timer(0.5).timeout
		_expect(not is_instance_valid(sandbox) and retired.get_ref() == null,"Closing releases the local rule world")

func _verify_details(journal: Control) -> void:
	for language in ["zh","en"]:
		L10n.set_language(language)
		for key in ["viscosity","camouflage","affection","thorns"]:
			journal._open_equipment("Glyph_"+key)
			await _settle()
			var preview: Control = journal._equipment_preview
			var sandbox: Control = preview.sandbox
			await _until(func(): return is_instance_valid(sandbox._announcement_text),"Native glyph status name: "+key,6)
			var popup: CombatFloatingText = sandbox._announcement_text
			if is_instance_valid(popup):
				var turn: int = sandbox.world.environment.turn
				var actions: int = sandbox.attacks_resolved+sandbox.moves_completed+sandbox.casts_completed
				await _glyph_capture("name-%s-%s" % [language,key])
				while is_instance_valid(popup) and popup.time_left > 0.2:
					var bounds := popup.collision_rect()
					var inside := Rect2(sandbox.map.position+bounds.position*sandbox.map.scale,bounds.size*sandbox.map.scale)
					_expect(Rect2(Vector2.ZERO,sandbox.size).encloses(inside),"Full native name and outline fit the animation: %s %s %s" % [language,key,inside])
					_expect(sandbox.world.environment.turn == turn and sandbox.attacks_resolved+sandbox.moves_completed+sandbox.casts_completed == actions,"Actions wait until the name finishes")
					_expect(CombatTextLayer.for_actor(sandbox.hero_sprite).active_texts().size() == 1,"Names do not overlap damage numbers")
					await get_tree().process_frame
			L10n.set_language("en" if language == "zh" else "zh")
			await _settle()
			_expect(preview._description == Catalog.entry_description(preview.item),"Changing language updates the open glyph description")
			for child in preview._content.get_children():
				if child is Label: _expect(child.text == Catalog.entry_title(preview.item),"Glyph title follows the language")
			preview.close()
			await _settle()
			L10n.set_language(language)
	for key in ["swiftness","flow"]:
		journal._open_equipment("Glyph_"+key)
		await _settle()
		var sandbox: Control = journal._equipment_preview.sandbox
		await _until(func(): return sandbox.movement_history.size() >= 4,"Walking reaches the accelerated stage",8)
		var tint := Color("dddd00" if key == "swiftness" else "00ccff")
		await _until(func(): return sandbox.effects.scroll_particles.any(func(particle): return particle.color == tint),"Native colored speed specks appear",1)
		await get_tree().create_timer(0.1).timeout
		await _glyph_capture(key+"-native-specks")
		journal._equipment_preview.close()
		await _settle()
	journal._open_equipment("Glyph_entanglement")
	await _settle()
	var sandbox: Control = journal._equipment_preview.sandbox
	await _until(func(): return sandbox.attacks_resolved > 0,"Earthroot armor is gained",5)
	await get_tree().create_timer(1.1).timeout
	_expect(sandbox.warrior.data.get("earthroot_armor",0) > 0,"Armor icon remains after damage text fades")
	await _glyph_capture("entanglement-visible-armor")
	journal._equipment_preview.close()
	await _settle()
	await _check_cancel(journal)
	journal.free()
	L10n.set_language("zh")
	print("GLYPH_PREVIEW_DETAILS_CHECKS ","FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)

func _run() -> void:
	PvpNet._endpoint_loaded = true
	PvpNet._endpoint = {}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/pvp-runtime/glyph-preview"))
	if "--find-glyph-seeds" in OS.get_cmdline_user_args():
		_find_seeds()
		return
	L10n.set_language("zh")
	await _resize(Vector2i(360,640),false)
	var journal := load("res://scenes/journal.tscn").instantiate() as Control
	add_child(journal)
	journal._select_tab(Journal.EQUIPMENT_TAB)
	await _settle()
	if "--glyph-titles-only" in OS.get_cmdline_user_args():
		for language in ["zh","en"]:
			L10n.set_language(language)
			for dimensions in [Vector2i(240,320),Vector2i(360,640),Vector2i(960,540)]:
				await _resize(dimensions,true)
				for type_id in Catalog.types("glyph"):
					journal._open_equipment(type_id)
					await _settle()
					var preview: Control = journal._equipment_preview
					_check_layout(preview)
					for child in preview._content.get_children():
						if child is Label:
							var font: Font = child.get_theme_font("font")
							var width := font.get_string_size(child.text,HORIZONTAL_ALIGNMENT_LEFT,-1,child.get_theme_font_size("font_size")).x
							_expect(width <= child.size.x,"Full original glyph title fits: "+child.text)
							if language == "en": _expect(child.text.begins_with("Glyph"),"Standalone English title includes the native Glyph noun")
					if type_id == "Glyph_stone": await _glyph_capture("layout-%s-%dx%d" % [language,dimensions.x,dimensions.y])
					preview.close()
					await _settle()
		ScreenLayout.safe_area_override = Rect2i()
		journal.free()
		L10n.set_language("zh")
		print("GLYPH_PREVIEW_TITLE_CHECKS ","FAIL" if _failed else "PASS")
		get_tree().quit(1 if _failed else 0)
		return
	if "--glyph-details-only" in OS.get_cmdline_user_args():
		await _verify_details(journal)
		return
	var types := Catalog.types("glyph")
	_expect(types.size() == 12 and journal._equipment._groups.size() == 11,"Twelve glyphs are the eleventh journal group")
	_expect(Catalog.create("Glyph_obfuscation") == null,"Removed Obfuscation remains absent")
	journal._equipment._scroll.scroll_vertical = 9999
	await _settle()
	await _tap(journal._equipment._groups[10].tiles[0])
	_expect(is_instance_valid(journal._equipment_preview) and Catalog.is_glyph(journal._equipment_preview.item),"Actual glyph tile opens its preview")
	journal._equipment_preview.close()
	await _settle()
	for type_id in types:
		journal._open_equipment(type_id)
		await _settle()
		var preview: Control = journal._equipment_preview
		var sandbox: Control = preview.sandbox
		if sandbox == null: _expect(false,"Missing glyph sandbox"); get_tree().quit(1); return
		_check_layout(preview)
		var original: Dictionary = preview.item.metadata.duplicate(true)
		_expect(sandbox.world.get_script() == preload("res://scripts/menu/glyph_preview_world.gd") and sandbox.armor != preview.item,"Independent journal world uses timed glyph rules on a copied armor")
		_expect(sandbox.hero_sprite.armor_tier == 1 and sandbox.weapon_icon.sprite.material is ShaderMaterial,"Native cloth appearance and glyph glow")
		await _check_effect(sandbox)
		await _glyph_capture(sandbox.key+"-effect")
		_expect(preview.item.metadata == original,"Catalog armor is unchanged")
		await _until(func(): return sandbox.loops_completed > 0,"Glyph demonstration loops: "+type_id,22)
		_expect(sandbox.warrior.hp == 70 and sandbox.rat.hp == 70,"Loop resets health")
		var retired: WeakRef = weakref(sandbox.world)
		preview.close()
		await _settle()
		_expect(retired.get_ref() == null,"Closing releases every glyph world")
		print("GLYPH_PREVIEW_OK ",type_id)
	for language in ["zh","en"]:
		L10n.set_language(language)
		for dimensions in [Vector2i(240,320),Vector2i(360,640),Vector2i(960,540)]:
			await _resize(dimensions,true)
			for type_id in types:
				journal._open_equipment(type_id)
				await _settle()
				_check_layout(journal._equipment_preview)
				if type_id == "Glyph_stone": await _glyph_capture("layout-%s-%dx%d" % [language,dimensions.x,dimensions.y])
				journal._equipment_preview.close()
				await _settle()
	ScreenLayout.safe_area_override = Rect2i()
	await _resize(Vector2i(360,640),false)
	await _check_cancel(journal)
	journal.free()
	L10n.set_language("zh")
	print("GLYPH_PREVIEW_CHECKS ","FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)
