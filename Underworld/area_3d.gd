extends Area3D

@export var next_level_path := "res://levels/Level2.tscn"
@export var activate_delay := 0.6

var _armed := false
var _player_inside := false

func _ready() -> void:
	# Monitoring stays ON, just arm later.
	await get_tree().process_frame
	await get_tree().create_timer(activate_delay).timeout

	# Snapshot any overlaps now (so we won’t fire until the player leaves & re-enters)
	_player_inside = _is_player_overlapping()
	if _player_inside:
		print("[Trigger] armed; player already inside – waiting for exit then re-enter")
	else:
		print("[Trigger] armed; player NOT inside")

	_armed = true

func _is_player_overlapping() -> bool:
	for b in get_overlapping_bodies():
		if b.is_in_group("player"):
			return true
	return false

func _on_area_3d_body_entered(body: Node3D) -> void:
	# Debug who entered and distance (helps catch stray colliders)
	var d := body.global_transform.origin.distance_to(global_transform.origin)
	print("[Trigger] ENTER:", body.name, " groups=", body.get_groups(), " dist=", d)
	if not _armed or not body.is_in_group("player"):
		return
	if _player_inside:
		# We were already overlapping when armed; require an exit first
		return

	set_deferred("monitoring", false)
	var game := get_node_or_null("/root/Game")
	if game and game.has_method("load_level"):
		game.call_deferred("load_level", next_level_path)

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = false
	pass # Replace with function body.


func _on_body_entered(body: Node3D) -> void:
	pass # Replace with function body.
