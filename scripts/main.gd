extends Control

@onready var status: Label = $Center/Stack/Status
@onready var tap_button: Button = $Center/Stack/TapButton
@onready var indicator: ColorRect = $Center/Stack/Indicator

var tap_count: int = 0

func _ready() -> void:
    tap_button.pressed.connect(_on_tap)

func _on_tap() -> void:
    tap_count += 1
    status.text = "Taps: %d | Web build is interactive" % tap_count
    indicator.color = Color(0.2, 0.75, 0.48) if tap_count % 2 == 1 else Color(0.18, 0.45, 0.8)
