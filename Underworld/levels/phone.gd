extends Node3D

signal phone_state_changed(state: String)
signal phone_link_clicked(path: String)

@export var move_time := 0.20

# NodePaths for pose markers under Head/Phone3D
@export var hip_marker: NodePath
@export var held_marker: NodePath
@export var close_marker: NodePath
@export var full_marker: NodePath
@onready var head: Node3D            = $".."                # Player/Head
@onready var phone3d: Node3D         = self                # This Phone3D
@onready var phone_vp: SubViewport   = $SubViewport        # Player/Head/Phone3D/SubViewport
# References in the Player scene
# --- overlay pieces live under Game/PhoneLayer/PhoneView ---
@onready var phone_view_container: SubViewportContainer = \
	get_node_or_null("/root/Game/PhoneLayer/PhoneView")

@onready var ui_overlay_vp: SubViewport = \
	get_node_or_null("/root/Game/PhoneLayer/PhoneView/OverlayViewport")

@onready var phone_ui: Control = \
	get_node_or_null("/root/Game/PhoneLayer/PhoneView/PhoneUI")

# ---- cached transforms (local to Head) ----
var _hip_xf: Transform3D
var _held_xf: Transform3D
var _close_xf: Transform3D
var _full_xf: Transform3D

# ---- state / tween ----
var _state := "hip"	# "hip" | "held" | "close" | "full"
var _tween: Tween = null

func _ready() -> void:
	# Wire SubViewport into the container and allow UI input.
	if phone_view_container != null and ui_overlay_vp != null:
		phone_view_container.subviewport = ui_overlay_vp
		ui_overlay_vp.gui_disable_input = false
		phone_view_container.mouse_target = true

	# Make sure PhoneUI actually renders INSIDE the SubViewport.
	# (SubViewportContainer does not render its own children.)
	if phone_ui != null and ui_overlay_vp != null and phone_ui.get_parent() != ui_overlay_vp:
		phone_ui.reparent(ui_overlay_vp)

	# Cache pose transforms
	_hip_xf   = _xf_from_marker(hip_marker,   Vector3(0.15, -0.35,  0.15))
	_held_xf  = _xf_from_marker(held_marker,  Vector3(0.30, -0.12, -0.45))
	_close_xf = _xf_from_marker(close_marker, Vector3(0.15, -0.05, -0.30))
	_full_xf  = _xf_from_marker(full_marker,  Vector3(0.00, -0.02, -0.20))

	# Start holstered at hip
	_apply_transform_immediate(_hip_xf)
	_set_overlay(false)
	_emit_state()

	# Connect RichTextLabel meta clicks (if present)
	if phone_ui != null:
		var label := phone_ui.get_node_or_null("RichTextLabel") as RichTextLabel
		if label != null and not label.is_connected("meta_clicked", Callable(self, "_on_phone_meta_clicked")):
			label.connect("meta_clicked", Callable(self, "_on_phone_meta_clicked"))

func _on_phone_meta_clicked(meta: Variant) -> void:
	if typeof(meta) == TYPE_STRING:
		emit_signal("phone_link_clicked", String(meta))

# ---------- helpers ----------

func _xf_from_marker(path: NodePath, fallback_pos: Vector3) -> Transform3D:
	if path == NodePath(""):
		return Transform3D(Basis(), fallback_pos)

	var m := get_node_or_null(path) as Node3D
	if m != null:
		return m.transform
	else:
		return Transform3D(Basis(), fallback_pos)


func _apply_transform_immediate(t: Transform3D) -> void:
	if _tween:
		_tween.kill()
		_tween = null
	phone3d.transform = t

func _tween_to(t: Transform3D) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(phone3d, "transform", t, move_time)
	await _tween.finished
	_tween = null

func _set_overlay(on: bool) -> void:
	if on:
		move_ui_to_overlay()
	else:
		move_ui_to_world()

func move_ui_to_overlay() -> void:
	if phone_view_container != null and ui_overlay_vp != null:
		phone_view_container.subviewport = ui_overlay_vp
		ui_overlay_vp.gui_disable_input = false
		phone_view_container.mouse_target = true

func move_ui_to_world() -> void:
	# Draw UI back into the Phone3D’s SubViewport (not the overlay)
	if phone_vp != null:
		if phone_view_container != null:
			phone_view_container.subviewport = null
		phone_vp.gui_disable_input = false

func _emit_state() -> void:
	emit_signal("phone_state_changed", _state)

func _lock_mouse_for_ui() -> void:
	# Game should switch mouse mode; this is a safe local hint
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _unlock_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func is_open_state() -> bool:
	return _state == "close" or _state == "full"

# ---------- buzzing hookup to Game ----------

func _process(delta: float) -> void:
	var game := get_node_or_null("/root/Game")
	var should_buzz := true
	if game and ("phone_can_buzz" in game):
		should_buzz = game.phone_can_buzz
	if not should_buzz:
		return

	var do_buzz := not is_open_state()
	if game and game.has_method("_update_buzz"):
		game._update_buzz(delta, do_buzz)

	if is_open_state() and game and game.has_method("_stop_buzzing"):
		game._stop_buzzing()

# ---------- pose API you already call from Player ----------

func next_pose() -> void:
	match _state:
		"hip":
			_set_overlay(false)
			await _tween_to(_held_xf)
			_state = "held"
		"held":
			_set_overlay(true)
			await _tween_to(_close_xf)
			_lock_mouse_for_ui()
			_state = "close"
		"close":
			await _tween_to(_full_xf)
			_lock_mouse_for_ui()
			_state = "full"
		"full":
			# stay
			pass
	_emit_state()

func prev_pose() -> void:
	match _state:
		"full":
			await _tween_to(_close_xf)
			_state = "close"
		"close":
			_unlock_mouse()
			_set_overlay(false)
			await _tween_to(_held_xf)
			_state = "held"
		"held":
			await _tween_to(_hip_xf)
			_state = "hip"
		"hip":
			pass
	_emit_state()

func holster() -> void:
	_unlock_mouse()
	_set_overlay(false)
	await _tween_to(_hip_xf)
	_state = "hip"
	_emit_state()
