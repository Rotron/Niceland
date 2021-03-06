extends MeshInstance

# World node is optional
export (NodePath) var world

# If the world node is found, then the following variables
# will be copied from there.
var game_seed = 0
var ground_size = 1024.0 * 2.0
var ground_lod_step = 8.0

var noise = preload("res://Scripts/HeightGenerator.gd").new()

var thread = Thread.new()
var gen_verts = []
var view_point
var last_point
var gen_time

var near_far_limit_i = 0
var upd_distance = 16

func _ready():
	
	noise.init()
	
	if(world != null):
		print("Copying ground settings from World")
		world = get_node(world)
		game_seed = world.game_seed
		ground_size = world.ground_size
		ground_lod_step = world.ground_lod_step
	else:
		print("Using default settings for ground")
	
	set_process(false)
	
	upd_distance = float(ground_size) / 16.0
	
	view_point = get_vp()
	last_point = view_point
	
	init_genverts()
	call_deferred("start_generating")

func get_vp():
	var p = get_viewport().get_camera().get_global_transform().origin
	p -= get_viewport().get_camera().get_global_transform().basis.z * upd_distance * 0.75
	p.y = 0.0
	return p

func _process(delta):
	view_point = get_viewport().get_camera().get_global_transform().origin
	view_point.y = 0.0
	if(last_point.distance_to(view_point) > upd_distance):
		start_generating()
	
	

func start_generating():
	print("Start generating ground, seed = ", game_seed)
	gen_time = OS.get_ticks_msec()
	set_process(false)
	view_point = get_vp()
	view_point.x = stepify(view_point.x, ground_lod_step)
	view_point.z = stepify(view_point.z, ground_lod_step)
	
	thread.start(self, "generate", [view_point, game_seed])

func finish_generating():
	var msh = thread.wait_to_finish()
	self.set_mesh(msh)
	
	# TODO: Collider generation. I think Godot has a bug...
	
#	$StaticBody/CollisionShape.set_shape(msh.create_trimesh_shape())
#	print("surf count ",msh.get_surface_count())
#	print("face count ",msh.get_faces().size())
	
	# Generate collider
#	var shp = ConcavePolygonShape.new()
#	shp.set_faces(msh.get_faces())
#	col_shape.set_shape(shp)
#	col_shape.set_disabled(false)
	
	# Generate collider
#	col_shape.set_faces(msh.get_faces())
#	$Collider/CollisionShape.set_shape(col_shape)
#	$Collider/CollisionShape.set_disabled(false)
	
	gen_time = OS.get_ticks_msec() - gen_time
	print("Ground generated in ", gen_time, " msec")
	transform.origin = view_point
	last_point = view_point
	set_process(true)
	

func generate(userdata):
	
	var pos = userdata[0]
	var surf = SurfaceTool.new()
	
	# Generate surface
	surf.begin(Mesh.PRIMITIVE_TRIANGLES)
	surf.add_smooth_group(true)
	var i = 0
	while(i < gen_verts.size()):
		
		# Generate vertex position
		var p = gen_verts[i] + pos
		p.y = noise.get_h(p)
		
		# Generate UV
		if(i < near_far_limit_i):
			# Texture tiles less when far
			surf.add_uv(Vector2(p.x, p.z) / 8.0)
			surf.add_uv2(Vector2(p.x, p.z) / 8.0)
		else:
			# Texture tiles more when near
			surf.add_uv(Vector2(p.x, p.z))
			surf.add_uv2(Vector2(p.x, p.z))
		
		surf.add_vertex(Vector3(gen_verts[i].x, p.y, gen_verts[i].z))
		i += 1
	surf.generate_normals()
	surf.index()
	
	# SurfaceTool to Mesh
	var msh = Mesh.new()
	msh = surf.commit()
	
	call_deferred("finish_generating")
	return msh

func init_genverts():
	var pi = 3.141592654
	var pi2 = pi*2.0
	var small_step = max(ground_lod_step / 8.0, 2.0)
	var a = (360.0 / (360.0 / small_step)) / 57.295779515
	
	# Radial web
	var x = 0.0
	while(x < pi2):
		var s = small_step
		var z = ground_size / 10.0 - ground_lod_step
		while(z <= ground_size):
			
			var z1 = z
			var z2 = z + s
			
			var p1 = Vector3(z1, 0.0, z1)
			var p2 = Vector3(z1, 0.0, z1)
			var p3 = Vector3(z2, 0.0, z2)
			var p4 = Vector3(z2, 0.0, z2)
			
			p1.x *= sin(x)
			p1.z *= cos(x)
			
			p2.x *= sin(x + a)
			p2.z *= cos(x + a)
			
			p3.x *= sin(x + a)
			p3.z *= cos(x + a)
			
			p4.x *= sin(x)
			p4.z *= cos(x)
			
			# Stepifying slightly helps with jumps between lods
			p1.x = stepify(p1.x, ground_lod_step)
			p1.z = stepify(p1.z, ground_lod_step)
			p2.x = stepify(p2.x, ground_lod_step)
			p2.z = stepify(p2.z, ground_lod_step)
			p3.x = stepify(p3.x, ground_lod_step)
			p3.z = stepify(p3.z, ground_lod_step)
			p4.x = stepify(p4.x, ground_lod_step)
			p4.z = stepify(p4.z, ground_lod_step)
			
			gen_verts.append(p1)
			gen_verts.append(p2)
			gen_verts.append(p3)

			gen_verts.append(p3)
			gen_verts.append(p4)
			gen_verts.append(p1)
			
			z += s
#			s *= 2.0
			s += ground_lod_step * 2.0
			
		x += a
	
	near_far_limit_i = gen_verts.size()
	
	# Square grid
	var s = ground_lod_step# * 4.0
	var w = ground_size / 10.0 + s
	x = -w
	while(x < w):
		var z = -w
		while(z < w):
			if(Vector3(x,0,z).length() <= w):
				var p1 = Vector3(x, 0.0, z)
				var p2 = Vector3(x+s, 0.0, z)
				var p3 = Vector3(x+s, 0.0, z+s)
				var p4 = Vector3(x, 0.0, z+s)
				
				gen_verts.append(p1)
				gen_verts.append(p2)
				gen_verts.append(p3)
				
				gen_verts.append(p3)
				gen_verts.append(p4)
				gen_verts.append(p1)
			
			z += s
		x += s
		
	print("Ground tris = ",gen_verts.size() / 3.0)


