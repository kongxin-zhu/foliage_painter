extends RefCounted
class_name Block

#顶层分块大小
var _size:int = 8.0
#
var _max_items:int = 40
#四叉树深度
var _depth:int = 2
#节点字典
var _nodes:Dictionary
var searching:bool = false
var _searcher:BlockSearcher

func _init(size := 8.0, max_items := 40,depth := 2):
	_nodes = Dictionary()
	_size = size
	_depth = depth

func instantiate_searcher(thread_queue: ThreadQueue) -> BlockSearcher:
	_searcher = BlockSearcher.new(thread_queue)
	return _searcher

#添加到节点里
func add_element(element:Node3D):
	var _key:String = _get_key(element.position)
	if not _nodes.has(_key):
		var num:Vector2 = _get_block_num(element.position)
		_nodes[_key] = BlockNode.new(null,num,_size,_max_items,_depth)
	_nodes[_key].add_element(element)
#	print("nodes数量: ",_nodes.size())
#	for key in _nodes.keys():
#		print("key: ",key)
	
#func remove_element(element:Node3D):
#	pass
	
#搜索
#is_remove is false only do search,is_remove is true do search and remove
func search(position:Vector3,radius:float,path_list:Array[String],is_remove:bool = false) -> Array:
	if searching == true:
		print("上一次还没搜索完")
		return []
		
	searching = true
	var selected_block = _get_all_cover_block(position,radius)
#	print("刷过的图块：",selected_block)
	var selected_elements:Array = []
	for node in selected_block:
		var results:Array = node.get_all_cover_element(position,radius,path_list,is_remove)
		selected_elements.append_array(results)
	if is_remove:
		erase_empty_block()
	searching = false
	return selected_elements
	

	
func update(root_node:Node3D):
	clear()
	pass
	for child in root_node.get_children():
		for element in child.get_children():
			add_element(element)
			
	
	
func clear():
	_nodes.clear()

#获取块编号 
func _get_block_num(position:Vector3) -> Vector2:
	var x = int(floor(position.x / _size))
	var z = int(floor(position.z / _size))
	return Vector2(x,z)

#根据坐标获得顶层key
func _get_key(position:Vector3) -> String:
	var temp:String = "block_%d_%d"
	var num:Vector2 = _get_block_num(position)
	var key:String = temp % [num.x,num.y]
	return key

#根据块编号获取顶层key
func _get_node_by_num(num:Vector2) -> String:
	var temp:String = "block_%d_%d"
	var key:String = temp % [num.x,num.y]
	return key

#获得所有和刷子有交集的分块
func _get_all_cover_block(position:Vector3,radius:float) -> Array:
	#先计算可能会覆盖多少个分块
	var selected_blocks:Array[BlockNode] = []
	#刷子-X-Z方向的坐标
	var left_top_postion:Vector3 = Vector3(position.x - radius,0.0,position.z - radius)
	#刷子+X+Z方向的坐标
	var right_bottom_postion:Vector3 = Vector3(position.x + radius,0.0,position.z + radius)
	#左上角的块num
	var left_top_num:Vector2 = _get_block_num(left_top_postion)
	#右下解的块num
	var right_bottom_num:Vector2 = _get_block_num(right_bottom_postion)
	#取这个块右下角的坐标
	right_bottom_num += Vector2(1,1)
	
#	print("left_top_num: ",left_top_num)
#	print("left_top_postion: ",left_top_postion)
#	print("right_bottom_num: ",right_bottom_num)
#	print("right_bottom_postion ",right_bottom_postion)
	
	if left_top_num == right_bottom_num:
#		print("刷子在一个格子之内")
		var node = get_cover_node(position,radius,left_top_num)
#		print("node: ",node)
		if node:
			selected_blocks.append(node)
	else:
		for x in range(left_top_num.x,right_bottom_num.x):
			for y in range(left_top_num.y,right_bottom_num.y):
#				print("x: ",x," y: ",y)
				var node = get_cover_node(position,radius,Vector2(x,y))
				if node:
					selected_blocks.append(node)
#				var key:String = _get_node_by_num(Vector2(x,y))
#				if _nodes.has(key):
#					var node = _nodes[key]
#					var is_cover:bool = node.check_node_cover(position,radius)
#					if is_cover:
#						selected_blocks.append(node)
		

	return selected_blocks
	
func get_cover_node(position:Vector3,radius:float,num:Vector2) -> BlockNode:
	var key:String = _get_node_by_num(num)
#	print("key: ",key)
	if _nodes.has(key):
#		print("有这个节点")
		var node:BlockNode = _nodes[key]
		var is_cover:bool = node.check_node_cover(position,radius)
		if is_cover:
			return node
	return null

#清空所有没有数据的block node
func erase_empty_block():
	for key in _nodes:
		var block:BlockNode = _nodes[key]
		var is_empty:bool = block.is_empty()
		if is_empty:
			_nodes.erase(key)
#打印所有的节点
func print_all_block():
	print("打印所有节点和数据")
	for key in _nodes:
		_nodes[key].print_elements()
