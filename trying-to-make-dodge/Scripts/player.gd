extends CharacterBody2D

const MAX_SPEED = 200.0
const ACCELERATION = 1200.0
const FRICTION = 1000.0
const DASH_SPEED = 600.0
const DASH_TIME = 0.15
const DASH_COOLDOWN = 15

var dash_direction := Vector2.ZERO
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var was_dashing := false

# These are set by the AI (or could be set by keyboard input)
var desired_direction: Vector2 = Vector2.ZERO
var wants_to_dash := false

# Set this to false if you want manual keyboard control
@export var ai_controlled := true

func _physics_process(delta: float) -> void:
	# Read input (either AI sets these variables, or we read keyboard)
	if not ai_controlled:
		read_keyboard_input()
	
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta
	
	var is_dashing = dash_timer > 0.0
	
	if is_dashing:
		if not was_dashing:
			set_collision_layer_value(1, false)
			set_collision_layer_value(4, true)
		dash_timer = max(dash_timer - delta, 0.0)
		velocity = dash_direction * DASH_SPEED
		move_and_slide()
	else:
		if was_dashing:
			set_collision_layer_value(4, false)
			set_collision_layer_value(1, true)
		
		handle_normal_movement(delta)
		
		if wants_to_dash and dash_cooldown_timer <= 0.0 and desired_direction.length() > 0.0:
			start_dash(desired_direction.normalized())
		
		move_and_slide()
	
	# Clamp position to viewport boundaries
	clamp_to_viewport()
	
	was_dashing = is_dashing

func clamp_to_viewport():
	# Get actual visible area from camera if it exists
	var camera := get_viewport().get_camera_2d()
	var viewport_size: Vector2
	var camera_offset := Vector2.ZERO
	
	if camera:
		# If there's a camera, get the visible rect
		var zoom = camera.zoom
		var screen_size = get_viewport_rect().size
		viewport_size = screen_size / zoom
		camera_offset = camera.global_position - viewport_size / 2
	else:
		# Fallback to viewport size
		viewport_size = get_viewport_rect().size
	
	var margin := 10.0
	
	# Clamp to camera-aware boundaries
	global_position.x = clamp(global_position.x, camera_offset.x + margin, camera_offset.x + viewport_size.x - margin)
	global_position.y = clamp(global_position.y, camera_offset.y + margin, camera_offset.y + viewport_size.y - margin)

func handle_normal_movement(delta: float) -> void:
	var direction := desired_direction.normalized()
	
	if direction != Vector2.ZERO:
		velocity = velocity.move_toward(direction * MAX_SPEED, ACCELERATION * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)

func read_keyboard_input():
	var dir := Vector2.ZERO
	if Input.is_action_pressed("moveRight"):
		dir.x += 1
	if Input.is_action_pressed("moveLeft"):
		dir.x -= 1
	if Input.is_action_pressed("moveDown"):
		dir.y += 1
	if Input.is_action_pressed("moveUp"):
		dir.y -= 1
	
	desired_direction = dir
	wants_to_dash = Input.is_action_just_pressed("dash")

func start_dash(direction: Vector2):
	dash_direction = direction
	dash_timer = DASH_TIME
	dash_cooldown_timer = DASH_COOLDOWN
