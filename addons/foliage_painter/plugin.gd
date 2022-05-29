@tool
extends EditorPlugin

enum MODE {
	SELECT_MODE = 0,
	FOLIAGE_MODE = 1
}

#最大面积100m * 100m
const MAX_CALCULATE_AREA:float = 100
const FOLIAGE_NAME:String = "Foliage3D"
const BRUSH_NAME:String = "Brush"
const BLOCK_NAME:String = "Block"
const Foliage3D = preload("./ui/foliage3d.gd")
const PaletteScene = preload("./ui/palette.tscn")
const TIME_LIMIT:float = 0.05
#const Octree = preload("./scripts/octree.gd")
var Brush3D = preload("./mesh/brush.tscn")
#左侧素材列表
var _palette:Palette = preload("./ui/palette.tscn").instantiate()
#顶部模式选择UI
var _topui = preload("./ui/topui.tscn").instantiate()

#绘制根节点
var foliage : Foliage3D
var brush:MeshInstance3D
#分块计算逻辑
var block:Block = null
var _selected_elements := []
var _mouse_position := Vector2()
#var _editor_camera : Camera3D
#var _collision_mask := 1
#var _placed_instances = []
#var _removed_instances = []
#var _disable_undo := false
#var _current_action := -1
#var _cmd_pending_action := false
#可以绘制
var start_paint:bool = true
#按键CD
var shortcut_cd:float = 0
var mouse_left_pressed:bool = false
var mouse_right_pressed:bool = false
#摄像机
#var _viewport_camera:Camera3D = null
#一次绘制完成
var _paint_complete:bool = true

static func get_icon(name):
	return load("res://addons/foliage_painter/icons/icon_" + name + ".svg")


func _enter_tree():
	print("Scatter plugin Enter tree")
	
	set_physics_process(false)
	
	_topui.connect("toggle_mode",_on_toggle_mode)
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU,_topui)
	
	add_custom_type("Foliage3D", "Node3D", Foliage3D, get_icon("scatter3d_node"))
	
	var base_control = get_editor_interface().get_base_control()

	_palette.connect("elements_selected", _on_Palette_element_selected)
	_palette.connect("element_added", _on_Palette_element_added)
	_palette.connect("elements_removed", _on_Palette_patterns_removed)
	_palette.connect("brush_size_changed", _on_Brush_size_changed)
	_palette.connect("update_block_data",_on_update_block_data)
	_palette.hide()
	add_control_to_container(CustomControlContainer.CONTAINER_SPATIAL_EDITOR_SIDE_LEFT,_palette)
	_palette.set_preview_provider(get_editor_interface().get_resource_previewer())
	_palette.call_deferred("setup_dialogs", base_control)
	
	#初始化分块计算逻辑
	init_block()
	show_brush(false)
	
	set_input_event_forwarding_always_enabled()

func _exit_tree():

	remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU,_topui)
	remove_custom_type("Scatter3D")
	remove_control_from_container(CustomControlContainer.CONTAINER_SPATIAL_EDITOR_SIDE_LEFT,_palette)
	
	if _palette != null:
		_palette.queue_free()
		_palette = null

func _handles(object):
	pass

func _edit(obj):
	pass

func _process(delta):
	if shortcut_cd <= TIME_LIMIT:
		shortcut_cd += delta
	if Input.is_key_pressed(KEY_BRACKETLEFT):
		if _palette.mode == MODE.FOLIAGE_MODE and _palette.tool_mode != _palette.SINGLE and brush.visible == true and shortcut_cd >= TIME_LIMIT:
			shortcut_cd = 0
			_palette.on_change_brush_size(-10)
	elif Input.is_key_pressed(KEY_BRACKETRIGHT):
		if _palette.mode == MODE.FOLIAGE_MODE and _palette.tool_mode != _palette.SINGLE and brush.visible == true and shortcut_cd >= TIME_LIMIT:
			shortcut_cd = 0
			_palette.on_change_brush_size(10)
 
func _forward_3d_gui_input(p_camera:Camera3D, p_event:InputEvent):
	if _palette.mode == MODE.SELECT_MODE:
		return false
	if foliage == null:
		return false
	if _selected_elements.size() == 0:
		show_brush(false)
		return false
	
	if mouse_right_pressed:
		show_brush(false)
		if not (p_event is InputEventMouseButton and not p_event.pressed and p_event.button_index == MOUSE_BUTTON_RIGHT):
			return false
	elif mouse_right_pressed == false and brush.visible == false:
		show_brush(true)

	#射线检测
	if p_event is InputEventMouseMotion:
		var mouse_position = p_event.position
		var viewport = p_camera.get_viewport()
		var viewport_container:SubViewportContainer = viewport.get_parent()
		var screen_position = mouse_position * Vector2(viewport.size) / viewport_container.size
		_mouse_position = screen_position

	var ray_origin = p_camera.project_ray_origin(_mouse_position)
	var ray_dir = p_camera.project_ray_normal(_mouse_position)
	var ray_distance = p_camera.far

	var hit:Dictionary = ray_cast(ray_origin, ray_origin + ray_dir * ray_distance)
	if hit.is_empty():
		return

	var captured_event = false
	#鼠标按钮判定
	if p_event is InputEventMouseButton:
		if p_event.pressed:
			if p_event.button_index == MOUSE_BUTTON_LEFT:
				mouse_left_pressed = true
				captured_event = true
				if _palette.tool_mode == _palette.SINGLE:
#					if _viewport_camera == null:
#						_viewport_camera = p_camera
					var element:MeshInstance3D = _random_element_instance()
					_single(hit.position,element)
#				if _palette.tool_mode == _palette.PAINT:
#					_paint()
				elif _palette.tool_mode == _palette.ERASE:
					_erase()
			elif p_event.button_index == MOUSE_BUTTON_RIGHT:
				mouse_right_pressed = true
		else:
			if p_event.button_index == MOUSE_BUTTON_LEFT:
				mouse_left_pressed = false
			elif p_event.button_index == MOUSE_BUTTON_RIGHT:
				mouse_right_pressed = false
	
	if _palette.tool_mode == _palette.PAINT or _palette.tool_mode == _palette.ERASE:
		start_paint = true
				
	#如果鼠标左键按下
	if p_event is InputEventMouseMotion and mouse_left_pressed and start_paint:
		start_paint = false
		if _palette.tool_mode == _palette.PAINT:
			_paint()
		elif _palette.tool_mode == _palette.ERASE:
			_erase()
	
	return captured_event

func ray_cast(ray_origin: Vector3, ray_end: Vector3) -> Dictionary:
	var space_state =  get_viewport().world_3d.direct_space_state
	var pt:PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	pt.from = ray_origin
	pt.to = ray_origin + ray_end
#	pt.exclude = []
#	pt.collision_mask = 1
	var hit = space_state.intersect_ray(pt)
	
	if hit.is_empty():
		return hit
	
	var hit_instance_root
	# Collider can be null if the hit is on something that has no associated node
	if hit.collider != null:
		hit_instance_root = FoliagePainterUtil.get_instance_root(hit.collider)
	
#	if hit.collider == null or not (hit_instance_root.get_parent() is Foliage3D):
	if hit.collider == null or not (hit_instance_root.has_meta("path")):
		var pos = hit.position
		brush.position = hit.position
	return hit

func _paint():
	if not _paint_complete:
		return
	_paint_complete = false
#	var start_time = Time.get_ticks_msec()
	var datas:Array[Dictionary] = calculate_points()
	
	#TODO 清除掉已经刷过的地方
	var brush_position:Vector3 = brush.position
	var radius:float = brush.get_radius()
	#筛掉所有已绘制的部分
	for data in datas:
		var e_path:String = data["element"].get_meta("path")
		var points:Array[Vector3] = data["points"]
		var path_list:Array[String] = [e_path]
		var results:Array = block.search(brush_position,radius,path_list)
		var property:ElementProperty = _palette.get_element_property(e_path)
		var r:float = property.radius / 100.0
		for ele in results:
			for p in points:
				var dis:float = p.distance_to(ele.position)
				
				if dis < r:
					points.erase(p)
#	var end_time = Time.get_ticks_msec()
#	var a = end_time - start_time
#	var temp1:String = "算点->开始时间: %f,结束时间: %f,时间差: %f" % [start_time,end_time,a]
#	print("------------")
#	print(temp1)
	
	#绘制
	for dic in datas:
		var poins:Array[Vector3] = dic["points"]
		var path:String = dic["element"].get_meta("path")
		var layer_name:String = get_layer_name(path)
		var layer = foliage.get_node_or_null(layer_name)
		
		if layer == null:
			print("add Layer")
			layer = Node3D.new()
			layer.name = layer_name
			foliage.add_child(layer)
			layer.owner = get_editor_interface().get_edited_scene_root()
		for pos in poins:
			var instance = dic["element"].instantiate()
			instance.set_meta("path",path)
			_draw(pos,instance,path,layer)
		var count = layer.get_child_count()
		_palette.update_element_number(path,count)
	_paint_complete = true
#	var end_time1 = Time.get_ticks_msec()
#	var b = end_time1 - end_time
#	var temp2:String = "摆放模型->开始时间: %f,结束时间: %f,时间差: %f" % [end_time,end_time1,b]
#	print(temp2)
	
func _single(pos:Vector3,instance:Node3D):
	var path = instance.get_meta("path")
	var layer_name:String = get_layer_name(path)
	var layer = foliage.get_node_or_null(layer_name)
	
	if layer == null:
		print("添加Layer")
		layer = Node3D.new()
		layer.name = layer_name
		foliage.add_child(layer)
		layer.owner = get_editor_interface().get_edited_scene_root()
	_draw(pos,instance,path,layer)
	var e_path = instance.get_meta("path")
#	var layer = get_layer(e_path)
	var count = layer.get_child_count()
	_palette.update_element_number(path,count)

func _draw(pos:Vector3,instance:Node3D,path:String,layer:Node3D):
#	var path = instance.get_meta("path")
#	var layer_name:String = get_layer_name(path)
#	var layer = foliage.get_node_or_null(layer_name)
#
#	if layer == null:
#		print("添加Layer")
#		layer = Node3D.new()
#		layer.name = layer_name
#		foliage.add_child(layer)
#		layer.owner = get_editor_interface().get_edited_scene_root()

	#user property
	var property:ElementProperty = _palette.get_element_property(path)
	#random y offset from min ~ max
	var yOffset:float = randf_range(property.yOffsetMin,property.yOffsetMax)
	#10 times smaller,so -1000 to 1000 is -10 meter to 10 meter
	yOffset /= 10
	instance.position = pos + Vector3(0,yOffset,0)
	#random roate from min ~ max
	var angle:float = randf_range(property.rotateMin,property.rotateMax)
	var rad:float = deg2rad(angle)
	instance.rotate_y(rad)
	#random scale from min ~ max
	var s:float = randf_range(property.scaleMin,property.scaleMax)
	instance.scale = Vector3(s,s,s)
	
	layer.add_child(instance)
	instance.owner = get_editor_interface().get_edited_scene_root()
	#添加到分块算法里
	block.add_element(instance)
#	var count = layer.get_child_count()
#	_palette.update_element_number(path,count)

func _erase():
	pass
	if brush == null:
		return
#	var start_time = Time.get_ticks_msec()
	var brush_position:Vector3 = brush.position
	var radius:float = brush.get_radius()
	
	var path_list:Array[String] = FoliagePainterUtil.get_path_list(_selected_elements)
	var results:Array = block.search(brush_position,radius,path_list,true)
	if results.size() == 0:
		return
#	var end_time = Time.get_ticks_msec()
#	var a = end_time - start_time
#	var temp1:String = "检测查找->开始时间: %f,结束时间: %f,时间差: %f" % [start_time,end_time,a]
#	print("------------")
#	print(temp1)
#	print("找到了几个: ",len(results))
	for e in results:
		var element:Node3D = e as Node3D
		var parent:Node3D = element.get_parent_node_3d()
		if parent:
			parent.remove_child(element)
			if parent.get_child_count() == 0:
				parent.queue_free()
	for path in path_list:
		var layer = get_layer(path)
		if layer:
			var count = layer.get_child_count()
			_palette.update_element_number(path,count)
	#TODO 更新实例的数量
#	var end_time1 = Time.get_ticks_msec()
#	var b = end_time1 - end_time
#	var temp2:String = "开始删除->开始时间: %f,结束时间: %f,时间差: %f" % [end_time,end_time1,b]
#	print(temp2)

#func _on_action_completed(action: int):
#	if action == ACTION_PAINT:
#		pass
#		if len(_placed_instances) == 0:
#			return
		# TODO This will creep memory until the scene is closed...
		# Because in Godot, undo/redo of node creation/deletion is done by NOT deleting them.
		# To stay in line with this, I have to do the same...
#		var ur = get_undo_redo()
#		ur.create_action("Paint scenes")
#		for instance in _placed_instances:
#			# This is what allows nodes to be freed
#			ur.add_do_reference(instance)
#		_disable_undo = true
#		ur.add_do_method(self, "_redo_paint", foliage.get_path(), _placed_instances.duplicate(false))
#		ur.add_undo_method(self, "_undo_paint", foliage.get_path(), _placed_instances.duplicate(false))
#		ur.commit_action()
#		_disable_undo = false
#		_placed_instances.clear()

#	elif action == ACTION_ERASE:
#		pass
#		if len(_removed_instances) == 0:
#			return
#		var ur = get_undo_redo()
#		ur.create_action("Erase painted scenes")
#		for instance in _removed_instances:
#			ur.add_undo_reference(instance)
#		_disable_undo = true
#		ur.add_do_method(self, "_redo_erase", foliage.get_path(), _removed_instances.duplicate(false))
#		ur.add_undo_method(self, "_undo_erase", foliage.get_path(), _removed_instances.duplicate(false))
#		ur.commit_action()
#		_disable_undo = false
#		_removed_instances.clear()



#func _redo_paint(parent_path, instances_data):
#	if _disable_undo:
#		return
#	var parent = get_node(parent_path)
#	for instance in instances_data:
#		parent.add_child(instance)
#
#
#func _undo_paint(parent_path, instances_data):
#	if _disable_undo:
#		return
#	var parent = get_node(parent_path)
#	for instance in instances_data:
#		parent.remove_child(instance)


#func _redo_erase(parent_path, instances_data):
#	if _disable_undo:
#		return
#	var parent = get_node(parent_path)
#	for instance in instances_data:
#		instance.get_parent().remove_child(instance)
#
#
#func _undo_erase(parent_path, instances_data):
#	if _disable_undo:
#		return
#	var parent = get_node(parent_path)
#	for instance in instances_data:
#		parent.add_child(instance)

func init_block():
	block = Block.new(8,400,2)
	if foliage:
		block.update(foliage)

# Goes up the tree from the given node and finds the first Scatter layer,
# then return the immediate child of it from which the node is child of
func get_scatter_child_instance(node, scatter_root):
	var parent = node
	while parent != null:
		parent = node.get_parent()
		if parent != null and parent == scatter_root:
			return node
		node = parent
	return null


func _set_selected_elements(patterns):
	if _selected_elements != patterns:
		_selected_elements = patterns
#		var largest_aabb = AABB()
#		for pattern in patterns:
#			var temp = pattern.instantiate()
#			# TODO This causes errors because of accessing `global_transform` outside the tree... Oo
#			# See https://github.com/godotengine/godot/issues/30445
#			largest_aabb = largest_aabb.merge(FoliagePainterUtil.get_scene_aabb(temp))
#			temp.free()
#		_pattern_margin = largest_aabb.size.length() * 0.4


#随机获得一个element
func _random_element_instance():
	var rand:int = randi_range(0,_selected_elements.size() - 1)
	var ins = _selected_elements[rand].instantiate()
	var path = _selected_elements[rand].get_meta("path")
	ins.set_meta("path",path)
	return ins


func _on_Palette_element_selected(pattern_paths):
	var scenes = []
	for file in pattern_paths:
		var packet = load(file)
		packet.set_meta("path",file)
		scenes.append(packet)
	_set_selected_elements(scenes)


func _on_Palette_element_added(path):
	if not _verify_element(path):
		return
	_add_element(path)
	# TODO Duh, may not work if the file was moved or renamed... I'm tired of this
#	var ur = get_undo_redo()
#	ur.create_action("Add scatter pattern")
#	ur.add_do_method(self, "_add_pattern", path)
#	ur.add_undo_method(self, "_remove_pattern", path)
#	ur.commit_action()


func _on_Palette_patterns_removed(paths):
	for path in paths:
		_remove_element(path)
#	var ur = get_undo_redo()
#	ur.create_action("Remove scatter pattern")
#	for path in paths:
#		ur.add_do_method(self, "_remove_pattern", path)
#		ur.add_undo_method(self, "_add_pattern", path)
#	ur.commit_action()


func _add_element(path):
	foliage.add_element(path)
	_palette.add_element(path)


func _remove_element(path):
	foliage.remove_element(path)
	_palette.remove_element(path)

func _on_Brush_size_changed():
	brush.update_size(_palette.brushSize.value)

func _on_update_block_data():
#	block.print_all_block()
	if foliage:
		block.update(foliage)

func _verify_element(fpath):
	# Check it can be loaded
	var scene = load(fpath)
	if scene == null:
		print("Could not load the scene. See the console for more info.")
		return false

	# Check it's not already in the list
	if foliage.has_element(fpath):
		_palette.select_element(fpath)
		print("The selected scene is already in the palette")
		return false

	# Check it's not the current scene itself
	if FoliagePainterUtil.is_self_or_parent_scene(fpath, foliage):
		print("The selected scene can't be added recursively")
		return false

	# Check it inherits Node3D
#	var scene_state = scene.get_state()
#	var root_type = scene_state.get_node_type(0)
	# Aaaah screw this
	var scene_instance = scene.instantiate()
	if not (scene_instance is Node3D):
		print("The selected scene is not a Node3D, it can't be painted in a 3D scene.")
		scene_instance.free()
		return false
	scene_instance.free()

	return true

#切换模式
func _on_toggle_mode(id):
	_palette.mode = id
	match id:
		MODE.SELECT_MODE:
			select_mode()
		MODE.FOLIAGE_MODE:
			foliage_mode()

func select_mode():
#	set_physics_process(false)
	_palette.set_visible(false)
	show_brush(false)

func foliage_mode():
	#获取主场景
	var root = get_editor_interface().get_edited_scene_root()
	var f = root.get_node_or_null(FOLIAGE_NAME)
	#植被根节点
	if f == null:
		print("没有Foliage3D")
		foliage = Foliage3D.new()
		foliage.name = FOLIAGE_NAME
		root.add_child(foliage)
		foliage.owner = root
	else:
		foliage = f
	#刷子
	var b = foliage.get_node_or_null(BRUSH_NAME)
	if b == null:
		print("没有Brush")
		brush = Brush3D.instantiate()
		brush.name = BRUSH_NAME
		foliage.add_child(brush)
		brush.owner = root
	else:
		brush = b
	brush.update_size(_palette.brushSize.value)
	
	readd_element()
	_palette.set_visible(true)
	show_brush(true)
	block.update(foliage)
#	set_physics_process(true)

#切换工具时重新给面板赋值
func readd_element():
	var element_list:Array[Dictionary] = []
	var elements = foliage.get_elements()
	for scene in elements:
		var dic:Dictionary = Dictionary()
		dic["path"] = scene.resource_path
		var select:bool = false
		for s in _selected_elements:
			if s.get_meta("path") == scene.resource_path:
				select = true
				break
		dic["selected"] = select
		var layer = get_layer(scene.resource_path)
		var num:int = 0
		if layer:
			num = layer.get_child_count()
		dic["number"] = num
		element_list.append(dic)
	_palette.load_elements(element_list)

#显示刷子
func show_brush(value:bool):
	if brush:
		brush.visible = value

#根据地址获取layer name
func get_layer_name(path:String) -> String:
	var base_name = path.get_file().get_basename()
	var pash_hash:int = path.hash()
	var layer_name:String = "layer_%s_%d" % [base_name,pash_hash]
	return layer_name

#根据地址获取layer
func get_layer(path:String) -> Node3D:
	var layer_name:String = get_layer_name(path)
	var layer = foliage.get_node_or_null(layer_name)
	return layer

#计算该生成多少个点
func calculate_points() -> Array:
	var radius:float = brush.get_radius()
	var area:float = PI * pow(radius,2)
	var proportion:float = area / MAX_CALCULATE_AREA
	var datas:Array[Dictionary] = []
	var space_state =  get_viewport().world_3d.direct_space_state
	
	for element in _selected_elements:
		var property:ElementProperty = _palette.get_element_property(element.get_meta("path"))
		var min_distance:float = property.radius / 100.0
		var cur_density:int = int(round(property.density * proportion * 10.0))
		if cur_density == 0:
			continue
		var points:Array[Vector3] = FoliagePainterUtil.generatePointInCycle1(space_state,cur_density,brush.position,radius,min_distance)
		var dic:Dictionary = Dictionary()
		dic["element"] = element
		dic["points"] = points
		datas.append(dic)
	return datas
