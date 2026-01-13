extends Node2D

@export var bullet_scene: PackedScene
@export var spawn_radius_min : float = 150.0
@export var spawn_radius_max : float = 350.0

@onready var player := $Player
@onready var bullet_container := $ProjectileContainer
@onready var timeLabel: Label = $UI/TimerLabel
@onready var timer: Timer = $Timer
@onready var socket_client := $SocketClient  # Add this node in the scene

var elapsedTime := 0.0
var timesHit = 0
var longestTimeAlive := 0.0
var dash_count := 0
var last_dash_penalty_time := 0.0
var total_reward_this_episode := 0.0
var was_dashing_last_frame := false  # Track dash state changes

# AI Mode: "grid" for your current AI, "neural" for Python NN
@export_enum("grid", "neural") var ai_mode: String = "neural"

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
	
	# Initialize danger grid
	danger_grid.resize(GRID_SIZE * GRID_SIZE)
	danger_grid.fill(0.0)
	
	# Connect to socket signal if using neural network mode
	if ai_mode == "neural" and socket_client:
		socket_client.action_received.connect(_on_action_received)

func _physics_process(delta: float) -> void:
	danger_grid = compute_danger_grid()
	queue_redraw()
	
	if ai_mode == "grid":
		# Use your grid-based AI
		var ai_dir := compute_ai_direction()
		player.desired_direction = ai_dir
		player.wants_to_dash = should_ai_dash(delta)
	elif ai_mode == "neural":
		# Send state to Python and wait for action
		send_state_to_python()
		
		# DEBUG: Print reward occasionally
		#if int(elapsedTime * 10) % 30 == 0:  # Every ~3 seconds
			#var recent_reward = calculate_reward()
			#print("Current reward per frame: %.2f | Dashing: %s | Danger: %.2f" % 
				#[recent_reward, player.dash_timer > 0.0, danger_grid[GRID_CENTER * GRID_SIZE + GRID_CENTER]])
	
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
	# Send terminal state if using neural network FIRST (before clearing bullets)
	if ai_mode == "neural" and socket_client and socket_client.connected:
		var terminal_state := {
			"done": true,
			"reward": -200.0,  # HUGE penalty for dying
			"time_alive": elapsedTime,
			"danger_grid": [],
			"player_pos": [0.0, 0.0],
			"player_vel": [0.0, 0.0],
			"bullets": [],
			"can_dash": true
		}
		socket_client.send_state(terminal_state)
		
		# Debug output
		print("Episode ended | Time: %.2f | Dashes: %d | Total Reward: %.1f" % [elapsedTime, dash_count, total_reward_this_episode])
		
		# Give Python time to process the terminal state
		await get_tree().create_timer(0.1).timeout
	
	player.global_position = Vector2.ZERO
	if elapsedTime > longestTimeAlive:
		longestTimeAlive = elapsedTime
	
	var seconds := int(longestTimeAlive)
	var milliseconds := int((longestTimeAlive - seconds) * 100)
	
	$UI/Record.text = "Record: %02d.%02d" % [seconds, milliseconds]
	
	elapsedTime = 0
	timer.wait_time = .5
	timesHit += 1
	dash_count = 0  # Reset dash counter
	total_reward_this_episode = 0.0  # Reset reward tracking
	was_dashing_last_frame = false  # Reset dash tracking
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
	
	# Sanity check
	if grid.size() != 121:
		print("CRITICAL ERROR: Grid initialized with size %d instead of 121" % grid.size())

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
	
	# Final verification before returning
	if grid.size() != 121:
		print("CRITICAL ERROR: Grid size changed to %d after processing" % grid.size())

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


# ===== NEURAL NETWORK COMMUNICATION =====

func send_state_to_python():
	if not socket_client or not socket_client.connected:
		return
	
	# Make sure danger grid exists and has correct size
	if danger_grid.is_empty() or danger_grid.size() != GRID_SIZE * GRID_SIZE:
		print("WARNING: Danger grid not ready (size: %d), computing now..." % danger_grid.size())
		danger_grid = compute_danger_grid()
	
	# Flatten danger grid to array
	var danger_array := []
	for i in range(danger_grid.size()):
		danger_array.append(danger_grid[i])
	
	# Final safety check
	if danger_array.size() != 121:
		print("ERROR: Danger array size is %d, padding to 121" % danger_array.size())
		while danger_array.size() < 121:
			danger_array.append(0.0)
	
	# Get closest bullets info
	var bullet_info := get_closest_bullets(5)
	
	# Prepare state dictionary
	var state := {
		"danger_grid": danger_array,
		"player_pos": [player.global_position.x, player.global_position.y],
		"player_vel": [player.velocity.x, player.velocity.y],
		"bullets": bullet_info,
		"time_alive": elapsedTime,
		"can_dash": player.dash_cooldown_timer <= 0.0,
		"reward": calculate_reward(),
		"done": false
	}
	
	socket_client.send_state(state)

func get_closest_bullets(count: int) -> Array:
	var bullets := []
	var bullet_distances := []
	
	for child in bullet_container.get_children():
		var bullet := child as Area2D
		if bullet == null:
			continue
		
		var dist :float= player.global_position.distance_to(bullet.global_position)
		bullet_distances.append({"bullet": bullet, "dist": dist})
	
	# Sort by distance
	bullet_distances.sort_custom(func(a, b): return a.dist < b.dist)
	
	# Get closest N bullets
	for i in range(min(count, bullet_distances.size())):
		var bullet = bullet_distances[i].bullet
		if bullet.has_method("get_velocity"):
			var vel = bullet.get_velocity()
			bullets.append({
				"pos": [bullet.global_position.x, bullet.global_position.y],
				"vel": [vel.x, vel.y],
				"dist": bullet_distances[i].dist
			})
	
	return bullets

func calculate_reward() -> float:
	# Base reward for staying alive
	var reward := 2.0  # Increased base reward
	
	# STRONG penalty for being in danger (scales with how dangerous)
	var center_danger := danger_grid[GRID_CENTER * GRID_SIZE + GRID_CENTER]
	if center_danger > 0.0:
		# Exponential penalty - being in extreme danger is REALLY bad
		reward -= center_danger * center_danger * 20.0
	
	# Penalty for being near screen edges
	var viewport_size := get_viewport_rect().size
	var margin := 100.0
	var edge_penalty := 0.0
	
	if player.global_position.x < margin or player.global_position.x > viewport_size.x - margin:
		edge_penalty += 0.5
	if player.global_position.y < margin or player.global_position.y > viewport_size.y - margin:
		edge_penalty += 0.5
	
	reward -= edge_penalty
	
	# Detect NEW dash (just started dashing this frame)
	var is_dashing_now :bool= player.dash_timer > 0.0
	if is_dashing_now and not was_dashing_last_frame:
		# MASSIVE penalty per dash
		reward -= 500.0
		dash_count += 1
	
	# Bonus for having dash available but NOT using it (smart play)
	if not is_dashing_now and player.dash_cooldown_timer <= 0.0 and center_danger < 0.3:
		reward += 0.5
	
	was_dashing_last_frame = is_dashing_now
	
	# Track total reward for debugging
	total_reward_this_episode += reward
	
	return reward

func _on_action_received(action_data: Dictionary):
	# Parse action from neural network
	if action_data.has("direction"):
		var dir_array = action_data["direction"]
		player.desired_direction = Vector2(dir_array[0], dir_array[1])
	
	if action_data.has("dash"):
		player.wants_to_dash = action_data["dash"]
