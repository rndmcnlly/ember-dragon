## The Ember Trail: the order of the levels and how each one plays, written in the
## internal DSL from core/campaign.gd. Reorder, retune, or add a line here. The maps
## are the .txt files next to this one; their events are the .rules files.
extends RefCounted


static func ember_trail() -> Campaign:
	var trail := Campaign.new("The Ember Trail")
	trail.level("meadow").eat(5).without_pickups().with_rules("tutorial")
	trail.level("ford").eat(8).with_pickups([HastePowerup]).with_rules("current")
	trail.level("cinders").eat(10).without_pickups().with_rules("aftershocks")
	trail.level("confluence").eat(12).with_pickups([GhostPowerup]).with_rival().with_rules("steam")
	trail.level("caldera").eat(15).faster(1.15).with_rules("eruption")
	return trail.then_any_other(Level.catalog())
