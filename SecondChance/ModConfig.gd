extends Node

var McmHelpers = load("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres")

const MOD_ID := "SecondChance"
const FRIENDLY_NAME := "Second Chance"
const DESCRIPTION := "Token that blocks permadeath once."
const SPAWN_ACTION := "SecondChance_SpawnToken"   # MCM uses this as the InputMap action name

func _ready():
    if McmHelpers == null:
        push_warning("Second Chance: Mod Configuration Menu not found")
        return

    var _mcmConfig = MCM_Config.new(
        MOD_ID,                     # The mods unique ID
        FRIENDLY_NAME,              # The mods name that will be displayed within the MCM
        DESCRIPTION,                # A short description of the mod
        UpdateConfig,               # The callback function that will handle all value updates for your mod
        self                        # The object to call for individual value `on_value_changed` callbacks
    )
        
    _mcmConfig.CreateKeycodeValue(
            SPAWN_ACTION,
            "[DEV] Spawn token key",
            "Debug key: spawns a Second Chance token in your inventory",
            KEY_F5, 
            MCM_Config.MCM_Key_Types.KEY
        ) \
        .setMenuPos(1)
    
    _mcmConfig.RegisterMod()

# Called by MCM whenever the player changes and saves values
func UpdateConfig(config: ConfigFile):
    pass