extends Node2D

@export var bullet_scene: PackedScene
@export var spawn_radius_min : float = 150.0
@export var spawn_radius_max : float = 350.0

@onready var player := $Player
@onready var bullet_container := $ProjectileContainer
@onready var timeLabel: Label = $UI/TimerLabel
@onready var timer: Timer = $Timer

var elapsedTime := 0.0
var timesHit = 0
var longestTimeAlive := 0.0

# Creating a danger grid for the AI
const GRID_SIZE := 11
const CELL_SIZE := 16
const GRID_CENTER: int = GRID_SIZE / 2

# Balanced settings for normal bullet speeds (100-150)
# Increase PREDICTION_STEPS for faster bullets
const PREDICTION_STEPS := 10
const STEP_TIME := 0.05

var danger_grid := PackedFloat32Array()
var last_ai_direction := Vector2.ZERO
var last_dash_time := 0.0

func _ready():
	timer.timeout.connect(spawn_bullet)

func _physics_process(delta: float) -> void:
	danger_grid = compute_danger_grid()
	queue_redraw()
	
	var ai_dir := compute_ai_direction()
	player.desired_direction = ai_dir
	player.wants_to_dash = should_ai_dash(delta)
	
	elapsedTime += delta
	updateLabel()

func should_ai_dash(delta: float) -> bool:
	last_dash_time += delta
	
	# Don't dash too frequently (adjust for faster bullets)
	if last_dash_time < 0.25:  # Reduced from 0.3 for faster reaction
		return false
	
	var center_idx := GRID_CENTER * GRID_SIZE + GRID_CENTER
	var center_danger := danger_grid[center_idx]
	
	# Lower threshold for faster bullets - dash earlier
	if center_danger < 0.4:  # Reduced from 0.5
		return false
	
	# Check if dashing in the current direction would help
	if last_ai_direction != Vector2.ZERO:
		var dash_danger := sample_danger_along_path(last_ai_direction, 3)
		
		# Dash if it would take us to a safer location
		if dash_danger < center_danger * 0.7:  # More lenient threshold
			last_dash_time = 0.0
			return true
	
	return false

func updateLabel():
	var seconds := int(elapsedTime)
	var milliseconds := int((elapsedTime - seconds) * 100)

	if seconds == 15:
		timer.wait_time = .3
	if seconds == 30:
		timer.wait_time = .2

	timeLabel.text = "Time: %02d.%02d" % [seconds, milliseconds]

func get_random_spawn_position() -> Vector2:
	var angle = randf() * TAU
	var distance = randf_range(spawn_radius_min, spawn_radius_max)
	return player.global_position + Vector2(cos(angle), sin(angle)) * distance

func reset():
	player.global_position = Vector2.ZERO
	if elapsedTime > longestTimeAlive:
		longestTimeAlive = elapsedTime
	
	var seconds := int(longestTimeAlive)
	var milliseconds := int((longestTimeAlive - seconds) * 100)
	
	$UI/Record.text = "Record: %02d.%02d" % [seconds, milliseconds]
	
	elapsedTime = 0
	timer.wait_time = .5
	timesHit += 1
	$UI/TimesHitLabel.text = "Times Hit: " + str(timesHit)
	
	for child in bullet_container.get_children():
		child.queue_free()

func spawn_bullet():
	var bullet = bullet_scene.instantiate()
	bullet.global_position = get_random_spawn_position()
	var dir_to_player = (player.global_position - bullet.global_position).normalized()
	bullet.direction = dir_to_player
	bullet_container.add_child(bullet)

func _draw():
	if danger_grid.is_empty():
		return

	# Draw danger grid
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var value := danger_grid[y * GRID_SIZE + x]
			if value <= 0.0:
				continue

			var alpha: float = clamp(float(value), 0.0, 1.0)
			var rect_pos : Vector2 = player.global_position + Vector2(
				(x - GRID_CENTER) * CELL_SIZE,
				(y - GRID_CENTER) * CELL_SIZE
			)

			draw_rect(
				Rect2(rect_pos, Vector2(CELL_SIZE, CELL_SIZE)),
				Color(1, 0, 0, alpha * 0.5)
			)
	
	# Draw AI direction indicator
	if last_ai_direction != Vector2.ZERO:
		draw_line(
			player.global_position,
			player.global_position + last_ai_direction * 40,
			Color.GREEN,
			3
		)

func compute_danger_grid() -> PackedFloat32Array:
	var grid: PackedFloat32Array = PackedFloat32Array()
	grid.resize(GRID_SIZE * GRID_SIZE)
	grid.fill(0.0)

	for child in bullet_container.get_children():
		var bullet := child as Area2D
		if bullet == null:
			continue
		if not bullet.has_method("get_velocity"):
			continue

		var velocity: Vector2 = bullet.get_velocity()

		# Add current position danger
		add_danger_at_position(bullet.global_position, grid, 1.0)
		
		# Add predicted future positions
		for i in range(PREDICTION_STEPS):
			var future_pos: Vector2 = bullet.global_position + velocity * ((i + 1) * STEP_TIME)
			var weight := 1.0 - (float(i) / PREDICTION_STEPS) * 0.3  # Slight decay over distance
			add_danger_at_position(future_pos, grid, weight)

	return grid

func add_danger_at_position(world_pos: Vector2, grid: PackedFloat32Array, weight: float = 1.0) -> void:
	var rel: Vector2 = world_pos - player.global_position

	var gx: int = int(floor(rel.x / CELL_SIZE)) + GRID_CENTER
	var gy: int = int(floor(rel.y / CELL_SIZE)) + GRID_CENTER

	if gx < 0 or gx >= GRID_SIZE or gy < 0 or gy >= GRID_SIZE:
		return

	var idx: int = gy * GRID_SIZE + gx
	var dist: float = rel.length()

	# Adjusted danger calculation - less aggressive
	var danger_value := weight * 1.5 / (dist * 0.08 + 1.0)
	grid[idx] += danger_value
	grid[idx] = clamp(grid[idx], 0.0, 1.5)  # Lower max danger

func compute_ai_direction() -> Vector2:
	var best_dir := Vector2.ZERO
	var lowest_danger := INF

	# Check 8 cardinal and diagonal directions
	var directions := [
		Vector2.UP,
		Vector2.DOWN,
		Vector2.LEFT,
		Vector2.RIGHT,
		Vector2(-1, -1).normalized(),
		Vector2(1, -1).normalized(),
		Vector2(-1, 1).normalized(),
		Vector2(1, 1).normalized()
	]

	for dir in directions:
		# Sample danger along path
		var danger := sample_danger_along_path(dir, 2)
		
		# Add boundary penalty (now fixed to only apply near edges)
		var boundary_penalty := get_boundary_penalty(dir)
		danger += boundary_penalty
		
		# Small penalty for changing direction (momentum)
		if last_ai_direction != Vector2.ZERO and dir.dot(last_ai_direction) < 0.5:
			danger += 0.05

		if danger < lowest_danger:
			lowest_danger = danger
			best_dir = dir

	# Debug print
	if Engine.get_frames_drawn() % 30 == 0:
		var stay_danger := danger_grid[GRID_CENTER * GRID_SIZE + GRID_CENTER]
		var viewport_size = get_viewport_rect().size
		print("AI Direction: ", best_dir, " | Move Danger: ", lowest_danger, " | Stay Danger: ", stay_danger, " | Pos: ", player.global_position, " | Viewport: ", viewport_size)
	
	# Only stand still if there's truly no danger
	var stay_danger := danger_grid[GRID_CENTER * GRID_SIZE + GRID_CENTER]
	if stay_danger < 0.05 and stay_danger < lowest_danger:
		best_dir = Vector2.ZERO

	last_ai_direction = best_dir
	return best_dir

func sample_danger_along_path(dir: Vector2, depth: int) -> float:
	if dir == Vector2.ZERO:
		return danger_grid[GRID_CENTER * GRID_SIZE + GRID_CENTER]

	var total_danger := 0.0
	
	# Sample multiple cells along the path
	for i in range(1, depth + 1):
		var check_pos : Vector2 = player.global_position + dir * CELL_SIZE * i
		var rel : Vector2 = check_pos - player.global_position

		var gx := int(floor(rel.x / CELL_SIZE)) + GRID_CENTER
		var gy := int(floor(rel.y / CELL_SIZE)) + GRID_CENTER

		if gx < 0 or gx >= GRID_SIZE or gy < 0 or gy >= GRID_SIZE:
			return 9999.0

		var cell_danger := danger_grid[gy * GRID_SIZE + gx]
		# Weight closer cells more heavily
		total_danger += cell_danger * (1.0 / float(i))
	
	return total_danger

func get_boundary_penalty(dir: Vector2) -> float:
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
	
	var margin := 60.0
	var future_pos :Vector2= player.global_position + dir * CELL_SIZE * 2
	var penalty := 0.0
	
	# Calculate boundaries relative to camera position
	var left_bound := camera_offset.x + margin
	var right_bound := camera_offset.x + viewport_size.x - margin
	var top_bound := camera_offset.y + margin
	var bottom_bound := camera_offset.y + viewport_size.y - margin
	
	# Only add penalty if we're near a boundary AND moving towards it
	if future_pos.x < left_bound and dir.x < 0:
		penalty += (left_bound - future_pos.x) * 0.02
	elif future_pos.x > right_bound and dir.x > 0:
		penalty += (future_pos.x - right_bound) * 0.02
	
	if future_pos.y < top_bound and dir.y < 0:
		penalty += (top_bound - future_pos.y) * 0.02
	elif future_pos.y > bottom_bound and dir.y > 0:
		penalty += (future_pos.y - bottom_bound) * 0.02
	
	return penalty
