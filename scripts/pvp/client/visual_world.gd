class_name PvpVisualWorld
extends WandWorld
## Passive data for the original effect renderers: no bind, tick or resolve calls.
func actor_at(cell: int) -> WandActor:
	for actor in actors:
		if actor.cell == cell and actor.hp > 0 and is_instance_valid(actor.sprite) and actor.sprite.is_visible_in_tree(): return actor
	return null
