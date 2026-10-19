extends RefCounted

var friendly: bool
var max_hp: float
var hp: float

func _init(is_friendly: bool) -> void:
    friendly = is_friendly
    max_hp = 10.0 if friendly else 8.0
    hp = max_hp

func tick(delta: float) -> void:
    hp -= delta
    if hp <= 0.0:
        hp = max_hp

func hp_text() -> String:
    return "HP %.1f / %.1f" % [hp, max_hp]
