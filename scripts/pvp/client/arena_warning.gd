extends Node2D
## DM300's TargetedCell: Icons.TARGET, hardlight red, 1 -> .6 alpha,
## with scale = alpha^(1/3). The authority owns its game-time lifetime.
const TARGET_TEXTURE = preload("res://assets/ui/source/icons.png")
var cells: Array[int] = []
var map_width := 36
var _elapsed := 0.0
var _target: AtlasTexture

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 110 # Public danger markers stay readable above the fog (z=100).
	_target = AtlasTexture.new()
	_target.atlas = TARGET_TEXTURE
	_target.region = Rect2(0,32,16,16)
	set_process(false)

func sync(value: Array, width: int) -> void:
	if cells==value and map_width==width: return
	cells.assign(value)
	map_width = width
	_elapsed = 0
	set_process(not cells.is_empty())
	queue_redraw()

func clear() -> void:
	sync([],map_width)

func _process(delta: float) -> void:
	_elapsed = minf(0.4,_elapsed+delta)
	queue_redraw()
	if _elapsed>=0.4: set_process(false)

func _draw() -> void:
	if _target==null: return
	var alpha := maxf(0.6,1-_elapsed)
	var side := 16*pow(alpha,1.0/3)
	for cell in cells:
		var center := Vector2(cell%map_width,cell/map_width)*16+Vector2(8,8)
		draw_texture_rect(_target,Rect2(center-Vector2.ONE*side/2,Vector2.ONE*side),false,Color(1,0,0,alpha))
