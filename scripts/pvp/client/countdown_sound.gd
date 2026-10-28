extends AudioStreamPlayer
## Shared market/battle tick: the original click sample at alternating pitches.
const CLICK: AudioStream = preload("res://assets/inventory/click.mp3")
var seconds := -1

func _ready() -> void:
	bus = &"SFX"
	stream = CLICK
	volume_db = 0.0

func reset() -> void:
	seconds = -1
	stop()

func set_seconds(value: int) -> void:
	if value == seconds: return
	seconds = value
	if seconds <= 0:
		stop()
		return
	pitch_scale = 1.5 if seconds % 2 == 0 else 0.9
	# The SFX bus applies the existing volume/mute preferences.
	if DisplayServer.get_name() != "headless": play()
