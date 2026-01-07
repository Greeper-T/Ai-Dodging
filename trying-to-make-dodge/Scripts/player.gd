extends CharacterBody2D

const MAX_SPEED = 200.0
const ACCELERATION = 1200.0
const FRICTION = 1000.0

const DASH_SPEED = 600.0
const DASH_TIME = 0.15
const DASH_COOLDOWN = 1.5

var dash_direction := Vector2.ZERO
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var was_dashing := false

func _physics_process(delta: float) -> void:
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

		if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0.0 and velocity.length() > 0.0:
			start_dash(velocity.normalized())

		move_and_slide()

	was_dashing = is_dashing


func handle_normal_movement(delta: float):
	var direction := Vector2.ZERO

	if Input.is_action_pressed("moveRight"):
		direction.x += 1
	if Input.is_action_pressed("moveLeft"):
		direction.x -= 1
	if Input.is_action_pressed("moveDown"):
		direction.y += 1
	if Input.is_action_pressed("moveUp"):
		direction.y -= 1

	direction = direction.normalized()

	if direction != Vector2.ZERO:
		velocity = velocity.move_toward(direction * MAX_SPEED, ACCELERATION * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)


func start_dash(direction: Vector2):
	dash_direction = direction
	dash_timer = DASH_TIME
	dash_cooldown_timer = DASH_COOLDOWN
