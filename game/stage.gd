## The world around the Arena: sky, sun, and the board's tiles. Built once and never
## changed during play, so each kind of tile is one MultiMesh (Flyweight made visible:
## one mesh uploaded once, drawn at a thousand transforms in one call).
class_name Stage
extends Node3D

const SKY_TOP := Color("1b2f4a")
const HORIZON := Color("e0936a")  # dusk; the fog uses it too, so the floor melts into the sky
const EARTH := Color("3a2f2a")  # warm dark ground beyond the walls
const RAISED := ["wall"]  # kinds that rise out of the ground; every other kind is walked on
## Colors for plain boxes when the kit lacks a kind's mesh. Magenta means "art missing".
const FALLBACK_COLORS := {"floor": Color("9c8a6c"), "wall": Color("4d4038")}

var rng := RandomNumberGenerator.new()  # seeded, so the stage looks the same every load


## board maps each cell (Vector2i) to a kind name ("floor", "wall", ...); meshes maps
## kind names to the kit's meshes. A new kind needs a mesh, not new code here.
func _init(board: Dictionary, meshes: Dictionary) -> void:
	rng.seed = 121
	add_child(_world())
	add_child(_sun())
	var cells_of := {}  # kind -> the cells that hold it
	var middle := Vector2.ZERO
	for cell in board:
		if not cells_of.has(board[cell]):
			cells_of[board[cell]] = []
		cells_of[board[cell]].append(cell)
		middle += Vector2(cell) / board.size()
	for kind in cells_of:
		var raised: bool = kind in RAISED
		add_child(_scatter(_mesh_for(kind, meshes, raised), cells_of[kind], raised))
	add_child(_skirt(middle))


## Sky, ambient light, tonemapping, glow, ambient occlusion, and fog in one resource.
func _world() -> WorldEnvironment:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = SKY_TOP
	sky_material.sky_horizon_color = HORIZON
	sky_material.ground_horizon_color = HORIZON
	sky_material.ground_bottom_color = EARTH
	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY  # cool from above
	environment.ambient_light_energy = 0.5
	# AgX keeps hues as they brighten, so embers stay orange instead of going yellow-white.
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0
	environment.tonemap_agx_contrast = 1.3
	# The web renderer's color buffer tops out near 1.0, so the glow threshold sits
	# just below that: only emissive things (eyes, embers, sparks) bleed light.
	environment.glow_enabled = true
	environment.glow_hdr_threshold = 0.85
	environment.glow_intensity = 0.9
	environment.glow_bloom = 0.03
	environment.adjustment_enabled = true  # AgX mutes greens a little; win them back
	environment.adjustment_saturation = 1.2
	environment.ssao_enabled = true  # dark creases where the dragon meets the floor
	environment.ssao_radius = 0.6
	environment.ssao_intensity = 1.2
	# Depth fog fades the far floor to the horizon color, hiding the edge of the world.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = HORIZON.darkened(0.2)
	environment.fog_depth_begin = 22.0
	environment.fog_depth_end = 70.0
	environment.fog_sky_affect = 0.0
	var world := WorldEnvironment.new()
	world.environment = environment
	return world


## A low warm sun: long soft shadows read as "late afternoon" and show the shapes.
func _sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_color = Color("ffd2a1")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 30.0  # only what the follow camera sees
	return sun


## Ground beyond the walls, just under the tiles, so the arena is not floating in the sky.
func _skirt(middle: Vector2) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = EARTH
	material.roughness = 1.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	plane.material = material
	var skirt := MeshInstance3D.new()
	skirt.mesh = plane
	skirt.position = Vector3(middle.x + 0.5, -0.2, middle.y + 0.5)
	return skirt


## One MultiMesh draws a copy of mesh in every cell. Raised kinds stand with their
## bottom at y = 0, the rest lie with their top at y = 0, whatever size the kit made them.
func _scatter(mesh: Mesh, cells: Array, raised: bool) -> MultiMeshInstance3D:
	var rest_y := -mesh.get_aabb().position.y if raised else -mesh.get_aabb().end.y
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true  # must be set before instance_count
	multimesh.mesh = _tintable(mesh)
	multimesh.instance_count = cells.size()
	for i in cells.size():
		var cell: Vector2i = cells[i]
		# Quarter turns and small height changes keep a thousand copies from looking stamped.
		var height := rng.randf_range(0.85, 1.15) if raised else 1.0
		var basis := Basis(Vector3.UP, rng.randi_range(0, 3) * PI / 2).scaled(Vector3(1, height, 1))
		var y := rest_y * height + (0.0 if raised else rng.randf_range(-0.015, 0.015))
		multimesh.set_instance_transform(
			i, Transform3D(basis, Vector3(cell.x + 0.5, y, cell.y + 0.5))
		)
		var shade := (1.0 if (cell.x + cell.y) % 2 == 0 else 0.9) * rng.randf_range(0.94, 1.04)
		multimesh.set_instance_color(i, Color(shade, shade, shade))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	return instance


## Instance colors only show when the material multiplies albedo by vertex color, so
## we copy the kit's mesh and switch that on (the shared kit mesh stays untouched).
func _tintable(mesh: Mesh) -> Mesh:
	var copy: Mesh = mesh.duplicate()
	for surface in copy.get_surface_count():
		var material := copy.surface_get_material(surface)
		if material is BaseMaterial3D and not material.vertex_color_use_as_albedo:
			material = material.duplicate()
			material.vertex_color_use_as_albedo = true
			copy.surface_set_material(surface, material)
	return copy


## The kit's mesh for this kind, or a plain box so a missing model never stops the game.
func _mesh_for(kind: String, meshes: Dictionary, raised: bool) -> Mesh:
	if meshes.has(kind):
		return meshes[kind]
	var material := StandardMaterial3D.new()
	material.albedo_color = FALLBACK_COLORS.get(kind, Color.MAGENTA)
	material.roughness = 0.9
	material.vertex_color_use_as_albedo = true
	var box := BoxMesh.new()
	box.size = Vector3(1, 0.7 if raised else 0.15, 1)
	box.material = material
	return box
