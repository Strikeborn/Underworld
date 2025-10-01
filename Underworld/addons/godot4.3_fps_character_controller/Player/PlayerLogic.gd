class_name Player extends CharacterBody3D

var _t_hold_fired := false
var _move_locked := false
var _t_pressed_at := 0.0
const T_HOLD_SEC := 0.4   # hold T this long to holster
@export_category("Player Settings")
@export var Move_Speed : float = 1.5
@export var Sprint_Speed : float = 10.0
@onready var phone3d := $"Head/Phone3D"
@onready var _phone_view: SubViewportContainer = get_node_or_null("/root/Game/PhoneLayer/PhoneView")
@export var PlayerInventory : Array[Dictionary] = []

@export_category("Inputs")
# @export var UserInputForward : String = &"ui_up"
# @export var UserInputBackward : String = &"ui_down"
# @export var UserInputLeft : String = &"ui_left"
# @export var UserInputRight : String = &"ui_right"

@export var InputDictionary : Dictionary = {
	"Forward": "ui_up",
	"Backward": "ui_down",
	"Left": "ui_left",
	"Right": "ui_right",
	"Jump": "ui_accept",
	"Escape": "ui_cancel",
	"Sprint": "ui_accept",
	"Interact": "ui_accept"
}

@export_category("Mouse Settings")
@export_range(0.09, 0.1) var Mouse_Sens : float = 0.09
@export_range(1.0, 50.0) var Mouse_Smooth : float = 50.0

@export_category("Camera Settings")
@export_subgroup("Tilt Settings")
@export_range(0.0, 1.0) var TiltThreshhold : float = 0.2
@onready var interact_ray: RayCast3D = $Head/InteractRay
# Onready
@onready var head : Node3D = $Head
@onready var camera : Camera3D = $Head/Camera3D
@onready var ltilt : Marker3D = $Tilt/LTilt
@onready var rtilt : Marker3D = $Tilt/RTilt
@onready var phone: Node3D = $Head/Phone3D
var _pending_spawn: Transform3D
var _has_pending_spawn := false
var _spawn_cooldown := 0.0
func teleport_to(t: Transform3D) -> void:
	_pending_spawn = t
	_has_pending_spawn = true
	
# Vectors
var direction : Vector3 = Vector3.ZERO
var Camera_Inp : Vector2 = Vector2()
var Rot_Vel : Vector2 = Vector2()

# Private
var _speed : float = Move_Speed
var _isMouseCaptured : bool = true

const JUMP_VELOCITY : float = 4.5

func set_spawn_cooldown(sec: float) -> void:
	_spawn_cooldown = max(0.0, sec)
	
func _ready() -> void:
	interact_ray.enabled = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	ltilt.rotation.z = TiltThreshhold
	rtilt.rotation.z = -TiltThreshhold
	if not is_in_group("player"):
		add_to_group("player")
	print("Player groups: ", get_groups())
	if phone3d and phone3d.has_signal("phone_state_changed"):
		phone3d.connect("phone_state_changed", Callable(self, "_on_phone_state_changed"))

func _on_phone_state_changed(state: String) -> void:
	# Lock movement when close or full
	_move_locked = (state == "close" or state == "full")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Camera_Inp = event.relative

func _process(delta: float) -> void:
	 # --- R cycles forward ---
	if Input.is_action_just_pressed("phone_next") and phone3d:
		phone3d.call("next_pose")

	# --- T tap = back one, hold = holster ---
	# T handling (press/hold/release)
	if Input.is_action_just_pressed("phone_prev"):
		_t_pressed_at = Time.get_ticks_msec() / 1000.0
		_t_hold_fired = false

	# T hold: holster as soon as threshold is crossed (don’t wait for release)
	if Input.is_action_pressed("phone_prev") and not _t_hold_fired:
		var now := Time.get_ticks_msec() / 1000.0
		if (now - _t_pressed_at) >= T_HOLD_SEC:
			if phone3d:
				phone3d.call("holster")
			_t_hold_fired = true

	# On release: only step-back if we didn't already auto-holster
	if Input.is_action_just_released("phone_prev"):
		if not _t_hold_fired and phone3d:
			phone3d.call("prev_pose")

	# If phone is “close/full”, ignore camera look (you already stop look when UI is up),
	# and prevent movement in _physics_process via _move_locked flag.

	# Camera Lock
	if Input.is_action_just_pressed(InputDictionary["Escape"]) and _isMouseCaptured:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_isMouseCaptured = false
	elif Input.is_action_just_pressed(InputDictionary["Escape"]) and not _isMouseCaptured:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_isMouseCaptured = true
	# R to toggle close/away
	# Left-click interact (raycast)
	if Input.is_action_just_pressed("Interact") and interact_ray.is_colliding():
		var hit := interact_ray.get_collider()
		if hit and hit.has_method("Interact"):
			hit.call_deferred("Interact")
	# Camera Smooth look
	Rot_Vel = Rot_Vel.lerp(Camera_Inp * Mouse_Sens, delta * Mouse_Smooth)
	head.rotate_x(-deg_to_rad(Rot_Vel.y))
	rotate_y(-deg_to_rad(Rot_Vel.x))
	head.rotation.x = clamp(head.rotation.x, -1.5, 1.5)
	Camera_Inp = Vector2.ZERO
	var phone_ui_open := _phone_view != null and _phone_view.visible
	if phone_ui_open:
		return  # skip look/move while the phone UI is open# skip camera/movement code while UI is up


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta
		
	if _has_pending_spawn:
		global_transform = _pending_spawn
		_has_pending_spawn = false
		if "velocity" in self:
			velocity = Vector3.ZERO
	if _move_locked:
		# zero horizontal velocity but keep gravity/jump handling as you prefer
		velocity.x = move_toward(velocity.x, 0.0, 1000.0)
		velocity.z = move_toward(velocity.z, 0.0, 1000.0)
		move_and_slide()
		return
	# Handle jump.
	if Input.is_action_just_pressed(InputDictionary["Jump"]) and is_on_floor():
		velocity.y = JUMP_VELOCITY

	#	Modified standard input for smooth movements.
	var input_dir : Vector2 = Input.get_vector(InputDictionary["Left"], InputDictionary["Right"], InputDictionary["Forward"], InputDictionary["Backward"])
	direction = lerp(direction,(transform.basis * Vector3(input_dir.x,0,input_dir.y)).normalized(), delta * 7.0)
	_speed = lerp(_speed, Move_Speed, min(delta * 5.0, 1.0))
	Sprint()
	if direction:
		velocity.x = direction.x * _speed
		velocity.z = direction.z * _speed
	else:
		velocity.x = move_toward(velocity.x,0,_speed)
		velocity.z = move_toward(velocity.z,0,_speed)
	
	move_and_slide()
		
	# skip rigidbody pushing while cooling down
	if _spawn_cooldown > 0.0:
		_spawn_cooldown -= delta
		return
	const MIN_PUSH_SPEED := 0.4
	var horiz_vel := Vector3(velocity.x, 0.0, velocity.z)
	if horiz_vel.length() < MIN_PUSH_SPEED and direction.length() < 0.05:
		return
		
	const PUSH_FORCE := 8.0
	var move_dir := horiz_vel.normalized()
	for i in range(get_slide_collision_count()):
		var col := get_slide_collision(i)
		var body := col.get_collider()
		if body is RigidBody3D:
			var n := col.get_normal()
			# Only push when we are pressing *into* the object
			if move_dir.dot(-n) > 0.35:
				body.apply_central_impulse(-n * PUSH_FORCE)

func Sprint() -> void:
	if Input.is_action_pressed(InputDictionary["Sprint"]):
		_speed = lerp(_speed, Sprint_Speed, 0.1)
	else:
		_speed = lerp(_speed, Move_Speed, 0.1)

@export var next_level_path := "res://levels/Level2.tscn"
