## Juice: sparks, screen flashes, camera shake, slow motion. It only listens to the
## Arena's signals (Observer), so the rules never know any of this exists, and
## deleting this file leaves a working, quieter game.
class_name Effects
extends Node3D

const EMBER := Color(1.0, 0.45, 0.12)
const ARCANE := Color(0.65, 0.35, 1.0)
const BLOOD := Color(1.0, 0.15, 0.1)
const MAX_SHAKE := 0.5  # camera offset in meters at full trauma

var camera: Camera3D
var _trauma := 0.0  # 0..1; the shake grows with its square, so small bumps stay subtle
var _flash := ColorRect.new()
var _sparks := {}  # color -> Mesh, one glowing cube per color shared by every burst


func _init(follow: Camera3D) -> void:
	camera = follow
	var layer := CanvasLayer.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	layer.add_child(_flash)
	add_child(layer)


## Subscribe to a new game's Arena. The old Arena's connections die with it.
func watch(arena: Arena) -> void:
	arena.ate.connect(func(cell): _burst(_center(cell), EMBER, 24, 4.0))
	arena.powered.connect(
		func(_powerup):
			_burst(_center(arena.dragon.body[0]), ARCANE, 40, 6.0)
			_flash_screen(ARCANE, 0.25)
	)
	arena.died.connect(
		func(_reason):
			var heading := arena.dragon.heading
			var impact := _center(arena.dragon.body[0]) + Vector3(heading.x, 0, heading.y) * 0.5
			_burst(impact, BLOOD, 60, 7.0)
			_flash_screen(BLOOD, 0.35)
			_trauma = 1.0
			_slow_motion(0.25, 0.6)
	)


func _process(delta: float) -> void:
	_trauma = maxf(_trauma - delta * 1.5, 0.0)
	var shake := MAX_SHAKE * _trauma * _trauma
	camera.h_offset = randf_range(-shake, shake)  # offsets leave the follow logic alone
	camera.v_offset = randf_range(-shake, shake)


## A one-shot puff of glowing cubes that frees itself when the last one fades.
func _burst(at: Vector3, color: Color, amount: int, speed: float) -> void:
	var burst := CPUParticles3D.new()
	burst.mesh = _spark(color)
	burst.amount = amount
	burst.one_shot = true
	burst.explosiveness = 0.95
	burst.lifetime = 0.8
	burst.lifetime_randomness = 0.4
	burst.direction = Vector3.UP
	burst.spread = 65.0
	burst.initial_velocity_min = speed * 0.4
	burst.initial_velocity_max = speed
	burst.gravity = Vector3(0, -12, 0)
	burst.angular_velocity_min = -360.0
	burst.angular_velocity_max = 360.0
	burst.scale_amount_min = 0.6
	burst.scale_amount_max = 1.4
	burst.scale_amount_curve = _fade_out()
	burst.position = at + Vector3(0, 0.3, 0)
	burst.finished.connect(burst.queue_free)
	add_child(burst)
	burst.emitting = true


func _flash_screen(color: Color, alpha: float) -> void:
	_flash.color = Color(color, alpha)
	var tween := create_tween().set_ignore_time_scale()  # fades at full speed in slow motion
	tween.tween_property(_flash, "color:a", 0.0, 0.4)


## Slow the whole engine briefly. The timer ignores time scale, or it would slow itself.
func _slow_motion(scale: float, seconds: float) -> void:
	Engine.time_scale = scale
	get_tree().create_timer(seconds, true, false, true).timeout.connect(
		func(): Engine.time_scale = 1.0
	)


## Emission above the glow threshold is what makes sparks bloom.
func _spark(color: Color) -> Mesh:
	if not _sparks.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color.darkened(0.5)
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 4.0
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE * 0.09
		cube.material = material
		_sparks[color] = cube
	return _sparks[color]


func _fade_out() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	return curve


func _center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, 0, cell.y + 0.5)
