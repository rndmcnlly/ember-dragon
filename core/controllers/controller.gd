## Who steers a dragon (Strategy). The Session asks each dragon's controller once per
## tick, just before it moves; the controller may queue turns with Dragon.turn(), and
## the rules then treat every dragon the same way. This base class never turns, so its
## dragon flies straight: the keyboard (PlayerController) and the rival's AI
## (GreedyController) are the two that do something.
class_name Controller
extends RefCounted


func steer(_session: Session, _dragon: Dragon) -> void:
	pass
