# Shared InventorySlot gestures, item art and original pixel counters.
extends InventorySlot
const L10n = preload("res://scripts/menu/game_locale.gd")

var price := 0
var buyer_order := -1
var can_purchase := false
var affordable := true
var item_view: InventorySlot

func _ready() -> void:
	super._ready()
	item_view = InventorySlot.new()
	item_view.quick = true
	item_view.show_extra = true
	item_view.position = Vector2(1, 0)
	item_view.size = Vector2(23, 23)
	add_child(item_view)
	item_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_view.focus_mode = Control.FOCUS_NONE

func set_item(value: InventoryItem, model: DungeonInventory) -> void:
	item = value
	inventory = model
	item_view.item = value
	item_view.inventory = model
	item_view.queue_redraw()
	queue_redraw()

func set_market_state(cost: int, buyer: int, allowed: bool, enough_gold: bool) -> void:
	price = cost
	buyer_order = buyer
	can_purchase = allowed
	affordable = enough_gold
	item_view.visible = buyer_order < 0
	tooltip_text = (item.display_name() + L10n.text(" · %d 金币 · 长按查看") % price) if buyer_order < 0 else L10n.text("已被购买")
	queue_redraw()

func _draw() -> void:
	var frame: StyleBoxTexture = UiAssets.get_style("GREY_BUTTON" if buyer_order >= 0 else "ORANGE_BUTTON").duplicate()
	if buyer_order >= 0: frame.modulate_color.a = 0.25
	elif not affordable: frame.modulate_color = Color(0.6, 0.6, 0.6)
	elif _holding and can_purchase: frame.modulate_color = Color(1.2, 1.2, 1.2)
	draw_style_box(frame, Rect2(0, 0, 25, 23))
	var price_text := str(price) if buyer_order < 0 else "--"
	var color := Color("ffff44") if buyer_order < 0 and affordable else Color("999999")
	SpdPixelText.draw(self, Vector2(floorf((25 - SpdPixelText.measure(price_text).x) / 2), 24), price_text, color)
	if has_focus(): draw_rect(Rect2(0, 0, 25, 23), Color("ffff44"), false, 1)
