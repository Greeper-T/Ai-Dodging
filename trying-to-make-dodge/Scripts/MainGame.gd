extends Node2D

@export var bullet_scene: PackedScene
@export var spawn_radius_min := 150.0
@export var spawn_radius_max := 350.0

@onready var player := $Player
@onready var bullet_container := $ProjectileContainer
@onready var timeLabel: Label = $UI/TimerLabel
@onready var timer: Timer = $Timer

var elapsedTime := 0.0
var timesHit = 0
var longestTimeAlive := 0.0

func _ready():
	timer.timeout.connect(spawn_bullet)

func _physics_process(delta: float) -> void:
	elapsedTime += delta
	updateLabel()


func updateLabel():
	var seconds := int(elapsedTime)
	var milliseconds := int((elapsedTime - seconds) * 100)

	if seconds == 15:
		timer.wait_time = .05
	if seconds == 30:
		timer.wait_time = .1

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
