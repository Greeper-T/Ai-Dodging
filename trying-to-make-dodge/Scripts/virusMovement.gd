extends Area2D


@export var speed := randf_range(100,150)
var direction := Vector2.ZERO

func _physics_process(delta: float) -> void:
	position += direction * speed * delta


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		#print("collided")
		get_parent().get_parent().reset()
		queue_free()


func get_velocity() -> Vector2:
	return direction * speed


func _on_timer_timeout() -> void:
	queue_free()
