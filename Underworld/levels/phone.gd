extends Node3D

signal phone_state_changed(state: String)
signal phone_link_clicked(path: String)   # relay to Game after “full” tween
@export var move_time := 0.20
@onready var ui_world_vp: SubViewport = %SubViewport          # Player/Phone3D/SubViewport
@onready var ui_overlay_vp: SubViewport = %OverlayViewport     # Game/PhoneLayer/OverlayViewport
@export var hip_marker: NodePath
@export var held_marker: NodePath
@export var close_marker: NodePath
@export var full_marker: NodePath   # optional; if empty, we’ll reuse close
@onready var head: Node3D = $".."
@onready var phone_view_container: SubViewportContainer = %PhoneView
@onready var world_vp: SubViewport = phone3d.get_node("SubViewport") as SubViewport
@onready var phone3d        : Node3D               = self
@onready var phone_vp       : SubViewport          = $"SubViewport"
@onready var phone_ui       : Control              = $"SubViewport/PhoneUI"
@onready var phone_view     : SubViewportContainer = get_node("/root/Game/PhoneLayer/PhoneView")
@onready var buzz := $PhoneBuzz  # AudioStreamPlayer or AudioStreamPlayer3D
var _hip_xf: Transform3D
var _held_xf: Transform3D
var _close_xf: Transform3D
var _full_xf: Transform3D
var _state := "hip"        # "hip" | "held" | "close" | "full"
var _tween: Tween = null

func _ready() -> void:
	# Fallbacks if Unique names were missed
	# Show this SubViewport inside the overlay container
	if is_instance_valid(phone_view) and is_instance_valid(phone_vp):
		phone_view.subviewport = phone_vp
		phone_vp.gui_disable_input = false  # allow clicks on UI
	
	# (your existing pose init here)
	# make sure the SubViewport updates while phone is up
	phone_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# Optional: connect meta_clicked if you haven't already
	var label := phone_ui.get_node_or_null("RichTextLabel")
	if label and not label.is_connected("meta_clicked", Callable(self, "_on_phone_meta_clicked")):
		label.connect("meta_clicked", Callable(self, "_on_phone_meta_clicked"))
	# Start holstered at hip
	_apply_transform_immediate(_hip_xf)
	_set_overlay(false)
	_emit_state()

func _on_phone_meta_clicked(meta: Variant) -> void:
	# meta is whatever you put in [url=...]
	if typeof(meta) == TYPE_STRING:
		var path := String(meta)
		# if we're not yet in "full", go full first then follow link
		request_full_then_link(path)	# uses your existing flow to call Game.load_level after full

	# UI: when a link is clicked, go full first, then relay after tween
	if phone_ui and phone_ui.has_signal("link_clicked"):
		phone_ui.connect("link_clicked", Callable(self, "_on_ui_link_clicked"))

func _xf_from_marker(path: NodePath, fallback_pos: Vector3) -> Transform3D:
	if path != NodePath(""):
		var m := get_node_or_null(path) as Node3D
		if m:
			return m.transform
	return Transform3D(Basis(), fallback_pos)
var _buzz_timer := 0.0
const BUZZ_PERIOD := 2.0  # seconds between buzzes (start large, shrink later)
func phone_is_open() -> bool:
	# however you expose state from phone.gd; e.g.:
	return phone_state == "close" or phone_state == "full"

func _process(delta: float) -> void:
	# Only on Level1 and only if phone is not close/full
	if current_level_name() == "Level1" and not phone_is_open():
		_buzz_timer -= delta
		if _buzz_timer <= 0.0:
			if buzz: buzz.play()
			# make buzzing faster gradually (clamped)
			_buzz_timer = max(0.6, BUZZ_PERIOD * 0.85)
	else:
		_buzz_timer = 0.0  # reset when open or not level1
func _apply_transform_immediate(t: Transform3D) -> void:
	if _tween:
		_tween.kill()
		_tween = null
	transform = t

func _tween_to(t: Transform3D) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "transform", t, move_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# ------------- Public controls -------------

func next_pose() -> void:
	# R: only move forward; never bounce back
	if _state == "hip":
		_go_state("held")
	elif _state == "held":
		_go_state("close")
	elif _state == "close":
		_go_state("full")
	elif _state == "full":
		# already full; no change
		pass

func prev_pose() -> void:
	# T tap: step back a pose
	if _state == "full":
		_go_state("close")
	elif _state == "close":
		_go_state("held")
	elif _state == "held":
		_go_state("hip")
	elif _state == "hip":
		# already holstered
		pass


func holster() -> void:
	_go_state("hip")

# Called by UI: snap to full, then (after tween) emit link to Game
func request_full_then_link(path: String) -> void:
	_go_state("full")
	if _tween:
		await _tween.finished
	phone_link_clicked.emit(path)

# ------------- Internals -------------

func _go_state(s: String) -> void:
	if s == _state:
		return
	_state = s
	
	if _state == "hip":
		_set_overlay(false)
		_tween_to(_hip_xf)
		_unlock_mouse()
	elif _state == "held":
		_set_overlay(false)
		_tween_to(_held_xf)
		_unlock_mouse()
	elif _state == "close":
		_set_overlay(true)
		_tween_to(_close_xf)
		_lock_mouse_for_ui()
	elif _state == "full":
		_set_overlay(true)
		_tween_to(_full_xf)
		_lock_mouse_for_ui()
	match _state:
		"hip", "held":
			_move_ui_to_world()
		"close", "full":
			_move_ui_to_overlay()

	_emit_state()

func _move_ui_to_overlay() -> void:
	if phone_ui and ui_overlay_vp and phone_ui.get_parent() != ui_overlay_vp:
		phone_ui.reparent(ui_overlay_vp)
	phone_view_container.visible = true
	phone_view.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _move_ui_to_world() -> void:
	if phone_ui and world_vp and phone_ui.get_parent() != world_vp:
		phone_ui.reparent(world_vp)
	phone_view_container.visible = false
	phone_view.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _emit_state() -> void:
	phone_state_changed.emit(_state)

func _set_overlay(on: bool) -> void:
	if phone_view_container:
		phone_view_container.visible = on

func _lock_mouse_for_ui() -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _unlock_mouse() -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_ui_link_clicked(path: String) -> void:
	# UI asked to open a link: fill the screen first, then tell Game
	request_full_then_link(path)
