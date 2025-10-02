extends Node3D

# ─────────────────────────────────────────────────────────────────────────────
# Connections / external signals
# ─────────────────────────────────────────────────────────────────────────────
signal phone_link_clicked(path: String)
signal phone_state_changed(state: String)	# "hip" | "held" | "close" | "full"

# ─────────────────────────────────────────────────────────────────────────────
# Wiring (set these once in the Inspector)
# ─────────────────────────────────────────────────────────────────────────────
@export var world_vp_path: NodePath						# Player/Head/Phone3D/SubViewport
@export var phone_view_container_path: NodePath		# Game/PhoneLayer/PhoneView (SubViewportContainer)
@export var ui_overlay_vp_path: NodePath				# Game/PhoneLayer/OverlayViewport (SubViewport)
@export var buzz_player_path: NodePath					# Game/AudioStreamPlayer(3D)

@export var head_path: NodePath							# Player/Head  (used for fallback transforms)

@export var hip_marker: NodePath
@export var held_marker: NodePath
@export var close_marker: NodePath
@export var full_marker: NodePath

# Fallback local offsets (relative to Head) used if a marker path is empty
@export var hip_offset := Vector3(0.15, -0.35, 0.15)
@export var held_offset := Vector3(0.30, -0.12, -0.45)
@export var close_offset := Vector3(0.15, -0.05, -0.30)
@export var full_offset := Vector3(0.00, -0.02, -0.20)

# Overlay UI update & tween
@export var move_time := 0.20

# Buzzing options (enable on levels you want buzzing)
@export var buzz_on_this_level := true
@export var buzz_period_sec := 2.0			# initial period between buzzes
@export var buzz_min_period := 0.6			# clamp as period shrinks
@export var buzz_shrink_factor := 0.85		# each buzz shortens period *= factor

# ─────────────────────────────────────────────────────────────────────────────
# Internals
# ─────────────────────────────────────────────────────────────────────────────
@onready var phone3d: Node3D = self
@onready var head: Node3D = get_node_or_null(head_path)
@onready var world_vp: SubViewport = get_node_or_null(world_vp_path)
@onready var phone_view_container: SubViewportContainer = get_node_or_null(phone_view_container_path)
@onready var ui_overlay_vp: SubViewport = get_node_or_null(ui_overlay_vp_path)
@onready var buzz: AudioStreamPlayer = get_node_or_null(buzz_player_path)

var _hip_xf: Transform3D
var _held_xf: Transform3D
var _close_xf: Transform3D
var _full_xf: Transform3D

var _state := "hip"				# "hip" | "held" | "close" | "full"
var _tween: Tween = null

var _buzz_timer := 0.0
var _buzz_active := false

# ─────────────────────────────────────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Show overlay SubViewport inside the container & ensure it receives GUI input
	if phone_view_container != null and ui_overlay_vp != null:
		phone_view_container.subviewport = ui_overlay_vp
		phone_view_container.mouse_target = true
		ui_overlay_vp.gui_disable_input = false
		ui_overlay_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# Cache pose transforms
	_hip_xf = _xf_from_marker(hip_marker,  hip_offset)
	_held_xf = _xf_from_marker(held_marker, held_offset)
	_close_xf = _xf_from_marker(close_marker, close_offset)
	_full_xf = _xf_from_marker(full_marker, full_offset)

	# Start holstered at hip
	_apply_transform_immediate(_hip_xf)
	_set_overlay(false)
	_emit_state()

func _process(delta: float) -> void:
	if not buzz_on_this_level:
		return

	# Stop buzzing whenever UI is up (close/full)
	var is_open := (_state == "close" or _state == "full")
	if is_open:
		_stop_buzzing()
		return

	_buzz_timer -= delta
	if _buzz_timer <= 0.0:
		_play_buzz()
		# shrink the period gradually, with clamp
		var next_period := buzz_period_sec * buzz_shrink_factor
		if next_period < buzz_min_period:
			next_period = buzz_min_period
		_buzz_timer = next_period

# ─────────────────────────────────────────────────────────────────────────────
# Public API (PlayerLogic drives these with R / T)
# ─────────────────────────────────────────────────────────────────────────────
func next_pose() -> void:
	if _state == "hip":
		_set_overlay(false)
		_tween_to(_held_xf)
		_unlock_mouse()
	elif _state == "held":
		_set_overlay(true)
		_tween_to(_close_xf)
		_lock_mouse_for_ui()
	elif _state == "close":
		_set_overlay(true)
		_tween_to(_full_xf)
		_lock_mouse_for_ui()
	elif _state == "full":
		# stay here until link/meta click handles navigation
		pass
	_emit_state()

func prev_pose() -> void:
	if _state == "full":
		_set_overlay(true)
		_tween_to(_close_xf)
		_lock_mouse_for_ui()
	elif _state == "close":
		_set_overlay(false)
		_tween_to(_held_xf)
		_unlock_mouse()
	elif _state == "held":
		_set_overlay(false)
		_tween_to(_hip_xf)
		_unlock_mouse()
	elif _state == "hip":
		pass
	_emit_state()

func holster() -> void:
	_set_overlay(false)
	_tween_to(_hip_xf)
	_unlock_mouse()
	_emit_state()

# If your UI emits a "link clicked" (e.g. RichTextLabel meta_clicked),
# you can call this to go full, then relay the link for transition.
func request_full_then_link(path: String) -> void:
	if _state != "full":
		_set_overlay(true)
		_tween_to(_full_xf)
		_lock_mouse_for_ui()
		_emit_state()
		# Give the tween a moment; if you want to strictly wait, connect to finished.
		await get_tree().process_frame
	phone_link_clicked.emit(path)

# ─────────────────────────────────────────────────────────────────────────────
# Overlay routing (no reparenting; we simply show the overlay container)
# ─────────────────────────────────────────────────────────────────────────────
func move_ui_to_overlay() -> void:
	if phone_view_container != null:
		phone_view_container.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func move_ui_to_world() -> void:
	if phone_view_container != null:
		phone_view_container.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _set_overlay(on: bool) -> void:
	if on:
		move_ui_to_overlay()
	else:
		move_ui_to_world()

# ─────────────────────────────────────────────────────────────────────────────
# Buzz helpers
# ─────────────────────────────────────────────────────────────────────────────
func _play_buzz() -> void:
	if buzz == null:
		return
	_buzz_active = true
	if not buzz.playing:
		buzz.play()

func _stop_buzzing() -> void:
	_buzz_timer = 0.0
	_buzz_active = false
	if buzz != null and buzz.playing:
		buzz.stop()

# ─────────────────────────────────────────────────────────────────────────────
# Transforms & tweening
# ─────────────────────────────────────────────────────────────────────────────
func _xf_from_marker(path: NodePath, fallback_local_offset: Vector3) -> Transform3D:
	# Prefer explicit marker transform
	if not path.is_empty():
		var m := get_node_or_null(path) as Node3D
		if m != null:
			return m.global_transform

	# Otherwise compose from Head + local offset (if head is provided)
	if head != null:
		var t := head.global_transform
		t.origin += t.basis * fallback_local_offset
		return t

	# Last resort: this node
	return global_transform

func _tween_to(t: Transform3D) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(phone3d, "global_transform", t, move_time)
	_tween.finished.connect(func(): _tween = null)

func _apply_transform_immediate(t: Transform3D) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	phone3d.global_transform = t

# ─────────────────────────────────────────────────────────────────────────────
# Mouse lock (camera vs. UI)
# ─────────────────────────────────────────────────────────────────────────────
func _lock_mouse_for_ui() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _unlock_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _emit_state() -> void:
	phone_state_changed.emit(_state)
