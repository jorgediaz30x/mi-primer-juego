extends "res://tests/test_case.gd"
## UpgradeDeck: offers, eligibility, stacking, requirements and modifiers.

const POOL := [
	{"id": "fast", "max_stacks": 2, "effects": {"bolt.cooldown": -0.1}},
	{"id": "fan", "max_stacks": 1, "effects": {"bolt.shots": 2}},
	{"id": "boom", "max_stacks": 1, "effects": {"levitate.explode": 1}},
	{"id": "big_boom", "max_stacks": 1, "requires": "boom", "effects": {"levitate.radius": 1}},
]


func _rng(seed_value: int = 7) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_offer_returns_distinct_ids() -> void:
	var deck := UpgradeDeck.new(POOL)
	var offer := deck.offer(_rng(), 3)
	assert_eq(offer.size(), 3)
	var seen := {}
	for id in offer:
		assert_false(seen.has(id), "duplicate %s" % id)
		seen[id] = true


func test_offer_never_includes_card_with_missing_requirement() -> void:
	var deck := UpgradeDeck.new(POOL)
	for s in 20:
		assert_false("big_boom" in deck.offer(_rng(s), 3), "seed %d offered big_boom" % s)


func test_requirement_unlocks_card() -> void:
	var deck := UpgradeDeck.new(POOL)
	deck.take("boom")
	assert_true(deck.is_eligible("big_boom"))


func test_same_seed_gives_same_offer() -> void:
	var deck := UpgradeDeck.new(POOL)
	assert_eq(deck.offer(_rng(3), 3), deck.offer(_rng(3), 3))


func test_offer_shrinks_when_pool_runs_out() -> void:
	var deck := UpgradeDeck.new(POOL)
	deck.take("fan")
	deck.take("boom")
	deck.take("big_boom")
	deck.take("fast")
	deck.take("fast")
	assert_eq(deck.offer(_rng(), 3).size(), 0)


func test_stacks_multiply_effects() -> void:
	var deck := UpgradeDeck.new(POOL)
	deck.take("fast")
	deck.take("fast")
	assert_near(deck.get_modifier("bolt.cooldown"), -0.2)


func test_take_past_max_stacks_is_refused() -> void:
	var deck := UpgradeDeck.new(POOL)
	assert_true(deck.take("fan"))
	assert_false(deck.take("fan"))
	assert_eq(deck.stacks_of("fan"), 1)


func test_owned_lists_taken_cards_in_pool_order() -> void:
	var deck := UpgradeDeck.new(POOL)
	deck.take("boom")
	deck.take("fast")
	assert_eq(deck.owned(), ["fast", "boom"])


func test_config_pool_is_well_formed() -> void:
	var config := GameConfig.load_from("res://assets/data/game_config.json")
	var pool := config.get_array("upgrades.pool")
	assert_true(pool.size() >= 6, "enough cards for several level-ups")
	var ids := {}
	for def: Variant in pool:
		ids[str((def as Dictionary).get("id"))] = true
	for def: Variant in pool:
		var req: String = str((def as Dictionary).get("requires", ""))
		assert_true(req.is_empty() or ids.has(req), "requirement %s exists" % req)
		assert_true(((def as Dictionary).get("effects", {}) as Dictionary).size() > 0, "card has effects")


func test_flag_gated_card_waits_for_flag() -> void:
	var deck := UpgradeDeck.new([{"id": "light", "requires_flag": "entered_dark", "effects": {"lumos.radius_mult": 0.4}}])
	assert_false(deck.is_eligible("light"))
	deck.set_flag("entered_dark")
	assert_true(deck.is_eligible("light"))


func test_state_round_trip_keeps_stacks_and_flags() -> void:
	var deck := UpgradeDeck.new(POOL)
	deck.take("fast")
	deck.take("fast")
	deck.set_flag("entered_dark")
	var restored := UpgradeDeck.new(POOL)
	restored.load_state(deck.to_state())
	assert_eq(restored.stacks_of("fast"), 2)
	assert_true(restored.has_flag("entered_dark"))


func test_load_state_clamps_stacks_and_drops_unknown() -> void:
	var deck := UpgradeDeck.new(POOL)
	deck.load_state({"stacks": {"fan": 9, "ghost": 3}, "flags": []})
	assert_eq(deck.stacks_of("fan"), 1)
	assert_eq(deck.stacks_of("ghost"), 0)


func test_deck_is_full_at_owned_limit() -> void:
	var deck := UpgradeDeck.new(POOL, 2)
	deck.take("fast")
	assert_false(deck.is_full())
	deck.take("fan")
	assert_true(deck.is_full())


func test_remove_frees_a_slot() -> void:
	var deck := UpgradeDeck.new(POOL, 2)
	deck.take("fast")
	deck.take("fast")
	assert_true(deck.remove("fast"))
	assert_eq(deck.stacks_of("fast"), 1)
	assert_false(deck.is_full())
	assert_false(deck.remove("fan"), "cannot remove what is not owned")


func test_featured_cards_come_first_in_the_offer() -> void:
	var deck := UpgradeDeck.new(POOL + [{"id": "light", "requires_flag": "entered_dark", "effects": {"lumos.radius_mult": 0.4}}])
	deck.set_flag("entered_dark")
	var featured := deck.cards_unlocked_by("entered_dark")
	assert_eq(featured, ["light"])
	for s in 10:
		assert_eq(deck.offer(_rng(s), 3, featured)[0], "light", "seed %d" % s)


func test_old_save_over_the_limit_is_trimmed() -> void:
	var deck := UpgradeDeck.new(POOL, 2)
	deck.load_state({"stacks": {"fast": 2, "fan": 1, "boom": 1}, "flags": []})
	assert_eq(deck.total_owned(), 2)


func test_oldest_is_the_first_card_taken() -> void:
	var deck := UpgradeDeck.new(POOL, 3)
	deck.take("fan")
	deck.take("fast")
	deck.take("boom")
	assert_eq(deck.oldest(), "fan")


func test_replace_drops_the_oldest_not_a_chosen_one() -> void:
	var deck := UpgradeDeck.new(POOL, 2)
	deck.take("fan")
	deck.take("boom")
	assert_true(deck.replace_oldest_with("fast"))
	assert_eq(deck.stacks_of("fan"), 0, "fan was the oldest")
	assert_eq(deck.stacks_of("boom"), 1)
	assert_eq(deck.oldest(), "boom", "boom is now the oldest")


func test_replace_with_ineligible_card_changes_nothing() -> void:
	# big_boom requires boom, which is not owned: still ineligible after the drop.
	var deck := UpgradeDeck.new(POOL, 1)
	deck.take("fan")
	assert_false(deck.replace_oldest_with("big_boom"))
	assert_eq(deck.stacks_of("fan"), 1, "the dropped card is restored")
	assert_eq(deck.oldest(), "fan")


func test_history_survives_save_round_trip() -> void:
	var deck := UpgradeDeck.new(POOL, 4)
	deck.take("boom")
	deck.take("fast")
	var restored := UpgradeDeck.new(POOL, 4)
	restored.load_state(deck.to_state())
	assert_eq(restored.oldest(), "boom")

