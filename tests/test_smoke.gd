extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed: PackedScene = load("res://scenes/main.tscn")
    if packed == null:
        push_error("Main scene did not load")
        quit(1)
        return
    var scene: Control = packed.instantiate() as Control
    if scene == null:
        push_error("Main scene is not a Control")
        quit(1)
        return
    root.add_child(scene)
    await process_frame
    var button: Button = scene.get_node_or_null("Center/Stack/TapButton") as Button
    if button == null:
        push_error("Tap button missing")
        quit(1)
        return
    var indicator: ColorRect = scene.get_node_or_null("Center/Stack/Indicator") as ColorRect
    if indicator == null or indicator.color != Color.RED:
        push_error("Acceptance indicator must start red")
        quit(1)
        return
    button.pressed.emit()
    if scene.tap_count != 1:
        push_error("Tap interaction failed")
        quit(1)
        return
    if indicator.color != Color(0.2, 0.75, 0.48):
        push_error("First tap did not change the indicator")
        quit(1)
        return
    button.pressed.emit()
    if scene.tap_count != 2 or indicator.color != Color.RED:
        push_error("Second tap did not restore red")
        quit(1)
        return
    print("SMOKE_TEST_PASSED")
    quit(0)
