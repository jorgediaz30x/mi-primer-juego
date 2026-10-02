class_name CaptureTool
extends RefCounted
## Screenshot helper for QA evidence. Only active when launched with user args:
##
##   godot --path . -- --capture=res://production/qa/evidence/shot.png --capture-at=5
##   godot --path . -- --capture=... --capture-cards     (forces a level-up card offer)
##   godot --path . -- --capture=... --capture-x=5100 --capture-god
##       (teleports the player to x and makes them invulnerable, to shoot a zone/boss)
##   ... --capture-skip   (marks every encounter as done, to reach the boss directly)
##   ... --capture-respawns=2  (restarts the run N times first, like pressing R)
##   ... --capture-level=2        (starts level N: 0 forest, 1 cave, 2 graveyard)
##   ... --capture-boss-ratio=0.2 (the boss spawns with that fraction of its hp)
##   ... --capture-title    (stays on the title screen — skips starting a run)
##   ... --capture-options  (opens Options, from the title)
##   ... --capture-controls (opens Controls, from the title)
##   ... --capture-pause    (starts a run, then opens the Esc pause menu)
##
## Saves the frame and quits. Does nothing in a normal run.


## Starts a capture if the command line asks for one.
static func maybe_run(host: Node, _level_up: LevelUpScreen) -> void:
	var path: String = ""
	var at: float = 4.0
	var show_cards: bool = false
	var lumos: bool = false
	var respawns: int = 0
	var level_index: int = -1
	var boss_ratio: float = -1.0
	var player_x: float = -1.0
	var god: bool = false
	var skip: bool = false
	var title: bool = false
	var options: bool = false
	var controls: bool = false
	var pause: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			path = arg.trim_prefix("--capture=")
		elif arg.begins_with("--capture-at="):
			at = float(arg.trim_prefix("--capture-at="))
		elif arg == "--capture-cards":
			show_cards = true
		elif arg == "--capture-lumos":
			lumos = true
		elif arg.begins_with("--capture-respawns="):
			respawns = int(arg.trim_prefix("--capture-respawns="))
		elif arg.begins_with("--capture-level="):
			level_index = int(arg.trim_prefix("--capture-level="))
		elif arg.begins_with("--capture-boss-ratio="):
			boss_ratio = float(arg.trim_prefix("--capture-boss-ratio="))
		elif arg.begins_with("--capture-x="):
			player_x = float(arg.trim_prefix("--capture-x="))
		elif arg == "--capture-god":
			god = true
		elif arg == "--capture-skip":
			skip = true
		elif arg == "--capture-title":
			title = true
		elif arg == "--capture-options":
			options = true
		elif arg == "--capture-controls":
			controls = true
		elif arg == "--capture-pause":
			pause = true
	if path.is_empty():
		return
	await host.get_tree().process_frame
	# Every capture except --capture-title skips the title screen, exactly as
	# before this screen existed: straight into a running level.
	if not title:
		host.call("_start_run")
	if level_index >= 0:
		host.call("debug_goto_level", level_index)
		await host.get_tree().process_frame
	for i in respawns:
		# Same path as pressing R after dying: rebuilds the level, keeps progression.
		host.call("_start_run")
		await host.get_tree().process_frame
	for child: Node in host.get_children():
		if child is Level:
			var level := child as Level
			level.player.debug_invulnerable = god
			level.debug_boss_hp_ratio = boss_ratio
			if skip:
				level.debug_skip_encounters()
			if player_x >= 0.0:
				level.debug_teleport(player_x)
			if lumos:
				level.player.debug_cast_lumos()
	if show_cards and host.has_method("debug_offer_cards"):
		host.call("debug_offer_cards")
	if options and host.has_method("debug_show_options"):
		host.call("debug_show_options")
	if controls and host.has_method("debug_show_controls"):
		host.call("debug_show_controls")
	if pause and host.has_method("debug_show_pause"):
		host.call("debug_show_pause")
	await host.get_tree().create_timer(at, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var image := host.get_viewport().get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(path))
	print("CaptureTool: saved %s (err=%d)" % [path, err])
	host.get_tree().quit()
