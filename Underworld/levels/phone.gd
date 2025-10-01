extends Node3D

signal phone_opened
signal phone_closed
signal phone_link_clicked(path: String)

@export var move_time := 0.25
@export var enabled := true
@export var held_marker: NodePath
@export var close_marker: NodePath

@onready var head: Node3D = get_node("/root/Game/Player/Head")
@onready var ui_viewport: SubViewport = $SubViewport
@onready var phone_ui: Control = $SubViewport/PhoneUI

var _held_xf: Transform3D
var _close_xf: Transform3D
var _state := "held"        # "held" | "close"
var _tween: Tween

func _ready() -> void:
	# Cache poses from markers (local to Head). Fallback to sane defaults.
	var held_ref: Node3D = null
	var close_ref: Node3D = null
	if held_marker != NodePath(""):
		held_ref = get_node_or_null(held_marker) as Node3D
	if close_marker != NodePath(""):
		close_ref = get_node_or_null(close_marker) as Node3D

	if held_ref != null:
		_held_xf = held_ref.transform
	else:
		_held_xf = Transform3D(Basis(), Vector3(0.25, -0.15, -0.5))

	if close_ref != null:
		_close_xf = close_ref.transform
	else:
		_close_xf = Transform3D(Basis(), Vector3(0.0, -0.05, -0.25))

	# Start in held pose
	transform = _held_xf

	# Hook UI
	if phone_ui != null and phone_ui.has_signal("link_clicked"):
		phone_ui.connect("link_clicked", _on_ui_link_clicked)

	visible = enabled
	if not enabled and _state == "close":
		put_away()

func set_enabled(v: bool) -> void:
	enabled = v
	visible = enabled
	if not enabled and _state == "close":
		put_away()

func toggle() -> void:
	if not enabled:
		return
	if _state == "held":
		bring_close()
	else:
		put_away()

func bring_close() -> void:
	if _state == "close" or not enabled:
		return
	_state = "close"
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "transform", _close_xf, move_time)
	emit_signal("phone_opened")

func put_away() -> void:
	if _state == "held":
		return
	_state = "held"
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "transform", _held_xf, move_time)
	emit_signal("phone_closed")

func interact() -> void:
	toggle()

func _on_ui_link_clicked(path: String) -> void:
	emit_signal("phone_link_clicked", path)
