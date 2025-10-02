extends Control
signal link_clicked(path: String)

func _ready() -> void:
	var r := $RichTextLabel
	r.meta_clicked.connect(_on_meta_clicked)

func _on_meta_clicked(meta: Variant) -> void:
	if typeof(meta) == TYPE_STRING:
		emit_signal("link_clicked", String(meta))

func _on_play_button_pressed() -> void:
	emit_signal("link_clicked", "res://levels/2D.tscn")

func _on_back_button_pressed() -> void:
	emit_signal("link_clicked", "res://levels/Level2.tscn")
