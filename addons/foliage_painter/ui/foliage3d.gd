@tool
extends Node3D

signal show_block(bool)

@export var _checkBox:bool = false:
	set(value):
		_checkBox = value
		emit_signal("show_block",value)
@export var _scenes:Array[PackedScene] = []

func _ready():
	_remove_dangling_patterns()

func _remove_dangling_patterns():
	# Remove null scenes in case they failed to load for some reason
	var changed = false
	var i = 0
	while i < len(_scenes):
		if _scenes[i] == null:
			printerr(get_path(), ": Scene ", i, " failed to load")
			_scenes.remove_at(i)
			changed = true
		else:
			i += 1
	if changed:
		notify_property_list_changed()

func get_elements():
	return _scenes

func add_element(path):
	_scenes.append(load(path))
	notify_property_list_changed()

func remove_element(path):
	for i in len(_scenes):
		if _scenes[i].resource_path == path:
			_scenes.remove_at(i)
			notify_property_list_changed()
			break


func has_element(path):
	for scene in _scenes:
		if scene.resource_path == path:
			return true
	return false
	
func get_show_block() -> bool:
	return _checkBox
