extends Area2D


func _ready() -> void:
	pass # Replace with function body.

@export var speed := randf_range(100,400)
var direction := Vector2.ZERO

func _process(delta: float) -> void:
	position += direction * speed * delta


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		print("collided")
		queue_free()


func _on_timer_timeout() -> void:
	queue_free()
