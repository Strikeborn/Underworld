extends Node3D

@export var start_level_path := "res://levels/Level1.tscn"

@onready var level_root: Node3D = $LevelRoot
@onready var fade: ColorRect = $CanvasLayer/Fade
@onready var phone_buzz: AudioStreamPlayer = $PhoneLayer/PhoneBuzz

var phone_can_buzz := true     # enabled on Level1 only
var phone_is_close := false
@onready var player: CharacterBody3D = $Player
@onready var player_cam: Camera3D = $Player/Head/Camera3D
var _saved_layer := 0
var _saved_mask  := 0
var to_unfreeze: Array[RigidBody3D] = []

@onready var phone3d: Node3D = $Player/Head/Phone3D  # adjust path if different
@onready var overlay_vp: SubViewport = $PhoneLayer/PhoneView/OverlayViewport
@onready var phone_vp: SubViewport = $Player/Head/Phone3D/SubViewport
@onready var phone_ui: Control = $Player/Head/Phone3D/SubViewport/PhoneUI
@onready var phone_layer: CanvasLayer = $PhoneLayer
var _current_level_id := ""

func current_level_id() -> String:
	return _current_level_id
func _prepare_player_for_spawn() -> void:
	_saved_layer = player.collision_layer
	_saved_mask  = player.collision_mask
	player.collision_layer = 0
	player.collision_mask  = 0
	player.process_mode = Node.PROCESS_MODE_DISABLED   # Player script won’t run

func _finish_player_spawn() -> void:
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.collision_layer = _saved_layer
	player.collision_mask  = _saved_mask
	if "velocity" in player:
		player.velocity = Vector3.ZERO

func _on_phone_link_clicked(path: String) -> void:
	phone_can_buzz = false   # stop buzzing once they actually click a link
	_update_buzz()
	load_level(path)          # your existing loader
	# example: path is a level path like "res://levels/Pac2D.tscn"
	await load_level(path, true)  # your existing loader & fade
	# Optional: after switching to 2D, holster so when we return to 3D we start hip
	if phone3d:
		phone3d.call_deferred("holster")

func _update_buzz() -> void:
	if phone_can_buzz and not phone_is_close:
		if not phone_buzz.playing:
			phone_buzz.play()
	else:
		if phone_buzz.playing:
			phone_buzz.stop()

func _ready() -> void:
	# connect phone events
	if phone3d:
		var c_open  := Callable(self, "_on_phone_opened")
		var c_close := Callable(self, "_on_phone_closed")
		var c_link  := Callable(self, "_on_phone_link_clicked")

		if phone3d.has_signal("phone_opened") and not phone3d.is_connected("phone_opened", c_open):
			phone3d.connect("phone_opened", c_open)

		if phone3d.has_signal("phone_closed") and not phone3d.is_connected("phone_closed", c_close):
			phone3d.connect("phone_closed", c_close)

		if phone3d.has_signal("phone_link_clicked") and not phone3d.is_connected("phone_link_clicked", c_link):
			phone3d.connect("phone_link_clicked", c_link)
	phone_layer.visible = false  # hidden until phone opens
	process_mode = Node.PROCESS_MODE_ALWAYS
	fade.modulate.a = 1.0
	# 1) Player off: no collisions, no script
	_prepare_player_for_spawn()
	# 2) Pause the world
	get_tree().paused = true
	# 3) Load level while paused and place player (no physics runs yet)
	await load_level(start_level_path, false)
	# 4) Unpause, let the world tick twice while player is still off
	get_tree().paused = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	# (optional) tiny cooldown for push code, if you kept it
	if player.has_method("set_spawn_cooldown"):
		player.set_spawn_cooldown(0.3)
	# 5) Now enable the player (collisions + script)
	_finish_player_spawn()
	
	# Unfreeze what we froze
	for rb in to_unfreeze:
		if is_instance_valid(rb):
			rb.freeze = false
			rb.sleeping = false
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
	# 6) Fade in
	await _fade(0.0)

func _on_phone_opened() -> void:
	# Move UI from the 3D phone to the fullscreen overlay viewport
	if phone_ui.get_parent() != overlay_vp:
		phone_ui.get_parent().remove_child(phone_ui)
		overlay_vp.add_child(phone_ui)
	phone_layer.visible = true

func _on_phone_closed() -> void:
	# Move UI back to the phone’s own viewport
	if phone_ui.get_parent() != phone_vp:
		phone_ui.get_parent().remove_child(phone_ui)
		phone_vp.add_child(phone_ui)
	phone_layer.visible = false
# game.gd

func _on_phone_state_changed(state: String) -> void:
	var ui_up := (state == "close" or state == "full")
	# called from your phone.gd signal
	phone_is_close = (state == "close" or state == "full")
	_update_buzz()
	# overlay visibility
	if phone_layer:
		phone_layer.visible = ui_up   # your CanvasLayer with PhoneView under it

	# mouse cursor mode
	if ui_up:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# freeze player walking while UI is up (optional, if not done already)
	if player and player.has_method("set_move_locked"):
		player.set_move_locked(ui_up)

func _find_first_camera3d_under(n: Node) -> Camera3D:
	if n is Camera3D:
		return n
	for c in n.get_children():
		var found := _find_first_camera3d_under(c)
		if found != null:
			return found
	return null

func _fade(a: float, dur := 0.35) -> void:
	var t = create_tween()
	t.tween_property(fade, "modulate:a", a, dur)
	await t.finished

func _clear_level() -> void:
	for c in level_root.get_children():
		c.queue_free()
		
func _freeze_rbs_near(root: Node, center: Vector3, radius: float) -> Array[RigidBody3D]:
	var frozen: Array[RigidBody3D] = []
	_freeze_walk(root, center, radius, frozen)
	return frozen

func _freeze_walk(n: Node, center: Vector3, radius: float, frozen: Array[RigidBody3D]) -> void:
	if n is RigidBody3D:
		var rb := n as RigidBody3D
		if rb.global_transform.origin.distance_to(center) <= radius:
			rb.freeze = true
			rb.sleeping = true
			frozen.append(rb)
	for c in n.get_children():
		_freeze_walk(c, center, radius, frozen)

func load_level(path: String, do_fade := true) -> void:
	if do_fade:
		await _fade(1.0)
	_clear_level()
	var packed: PackedScene = load(path)
	if packed == null:
		if do_fade: await _fade(0.0, 0.2)
		return

	var inst: Node = packed.instantiate()
	level_root.add_child(inst)
	_current_level_id = inst.name  # e.g. "Level1", "Level2", …
	await get_tree().process_frame  # still paused

	# Place exactly on Spawn BEFORE any physics ever runs
	var spawn := inst.find_child("Spawn", true, false) as Marker3D
	var spawn_xform: Transform3D
	if spawn != null:
		spawn_xform = spawn.global_transform
	else:
		spawn_xform = Transform3D()
	# 1) Freeze rigidbodies in a small bubble around spawn (e.g., 3 meters)
	if spawn != null:
		to_unfreeze = _freeze_rbs_near(inst, spawn_xform.origin, 3.0)
	# Place player at spawn_xform while still disabled/no-collide
	if spawn != null and player != null:
		player.global_transform = spawn_xform
		if "velocity" in player:
			player.velocity = Vector3.ZERO
	# decide camera based on what the level contains
	var cam2d := inst.find_child("Camera2D", true, false) as Camera2D
	if cam2d != null:
		_disable_all_camera2d(inst) # optional: first set all false then make current
		cam2d.current = true
		# hide player & phone while in 2D
		if is_instance_valid(player): player.visible = false
	else:
		# 3D level case (existing code)
		if is_instance_valid(player): player.visible = true
		if player_cam != null:
			player_cam.current = true
	var cfg := inst.get_node_or_null("LevelConfig")
	var phone_on := true
	if cfg:
		phone_on = bool(cfg.get("phone_enabled"))
	if phone3d and phone3d.has_method("set_enabled"):
		phone3d.call("set_enabled", phone_on)
	if do_fade:
		await _fade(0.0)

func _disable_all_camera2d(root: Node) -> void:
	if root is Camera2D:
		(root as Camera2D).current = false
	for c in root.get_children():
		_disable_all_camera2d(c)
