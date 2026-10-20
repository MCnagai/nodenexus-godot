extends RefCounted

var friendly: bool
var max_hp: float
var hp: float
var blocks: Array[String] = []
var elapsed := 0.0
var next_block := 0
var last_block := -1

func _init(is_friendly: bool) -> void:
    friendly = is_friendly
    max_hp = 10.0 if friendly else 8.0
    hp = max_hp

func reset_program() -> void:
    elapsed = 0.0
    next_block = 0
    last_block = -1

func take_damage(amount: float) -> bool:
    hp -= amount
    if hp <= 0.0:
        hp = max_hp
        return true
    return false

func heal(amount: float) -> void:
    hp = minf(max_hp, hp + amount)

func hp_text() -> String:
    return "HP %.1f / %.1f" % [hp, max_hp]
