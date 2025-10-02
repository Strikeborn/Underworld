extends Node3D
# Phone3D script (attached to Player/Head/Phone3D)

# --- Pose markers under Head/Phone3D (set in Inspector) ---
@export var hip_marker:  NodePath
@export var held_marker: NodePath
@export var close_marker: NodePath
@export var full_marker: NodePath

# --- References that live in the Player scene ---
@onready var head: Node3D = get_parent()         # Head
@onready var phone3d: Node3D = self               # Phone3D

# --- Overlay UI that lives under /root/Game/PhoneLayer ---
# SubViewportContainer that draws the phone overlay
@onready var phone_view_container: SubViewportContainer = \
	get_node_or_null("/root/Game/PhoneLayer/PhoneView")

# The SubViewport that actually contains the UI scene
@onready var ui_overlay_vp: SubViewport = \
	get_node_or_null("/root/Game/PhoneLayer/OverlayViewport")

# --- Cached pose transforms (local to Head) ---
var _hip_xf:  Transform3D
var _held_xf: Transform3D
var _close_xf: Transform3D
var _full_xf:  Transform3D

# --- State / tween ---
var _state := "hip"      # "hip" | "held" | "close" | "full"
var _tween: Tween = null

# ----------------------------- Helpers -----------------------------

func _xf_from_marker(path: NodePath, fallback_pos := Vector3.ZERO) -> Transform3D:
	if path == NodePath(""):
		return Transform3D(Basis(), fallback_pos)
	var m := get_node_or_null(path) as Node3D
	return m.transform if m else Transform3D(Basis(), fallback_pos)

func _apply_transform_immediate(t: Transform3D) -> void:
	if _tween:
		_tween.kill()
		_tween = null
	global_transform = head.global_transform * t

func _tween_to(t: Transform3D, dur := 0.20) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var from := global_transform
	var to   := head.global_transform * t
	_tween.tween_property(self, "global_transform", to, dur)

func _emit_state() -> void:
	# Relay to Game if needed
	var game := get_node_or_null("/root/Game")
	if game and game.has_signal("phone_state_changed"):
		game.emit_signal("phone_state_changed", _state)

# ------------------------------ Ready ------------------------------

func _ready() -> void:
	# Wire the overlay viewer once (no reparenting; just point the container)
	if phone_view_container and ui_overlay_vp:
		phone_view_container.subviewport = ui_overlay_vp
		# Let the controls inside the SubViewport receive mouse, not the container
		phone_view_container.mouse_target = false

	if ui_overlay_vp:
		ui_overlay_vp.gui_disable_input = false
		ui_overlay_vp.handle_input_locally = true
		ui_overlay_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# Cache local (to Head) transforms from the markers
	_hip_xf  = _xf_from_marker(hip_marker,  Vector3(0.15, -0.35,  0.15))
	_held_xf = _xf_from_marker(held_marker, Vector3(0.30, -0.12, -0.45))
	_close_xf= _xf_from_marker(close_marker,Vector3(0.15, -0.05, -0.30))
	_full_xf = _xf_from_marker(full_marker, _close_xf.origin + Vector3(0.0, -0.02, -0.20))

	# Start holstered at hip
	_apply_transform_immediate(_hip_xf)
	_set_overlay(false)
	_emit_state()

# ----------------------------- Overlay -----------------------------

func _set_overlay(on: bool) -> void:
	# You already mount the UI SubViewport to the container in _ready().
	# Nothing else is required here unless you want to hide/show the viewer.
	if phone_view_container:
		phone_view_container.visible = on

func move_ui_to_overlay() -> void:
	# Helper kept for compatibility: re-aim the container to the overlay viewport.
	if phone_view_container and ui_overlay_vp:
		phone_view_container.subviewport = ui_overlay_vp

func move_ui_to_world() -> void:
	# We no longer draw UI in the Phone3D’s SubViewport, so this is a no-op.
	pass

# ----------------------------- Buzzing -----------------------------

func _is_stowed() -> bool:
	return _state == "hip"

func _buzz_enabled_for_level() -> bool:
	# Stub: return true unless you later hook LevelConfig here
	return true

func _process(delta: float) -> void:
	var game := get_node_or_null("/root/Game")

	var should_buzz := true
	if game and "phone_should_buzz" in game:
		should_buzz = game.phone_should_buzz

	if not _buzz_enabled_for_level():
		return

	var do_buzz := should_buzz and _is_stowed()

	if game:
		# Your Game.gd version of _update_buzz() takes no args
		if do_buzz and game.has_method("_update_buzz"):
			game._update_buzz()
		elif game.has_method("_stop_buzzing"):
			game._stop_buzzing()

# ------------------------------ Poses ------------------------------

func next_pose() -> void:
	match _state:
		"hip":
			_set_overlay(false)
			_tween_to(_held_xf)
			_state = "held"

			var game := get_node_or_null("/root/Game")
			if game and game.has_method("_stop_buzzing"):
				game._stop_buzzing()

		"held":
			_set_overlay(true)
			move_ui_to_overlay()
			_tween_to(_close_xf)
			_state = "close"

		"close":
			_set_overlay(true)
			_tween_to(_full_xf)
			_state = "full"

		"full":
			pass

	_emit_state()


func prev_pose() -> void:
	match _state:
		"full":
			_tween_to(_close_xf)
			_state = "close"
		"close":
			_set_overlay(false)
			move_ui_to_world()
			_tween_to(_held_xf)
			_state = "held"
		"held":
			_tween_to(_hip_xf)
			_state = "hip"
		"hip":
			pass
	_emit_state()

func holster() -> void:
	_set_overlay(false)
	move_ui_to_world()
	_tween_to(_hip_xf)
	_state = "hip"
	_emit_state()

# ------------------------------ Input hooks ------------------------------

func lock_mouse_for_ui() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func unlock_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
