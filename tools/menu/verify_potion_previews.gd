extends "res://tools/menu/verify_equipment_preview.gd"

func _until(check: Callable, message: String, seconds: float = 15) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not check.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var ok: bool = check.call()
	_expect(ok, message)
	return ok

func _gas_volume(sandbox: Control, kind: String) -> int:
	var field: EnvironmentField = sandbox.world.environment.fields.get(kind)
	return field.volume if field != null else 0

func _potion_capture(name: String) -> void:
	await get_tree().create_timer(0.35).timeout
	await _capture_preview("potion-" + name)

func _run() -> void:
	PvpNet._endpoint_loaded = true
	PvpNet._endpoint = {}
	L10n.set_language("zh")
	await _resize(Vector2i(360, 640), false)
	var journal := load("res://scenes/journal.tscn").instantiate() as Control
	add_child(journal)
	journal._select_tab(Journal.EQUIPMENT_TAB)
	await _settle()
	var types := Catalog.types("potion")+Catalog.types("exotic_potion")
	_expect(types.size() == 20 and "PotionOfCorrosiveGas" in types and "PotionOfMagicalSight" in types and "PotionOfStrength" not in types and "PotionOfExperience" not in types, "The twenty enabled potions include Corrosive Gas and Magical Sight")
	var count := 0
	for type_id in types:
		journal._open_equipment(type_id)
		await _settle()
		var preview: Control = journal._equipment_preview
		var sandbox: Control = preview.sandbox
		_expect(sandbox != null and sandbox.world is PotionWorld, "Potion preview uses a real local PotionWorld")
		if sandbox == null: get_tree().quit(1); return
		_check_layout(preview)
		_expect(sandbox.map.map_size == Vector2i(4, 3) and sandbox.map.region == 2, "Potion demonstration retains the compact caves floor")
		match type_id:
			"PotionOfCorrosiveGas":
				await _until(func(): return sandbox.rat.has_status("corrosion") and sandbox.rat.hp < sandbox.rat.max_hp, "Real corrosive gas applies damage after impact")
				_expect(_gas_volume(sandbox, "corrosive_gas") > 0 and sandbox.rat.hp < sandbox.rat.max_hp, "Actual corrosion gas persists and damages the target")
				await _potion_capture("corrosive-gas")
			"PotionOfMagicalSight":
				_expect(not sandbox.rat_sprite.visible, "Wall blocks the target before drinking")
				await _until(func(): return sandbox.warrior.has_status("magical_sight") and sandbox.rat_sprite.visible, "Real magical sight reveals the target through the wall")
				await _potion_capture("magical-sight")
			"PotionOfEarthenArmor":
				await _until(func(): return sandbox.bark_history.size() >= 2,"Barkskin demonstrates physical mitigation and decay",18)
				_expect(sandbox.bark_history[0].damage == 4 and sandbox.bark_history[1].damage == 5,"Twelve physical damage loses eight then seven after three turns")
				await _potion_capture("earthen-armor")
			"PotionOfCleansing":
				await _until(func(): return sandbox.resisted >= 3,"Cleansing removes and prevents negative statuses",12)
				_expect(sandbox.warrior.hp == 40 and sandbox.warrior.has_status("cleanse"),"Drinking cleanses but never heals")
				await _until(func(): return sandbox.throws_completed > 0,"Cleansing also demonstrates a thrown use",15)
				_expect(sandbox.rat.has_status("cleanse") and not sandbox.rat.has_status("poison"),"The thrown bottle cleanses the actual target")
			"PotionOfStormClouds":
				await _until(func(): return sandbox.world.environment.turn > 0,"Rain clouds evolve after the bottle arrives")
				_expect(sandbox.world.environment.terrain[sandbox.rat.cell] == DungeonTerrain.Type.WATER,"Rain actually floods the ground")
				await _potion_capture("storm-clouds")
			"PotionOfDragonsBreath":
				await _until(func(): return sandbox.breath_completed > 0,"Aimed drink resolves real fire-cone arrival")
				_expect(sandbox.rat.has_status("burning") and sandbox.rat.has_status("cripple"),"Breath ignites and cripples the real target")
				await _potion_capture("dragons-breath")
			"PotionOfShroudingFog":
				await _until(func(): return sandbox.throws_completed > 0,"Shrouding Fog lands before blocking sight")
				_expect(not sandbox.rat_sprite.visible and sandbox.hero_sprite.visible,"Fog hides the rat from the player's actual FOV")
				await _until(func(): return sandbox.viewer == 1,"Fog also shows the opponent's actual view")
				_expect(not sandbox.hero_sprite.visible and sandbox.rat_sprite.visible,"The opponent also cannot see the player through fog")
				await _potion_capture("shrouding-fog")
			"PotionOfStamina":
				await _until(func(): return sandbox.movement_history.size() >= 6,"Stamina demonstrates ordinary and enhanced movement")
				for move in sandbox.movement_history:
					_expect(is_equal_approx(move.cost,2.0/3.0 if move.stamina else 1.0),"Stamina uses actual movement costs")
				await _potion_capture("stamina")
			"PotionOfShielding":
				await _until(func(): return sandbox.attacks_resolved > 0,"Shielding absorbs a real rat attack")
				_expect(sandbox.warrior.hp == 70 and sandbox.shield_history[0].shield == 20,"Shielding begins at twenty and prevents HP loss")
				await _potion_capture("shielding")
			"PotionOfSnapFreeze":
				await _until(func(): return sandbox.throws_completed > 0,"Snap Freeze lands before freezing")
				_expect(sandbox.rat.statuses.get("frost") == 5.0 and sandbox.rat.statuses.get("roots") == 5.0,"Actual ground freeze and roots use five turns")
				await _until(func(): return sandbox.mode == "water" and sandbox.throws_completed >= 2,"Snap Freeze also demonstrates water",12)
				_expect(sandbox.rat.statuses.get("frost") == 10.0 and sandbox.rat.statuses.get("roots") == 5.0,"Actual water freeze is ten turns and roots remain five")
			"PotionOfHealing":
				_expect(sandbox.warrior.hp == 40, "Healing starts from an injured player")
				await _until(func(): return sandbox.world.environment.turn >= 1, "Healing waits then advances a real turn")
				_expect(sandbox.warrior.hp == 42 and sandbox.warrior.statuses.get("healing") == 19.0, "Healing restores exactly two HP per waited turn")
				await _potion_capture("healing")
				await _until(func(): return sandbox.loops_completed >= 1, "Potion demonstration repeats automatically")
			"PotionOfHaste":
				await _until(func(): return sandbox.moves_completed >= 8, "Haste completes an orbit around the rat")
				_expect(sandbox.warrior.has_status("haste"), "Orbit uses the actual haste effect")
				var positions: Array = []
				for entry in sandbox.history:
					if entry.kind == "moved":
						positions.append(entry.cell)
						_expect(is_equal_approx(float(entry.cost), 1.0 / 3), "Haste movement spends one third of a turn")
				_expect(Vector2i(1, 0) in positions and Vector2i(3, 2) in positions, "The route goes around both sides of the rat")
				for frame in 90:
					await get_tree().process_frame
					_expect(sandbox.hero_sprite.position.y + sandbox.hero_sprite.body.position.y >= -0.01, "Top-row movement never clips the player's head")
				await _potion_capture("haste")
			"PotionOfInvisibility":
				await _until(func(): return sandbox.warrior.has_status("invisibility") and sandbox.hero_sprite.body.modulate.a <= 0.41, "Drinking fades the player to original invisible-player opacity")
				await _potion_capture("invisibility")
			"PotionOfLevitation":
				await _until(func(): return sandbox.warrior.flying and sandbox.hero_sprite.body.animation == &"fly", "Drinking levitation shows the original flying pose")
				await _potion_capture("levitation-drink")
				await _until(func(): return sandbox.throws_completed >= 1 and sandbox.rat.has_status("vertigo"), "Throwing the same potion produces actual confusion gas")
				_expect(_gas_volume(sandbox, "confusion_gas") > 0 and not sandbox.warrior.flying, "The second stage is a thrown gas effect with a reset player")
				await _potion_capture("levitation-throw")
			"PotionOfMindVision":
				_expect(not sandbox.rat_sprite.visible and sandbox.vision.visible[sandbox.rat.cell] == 0, "Grass really blocks sight of the rat before drinking")
				await _until(func(): return sandbox.warrior.has_status("mind_vision") and sandbox.rat_sprite.visible, "Mind vision reveals the rat behind grass")
				_expect(sandbox.vision.visible[sandbox.rat.cell] != 0, "Revelation comes from real field-of-view sensing")
				await _potion_capture("mind-vision")
			"PotionOfPurity":
				await _until(func(): return sandbox.mode == "drink" and sandbox.world.environment.turn >= 2, "Purity is exposed to toxic gas for multiple turns")
				_expect(sandbox.warrior.has_status("blob_immunity") and sandbox.warrior.hp == 70 and sandbox.rat.hp < 70, "Protected player is unharmed while the exposed rat takes real gas damage")
				await _potion_capture("purity-drink")
				await _until(func(): return sandbox.purity_clears >= 1, "Purity also demonstrates throwing")
				_expect(_gas_volume(sandbox, "toxic_gas") == 0 and _gas_volume(sandbox, "paralytic_gas") == 0, "Thrown purity actually removes both harmful gas fields")
				await _potion_capture("purity-throw")
			"PotionOfToxicGas":
				await _until(func(): return sandbox.throws_completed >= 1 and sandbox.rat.hp < 70, "Thrown toxic gas damages the rat")
				_expect(_gas_volume(sandbox, "toxic_gas") > 0, "The green cloud is an actual toxic-gas field")
				await _potion_capture("toxic-gas")
			"PotionOfParalyticGas":
				await _until(func(): return sandbox.rat.has_status("paralysis") and not sandbox.rat_sprite.body.is_playing(), "Thrown paralysis gas immobilizes the rat")
				_expect(_gas_volume(sandbox, "paralytic_gas") > 0, "Paralysis has a yellow environmental gas field")
				await _potion_capture("paralytic-gas")
			"PotionOfLiquidFlame":
				await _until(func(): return sandbox.rat.has_status("burning"), "Thrown liquid flame ignites the target")
				_expect(_gas_volume(sandbox, "fire") > 0, "Flames exist on actual floor cells")
				await _potion_capture("liquid-flame")
			"PotionOfFrost":
				await _until(func(): return sandbox.rat.has_status("frost") and sandbox.rat_sprite.body.material != null, "Thrown frost produces the real frozen-target visual")
				_expect(_gas_volume(sandbox, "freezing") > 0, "Ice mist comes from the freezing field")
				await _potion_capture("frost")
		L10n.set_language("en")
		await _settle()
		_check_layout(preview)
		var local_world: PotionWorld = sandbox.world
		preview.close()
		await _settle()
		_expect(local_world.actors.is_empty(), "Closing the potion preview disposes its actors")
		L10n.set_language("zh")
		count += 1
		print("POTION_PREVIEW_OK ", type_id)
	for language in ["zh", "en"]:
		L10n.set_language(language)
		for dimensions in [Vector2i(240, 320), Vector2i(960, 540)]:
			await _resize(dimensions, true)
			journal._open_equipment("PotionOfParalyticGas")
			await _settle()
			journal._equipment_preview._layout()
			await _settle()
			_check_layout(journal._equipment_preview)
			await _capture_preview("potion-layout-%s-%dx%d" % [language, dimensions.x, dimensions.y])
			journal._equipment_preview.close()
			await _settle()
	await _resize(Vector2i(360, 640), false)
	# Close and hide in mid-flight, then wait beyond arrival: no stale impact.
	journal._open_equipment("PotionOfToxicGas")
	await _settle()
	var preview: Control = journal._equipment_preview
	var sandbox: Control = preview.sandbox
	sandbox._execute({"kind":"throw"})
	_expect(not sandbox.effects.flights.is_empty(), "Closing scenario starts with an in-flight potion")
	preview.hide()
	await get_tree().create_timer(0.4).timeout
	_expect(sandbox.throws_completed == 0 and sandbox.effects.flights.is_empty(), "Hiding cancels the in-flight potion")
	preview.show()
	await _until(func(): return sandbox.throws_completed == 1, "Showing restarts a clean potion demonstration")
	preview.close()
	await _settle()
	ScreenLayout.safe_area_override = Rect2i()
	journal.free()
	L10n.set_language("zh")
	print("POTION_PREVIEW_CASES ", count)
	print("POTION_PREVIEW_CHECKS ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)
