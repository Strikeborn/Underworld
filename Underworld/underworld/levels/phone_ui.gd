extends Control
signal link_clicked(path: String)

func _on_play_button_pressed() -> void:
	emit_signal("link_clicked", "res://levels/2D.tscn")

func _on_back_button_pressed() -> void:
	emit_signal("link_clicked", "res://levels/Level2.tscn")
