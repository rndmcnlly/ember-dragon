## The Ember Trail: the order of the levels and how each one plays, written in the
## internal DSL from core/campaign.gd. Reorder, retune, or add a line here; the maps
## themselves are the .txt files next to this one.
extends RefCounted


static func ember_trail() -> Campaign:
	var trail := Campaign.new("The Ember Trail")
	trail.level("meadow").eat(5).without_pickups()
	trail.level("ford").eat(8).with_pickups([HastePowerup])
	trail.level("cinders").eat(10).with_pickups([HastePowerup, TrimPowerup])
	trail.level("confluence").eat(12).with_pickups([GhostPowerup, TrimPowerup])
	trail.level("caldera").eat(15).faster(1.15)
	return trail.then_any_other(Level.catalog())
