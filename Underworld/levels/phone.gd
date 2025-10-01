extends Node3D

signal phone_state_changed(state: String)
signal phone_link_clicked(path: String)   # relay to Game after “full” tween

@export var move_time := 0.20

@export var hip_marker: NodePath
@export var held_marker: NodePath
@export var close_marker: NodePath
@export var full_marker: NodePath   # optional; if empty, we’ll reuse close

@onready var head: Node3D = $".."
@onready var phone_view_container: CanvasItem = get_node_or_null("/root/Game/PhoneLayer/PhoneView")
@onready var phone_vp: SubViewport = $SubViewport
@onready var phone_ui: Control = $SubViewport/PhoneUI

var _hip_xf: Transform3D
var _held_xf: Transform3D
var _close_xf: Transform3D
var _full_xf: Transform3D
var _state := "hip"        # "hip" | "held" | "close" | "full"
var _tween: Tween = null

func _ready() -> void:
	# Cache local transforms from markers (markers live under Head, same space as Phone3D)
	_hip_xf   = _xf_from_marker(hip_marker,  Vector3(0.15, -0.35,  0.15))
	_held_xf  = _xf_from_marker(held_marker, Vector3(0.30, -0.12, -0.45))
	_close_xf = _xf_from_marker(close_marker,Vector3(0.15, -0.05, -0.30))
	var full_default := Vector3(0.00, -0.02, -0.20)
	_full_xf  = _xf_from_marker(full_marker, full_default)

	# Start holstered at hip
	_apply_transform_immediate(_hip_xf)
	_set_overlay(false)
	_emit_state()

	# UI: when a link is clicked, go full first, then relay after tween
	if phone_ui and phone_ui.has_signal("link_clicked"):
		phone_ui.connect("link_clicked", Callable(self, "_on_ui_link_clicked"))

func _xf_from_marker(path: NodePath, fallback_pos: Vector3) -> Transform3D:
	if path != NodePath(""):
		var m := get_node_or_null(path) as Node3D
		if m:
			return m.transform
	return Transform3D(Basis(), fallback_pos)

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

	_emit_state()

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
