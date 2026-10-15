extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed: PackedScene = load("res://scenes/main.tscn")
    if packed == null:
        push_error("Main scene did not load")
        quit(1)
        return
    var scene: Control = packed.instantiate()
    root.add_child(scene)
    await process_frame
    var button: Button = scene.get_node("Center/Stack/TapButton")
    if button == null:
        push_error("Tap button missing")
        quit(1)
        return
    button.pressed.emit()
    if scene.tap_count != 1:
        push_error("Tap interaction failed")
        quit(1)
        return
    print("SMOKE_TEST_PASSED")
    quit(0)
