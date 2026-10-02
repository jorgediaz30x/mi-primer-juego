class_name Hud
extends CanvasLayer
## In-run HUD, built from the generated UI art (panels, bar frame, icons) and the
## pixel font. Display only: it reads state and listens to signals, never changes it.
##
## Layout (1280x720): level/XP panel top-left, score + combo top-centre, zone
## top-right, spell slots bottom-left, boss bar bottom-centre, overlays centred.

const SPELLS := [
	{"icon": "spell_bolt", "key": "Clic", "ready": "bolt_ready"},
	{"icon": "spell_levitate", "key": "Clic der.", "ready": "levitate_ready"},
	{"icon": "nova", "key": "E", "ready": "nova_ready"},
	{"icon": "lumos", "key": "F", "ready": "lumos_ready"},
	{"icon": "move_dash", "key": "Shift", "ready": "dash_ready"},
]
const SLOT := Vector2(84, 84)
const OWNED_ICON := 40.0

var _config: GameConfig
var _deck: UpgradeDeck
var _experience: Experience
var _level: Level
var _best_score: int = 0

var _level_label: Label
var _xp_bar: HudBar
var _hearts_row: HBoxContainer
var _owned_row: HBoxContainer
var _slot_icons: Array[TextureRect] = []
var _score_label: Label
var _combo_label: Label
var _zone_label: Label
var _announce_label: Label
var _level_up_label: Label
var _banner_label: Label
var _slot_overlays: Array[ColorRect] = []
var _boss_box: Control
var _boss_label: Label
var _boss_bar: HudBar
var _overlay: Control
var _overlay_title: Label
var _overlay_stats: Label
var _overlay_hint: Label
var _grader: ScoreGrader
var _announce_tween: Tween
var _run_xp: int = 0
var _best_chain: int = 0


## Injects config. Call before adding to the tree; runs are bound with [method bind_run].
func setup(cfg: GameConfig) -> void:
	_config = cfg
	_grader = ScoreGrader.new(cfg.get_array("scoring.grades"))


func _ready() -> void:
	layer = 5
	_build_level_panel()
	_build_top()
	_build_spell_slots()
	_build_boss_bar()
	_build_overlay()


# --- Building --------------------------------------------------------------

func _build_level_panel() -> void:
	var box := UiStyle.panel(_config, Vector2(420, 114))
	box.position = Vector2(14, 12)
	add_child(box)
	_level_label = UiStyle.label(_config, "", "big", "accent")
	_level_label.position = Vector2(34, 18)
	add_child(_level_label)
	_xp_bar = HudBar.new()
	_xp_bar.setup(_config, Vector2(270, 30), "ui.xp_fill")
	_xp_bar.position = Vector2(142, 30)
	add_child(_xp_bar)
	_hearts_row = HBoxContainer.new()
	_hearts_row.position = Vector2(34, 70)
	_hearts_row.add_theme_constant_override("separation", 4)
	_hearts_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hearts_row)
	_owned_row = HBoxContainer.new()
	_owned_row.position = Vector2(16, 134)
	_owned_row.add_theme_constant_override("separation", 4)
	_owned_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_owned_row)


func _build_top() -> void:
	_score_label = _centered(UiStyle.label(_config, "", "big"), Vector2(440, 10), Vector2(400, 50))
	_combo_label = _centered(UiStyle.label(_config, "", "normal", "accent"), Vector2(440, 60), Vector2(400, 36))
	_zone_label = UiStyle.label(_config, "", "normal")
	_zone_label.position = Vector2(820, 20)
	_zone_label.size = Vector2(440, 36)
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_zone_label)
	_announce_label = _centered(UiStyle.label(_config, "", "normal"), Vector2(140, 230), Vector2(1000, 90))
	_announce_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_level_up_label = _centered(UiStyle.label(_config, "", "big", "accent"), Vector2(140, 150), Vector2(1000, 60))
	_level_up_label.modulate.a = 0.0
	_banner_label = _centered(UiStyle.label(_config, "", "huge", "danger"), Vector2(40, 200), Vector2(1200, 220))
	_banner_label.modulate.a = 0.0


func _build_spell_slots() -> void:
	var slot := SLOT
	for i in SPELLS.size():
		var origin := Vector2(18 + i * (slot.x + 12), 606)
		var box := UiStyle.panel(_config, slot)
		box.position = origin
		add_child(box)
		var texture := UiStyle.icon(_config, UiStyle.icon_index(_config, SPELLS[i]["icon"]))
		if texture:
			var icon := TextureRect.new()
			icon.texture = texture
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.position = origin + Vector2(12, 12)
			icon.size = slot - Vector2(24, 24)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(icon)
			_slot_icons.append(icon)
		else:
			_slot_icons.append(null)
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.6)
		shade.position = origin + Vector2(10, 10)
		shade.size = Vector2(slot.x - 20, 0)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)
		_slot_overlays.append(shade)
		var key := UiStyle.label(_config, str(SPELLS[i]["key"]), "small")
		key.position = origin + Vector2(0, slot.y - 4)
		key.size = Vector2(slot.x, 24)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(key)


func _build_boss_bar() -> void:
	_boss_box = Control.new()
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_box)
	_boss_label = UiStyle.label(_config, "", "normal", "danger")
	# Right of the spell slots (they end at x ~490), so nothing overlaps.
	_boss_label.position = Vector2(520, 626)
	_boss_label.size = Vector2(720, 32)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_label)
	_boss_bar = HudBar.new()
	_boss_bar.setup(_config, Vector2(720, 36), "ui.danger")
	_boss_bar.position = Vector2(520, 660)
	_boss_box.add_child(_boss_bar)
	_boss_box.hide()


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(UiStyle.dim(0.55))
	var box := UiStyle.panel(_config, Vector2(900, 300))
	box.position = Vector2(190, 200)
	_overlay.add_child(box)
	_overlay_title = UiStyle.label(_config, "", "huge", "danger")
	_overlay_title.position = Vector2(190, 222)
	_overlay_title.size = Vector2(900, 90)
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay.add_child(_overlay_title)
	_overlay_stats = UiStyle.label(_config, "", "normal")
	_overlay_stats.position = Vector2(190, 330)
	_overlay_stats.size = Vector2(900, 40)
	_overlay_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay.add_child(_overlay_stats)
	_overlay_hint = UiStyle.label(_config, "", "normal", "accent")
	_overlay_hint.position = Vector2(190, 410)
	_overlay_hint.size = Vector2(900, 40)
	_overlay_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay.add_child(_overlay_hint)
	add_child(_overlay)
	_overlay.hide()


func _centered(l: Label, at: Vector2, box: Vector2) -> Label:
	l.position = at
	l.size = box
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	return l


# --- Run binding -----------------------------------------------------------

## Binds the HUD to a fresh run: its level, its deck and its experience.
func bind_run(level: Level, deck: UpgradeDeck, experience: Experience, best_score: int) -> void:
	_level = level
	_deck = deck
	_experience = experience
	_best_score = best_score
	# Deck and experience outlive a respawn: connect once, not once per run.
	if not deck.changed.is_connected(_refresh_owned):
		deck.changed.connect(_refresh_owned)
	if not experience.leveled_up.is_connected(_on_leveled_up):
		experience.leveled_up.connect(_on_leveled_up)
	level.player.hearts_changed.connect(_refresh_hearts)
	_refresh_hearts(level.player.hearts(), level.player.max_hearts())
	_refresh_owned()
	_refresh_progress()
	_run_xp = 0
	_best_chain = 0
	_overlay.hide()
	_boss_box.hide()
	_combo_label.text = ""
	_score_label.text = _config.get_text("names.ui_score") % 0
	_zone_label.text = level.title()
	level.wave_started.connect(_on_wave_started)
	level.banner.connect(_on_banner)
	level.enemy_killed.connect(_on_enemy_killed)
	level.announce.connect(show_announcement)
	level.boss_started.connect(_on_boss_started)
	level.boss_health_changed.connect(_on_boss_health)


## Flashes a line in the middle of the screen.
func show_announcement(text: String) -> void:
	_announce_label.text = text
	_announce_label.modulate.a = 1.0
	if _announce_tween:
		_announce_tween.kill()
	_announce_tween = create_tween()
	_announce_tween.tween_interval(1.8)
	_announce_tween.tween_property(_announce_label, "modulate:a", 0.0, 0.5)


## Title card / knockout: huge text that punches in and fades (Cuphead-style).
func show_banner(text: String) -> void:
	# A title card owns the centre of the screen: clear the smaller line.
	if _announce_tween:
		_announce_tween.kill()
	_announce_label.modulate.a = 0.0
	_banner_label.text = text
	_banner_label.modulate.a = 1.0
	_banner_label.pivot_offset = _banner_label.size * 0.5
	_banner_label.scale = Vector2(2.2, 2.2)
	var tween := create_tween()
	tween.tween_property(_banner_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(_config.get_float("ui.banner_time", 1.6))
	tween.tween_property(_banner_label, "modulate:a", 0.0, 0.5)


func _on_banner(text: String, big: bool) -> void:
	if big:
		show_banner(text)
	else:
		show_announcement(text)


## Big "level up" call-out.
func show_level_up(new_level: int) -> void:
	_level_up_label.text = _config.get_text("names.ui_level_up") % new_level
	_level_up_label.modulate.a = 1.0
	_level_up_label.pivot_offset = _level_up_label.size * 0.5
	_level_up_label.scale = Vector2(1.6, 1.6)
	var tween := create_tween()
	tween.tween_property(_level_up_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	tween.tween_interval(1.4)
	tween.tween_property(_level_up_label, "modulate:a", 0.0, 0.5)


## Shows the "caught" overlay.
func show_death() -> void:
	_show_overlay(_config.get_text("names.death_title"), _config.get_text("names.death_hint"), "ui.danger")


## Shows the "level completed" overlay.
func show_victory() -> void:
	_show_overlay(_config.get_text("names.victory_title"), _config.get_text("names.victory_hint"), "ui.accent")


func _show_overlay(title: String, hint: String, color_key: String) -> void:
	var points: int = _level.score if _level and is_instance_valid(_level) else 0
	_overlay_title.text = "%s  %s" % [title, _grader.grade_for(points)]
	_overlay_title.add_theme_color_override("font_color", _config.get_color(color_key))
	_overlay_stats.text = "%s   ·   %s" % [
		_config.get_text("names.ui_run_stats") % [points, _run_xp, _best_chain],
		_config.get_text("names.ui_best") % maxi(points, _best_score)]
	_overlay_hint.text = hint
	_overlay.show()


# --- Per frame / signals -----------------------------------------------------

func _process(_delta: float) -> void:
	if _level == null or not is_instance_valid(_level) or _level.player == null:
		return
	var combo := _level.get_combo()
	if combo and combo.count >= 2:
		_combo_label.text = "x%.2f  COMBO %d" % [combo.multiplier(), combo.count]
		_combo_label.modulate.a = 0.4 + 0.6 * combo.time_left_ratio()
	else:
		_combo_label.text = ""
	var player := _level.player
	for i in _slot_overlays.size():
		var ready: float = float(player.call(str(SPELLS[i]["ready"])))
		_slot_overlays[i].size.y = (SLOT.y - 20.0) * (1.0 - ready)
		if _slot_icons[i] and SPELLS[i]["icon"] == "nova":
			# Locked until the Nova card is taken.
			_slot_icons[i].modulate = Color.WHITE if player.nova_unlocked() else Color(0.25, 0.25, 0.3)
		if _slot_icons[i] and SPELLS[i]["icon"] == "lumos":
			# Only usable in dark zones.
			_slot_icons[i].modulate = Color.WHITE if player.lumos_allowed else Color(0.25, 0.25, 0.3)


func _on_wave_started(index: int, total: int, title: String) -> void:
	_zone_label.text = _config.get_text("names.ui_encounter") % [index + 1, total, title]
	show_announcement(title)


func _on_enemy_killed(xp: int, _multiplier: float, chain: int, _points: int) -> void:
	_run_xp += xp
	_best_chain = maxi(_best_chain, chain)
	_score_label.text = _config.get_text("names.ui_score") % _level.score
	_refresh_progress()


## Short call-out when a card is taken.
func show_card_taken(id: String) -> void:
	show_announcement(str(_deck.get_def(id).get("name", id)))


func _on_boss_started(boss_name: String, _max_hp: int) -> void:
	_boss_label.text = boss_name
	_boss_bar.set_ratio(1.0)
	_zone_label.text = _config.get_text("names.ui_boss_stage")
	_boss_box.show()


func _on_boss_health(hp: int, max_hp: int) -> void:
	_boss_bar.set_ratio(float(hp) / float(maxi(1, max_hp)))


func _refresh_progress() -> void:
	if _experience == null:
		return
	_level_label.text = _config.get_text("names.ui_level") % _experience.level
	_xp_bar.set_ratio(_experience.progress())


func _refresh_hearts(current: int, maximum: int) -> void:
	for child in _hearts_row.get_children():
		child.queue_free()
	var texture := UiStyle.icon(_config, UiStyle.icon_index(_config, "heart"))
	for i in maximum:
		var heart := TextureRect.new()
		heart.texture = texture
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heart.custom_minimum_size = Vector2(40, 40)
		heart.modulate = Color.WHITE if i < current else Color(0.2, 0.2, 0.25, 0.8)
		heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hearts_row.add_child(heart)


func _refresh_owned() -> void:
	for child in _owned_row.get_children():
		child.queue_free()
	if _deck == null:
		return
	for id in _deck.owned():
		var def := _deck.get_def(id)
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(OWNED_ICON, OWNED_ICON)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.texture = UiStyle.icon(_config, UiStyle.icon_index(_config, str(def.get("icon", id))))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(OWNED_ICON, OWNED_ICON)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(icon)
		var stacks: int = _deck.stacks_of(id)
		if stacks > 1:
			var count := UiStyle.label(_config, "x%d" % stacks, "small", "accent")
			count.position = Vector2(OWNED_ICON - 26, OWNED_ICON - 22)
			holder.add_child(count)
		_owned_row.add_child(holder)


func _on_leveled_up(_new_level: int) -> void:
	_refresh_progress()
