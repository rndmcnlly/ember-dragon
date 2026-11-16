## Draws one dragon from the kit's pieces. The player's dragon and the rival are two of
## these; they differ only in which pieces they use ("head" or "rival_head"), because
## tools/build_art.py builds the rival's kit as the same shapes in another palette.
class_name DragonView
extends Node3D

const WAVE_HEIGHT := 0.06  # how far each segment rises and falls
const WAVE_SPEED := 8.0  # radians per second
const WAVE_STEP := 0.8  # radians between neighbors, so the wave runs head to tail

var meshes: Dictionary  # piece name -> Mesh, shared with every other view (Flyweight)
var prefix := ""  # "" for the hero's pieces, "rival_" for the rival's
var segments: Array[MeshInstance3D] = []
var _previous: Array[Vector2i] = []  # the body before the latest tick, to draw in-between
var _head_yaw := 0.0


func _init(kit: Dictionary, piece_prefix := "") -> void:
	meshes = kit
	prefix = piece_prefix


## Start drawing a new dragon (or none): forget where the last one was.
func reset(body: Array[Vector2i]) -> void:
	_previous = body.duplicate()
	visible = not body.is_empty()
	if not body.is_empty():
		_head_yaw = Kit.layout(body)[0][1] * PI / 2


## The rules are about to move the dragon: remember where it was.
func before_tick(body: Array[Vector2i]) -> void:
	_previous = body.duplicate()


## Draw the dragon partway between its last two ticks (t from 0 to 1). The cells in
## between already form a continuous body, so only the ends need to move: the head
## slides out of the neck, and the old tail slides into the cell it leaves behind.
## Returns where the head is drawn, for the camera.
func draw(body: Array[Vector2i], t: float, delta: float, ghost := false) -> Vector3:
	var path: Array[Vector2i] = body.duplicate()
	var old_tail: Vector2i = _previous.back()
	var tail_slides := (old_tail - body[-1]).length_squared() == 1  # not growing or trimmed
	if tail_slides:
		path.append(old_tail)
	while segments.size() < path.size():
		var segment := MeshInstance3D.new()
		add_child(segment)
		segments.append(segment)

	var placed := Kit.layout(path)
	var now := Time.get_ticks_msec() / 1000.0
	for i in segments.size():
		var segment := segments[i]
		segment.visible = i < path.size()
		if not segment.visible:
			continue
		segment.mesh = meshes[prefix + Kit.Piece.keys()[placed[i][0]].to_lower()]
		segment.position = _center(path[i])
		segment.rotation.y = placed[i][1] * PI / 2
		segment.transparency = 0.5 if ghost else 0.0
		# The wave's phase follows each cell's age (i + t), so it never jumps on a tick.
		segment.position.y = WAVE_HEIGHT * (1 + sin(now * WAVE_SPEED - (i + t) * WAVE_STEP))

	var head := segments[0]
	if (_previous[0] - body[0]).length_squared() == 1:
		head.position = _center(_previous[0]).lerp(_center(body[0]), t)
		head.position.y = WAVE_HEIGHT * (1 + sin(now * WAVE_SPEED))
	_head_yaw = lerp_angle(_head_yaw, head.rotation.y, 1 - exp(-30 * delta))
	head.rotation.y = _head_yaw
	if tail_slides:
		var tail := segments[path.size() - 1]
		var lift := tail.position.y
		tail.position = _center(old_tail).lerp(_center(body[-1]), t) + Vector3.UP * lift
	return head.position


func _center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, 0, cell.y + 0.5)
