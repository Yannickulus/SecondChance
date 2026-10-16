extends Node

const MCM_HELPERS = "res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres"

var _lib = null
var _gameData = preload("res://Resources/GameData.tres")

# True only while Character.Death() runs
var _dying: bool = false
# True if this death happened in a permadeath zone
var _permadeathZone: bool = false
var _tokenUsed: bool = false
var _spawn_action := ""
const SPAWN_FALLBACK_KEY := KEY_F5

const TOKEN_ID := "Second_Chance_Token"  # == ItemData.file == registry key

var _interface = null

func _ready():
	if Engine.has_meta("RTVModLib"):
		_lib = Engine.get_meta("RTVModLib")
		_register_objects()
		if _lib._is_ready:
			_on_lib_ready()
		else:
			_lib.frameworks_ready.connect(_on_lib_ready)

func _register_objects():
	#var token: Resource = load("res://mods/SecondChance/Second_Chance_Token.tres")  # an ItemData .tres
	var result: Dictionary = _lib.register_item({
		TOKEN_ID: {
			"item_path":   "res://SecondChance/Second_Chance_Token.tres",
			"loot_tables": ["LT_Master"],
		},
	})

func _on_lib_ready():
	_lib.hook("character-death-pre", _on_death_pre, 0)# Ensure this triggers before other pre-death events, other mods (ie. RecoverableRemains) can work off of what this mod sets on death
	_lib.hook("character-death-post", _on_death_post, 100)
	_setup_mcm()
	print("Second Chance: Loaded")

func _setup_mcm():
	if !ResourceLoader.exists(MCM_HELPERS):
		print("Secondchance: MCM not installed, using defaults")
		return
	var script = load("res://SecondChance/ModConfig.gd")
	if script == null:
		push_warning("Second Chance: ModConfig.gd could not be loaded")
	var node = Node.new()
	node.set_script(script)
	add_child(node)
	node.Setup(self)
	_spawn_action = script.SPAWN_ACTION

func _input(event: InputEvent) -> void:
	if _spawn_action != "" and InputMap.has_action(_spawn_action):
		# MCM registered the action: honor whatever key the player set
		if event.is_action_pressed(_spawn_action) and not event.is_echo():
			_spawn_token()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == SPAWN_FALLBACK_KEY:
		# No MCM action available: plain F5
		_spawn_token()

func _spawn_token() -> void:
	var ui = _get_interface()   # the find_child helper from earlier
	if ui == null:
		print("Second Chance: no Interface (not in a map?)")
		return

	var lib = Engine.get_meta("RTVModLib")
	var token_data = lib.get_entry(lib.Registry.ITEMS, TOKEN_ID)
	if token_data == null:
		push_warning("Second Chance: token item is not registered")
		return

	var grid = ui.inventoryGrid
	print("Second Chance: interface=", ui.get_path(), " grid=", grid.get_path(),
			" grid size=", grid.gridWidth, "x", grid.gridHeight,
			" items before=", grid.items.size())
	print("Second Chance: token file=", token_data.file, " size=", token_data.size)

	var slot = SlotData.new()
	slot.itemData = token_data

	var placed = ui.Create(slot, grid, false)
	print("Second Chance: Create returned ", placed, ", items now=", grid.items.size())
	
func _on_death_pre():
	_dying = true
	_permadeathZone = false
	_tokenUsed = false
	if _gameData.tutorial:
		return
	
	if not _gameData.permadeath:
		return;

	_permadeathZone = true
	print("Second Chance: death in PERMADEATH mode (difficulty " + str(_gameData.difficulty) + ")")
	if consume_token():
		_tokenUsed = true
		_gameData.permadeath = false   # Death() takes the normal path
		print("Second Chance: token consumed, permadeath blocked")
	else:
		print("Second Chance: no token, permadeath proceeds")

func _on_death_post():
	_dying = false
	_permadeathZone = false
	_tokenUsed = false

func _get_interface():
	if is_instance_valid(_interface):
		return _interface
	# Path derived from Interface.gd's own node references
	var direct = get_node_or_null("/root/Map/Core/UI/Interface")
	if direct != null and "inventoryGrid" in direct:
		_interface = direct
		return _interface

	# Fallback: several nodes are named "Interface", so only accept one
	# that really has an inventoryGrid
	for candidate in get_tree().root.find_children("Interface", "", true, false):
		if "inventoryGrid" in candidate:
			_interface = candidate
			return _interface

	return null

func consume_token() -> bool:
	var ui = _get_interface()
	if ui == null:
		print("Second Chance: Interface not found")
		return false
	var grid = ui.inventoryGrid
	for item in grid.items.duplicate():   # copy: Pick() modifies the array
		if not is_instance_valid(item) or item.slotData == null:
			continue
		var data = item.slotData.itemData
		if data == null or data.file != TOKEN_ID:
			continue
		if item.slotData.amount > 1:
			item.slotData.amount -= 1
			item.UpdateDetails()
			return true
		if grid.Pick(item) == null:
			continue
		grid.remove_child(item)   # Pick() leaves the node in the tree
		item.queue_free()
		return true
	return false