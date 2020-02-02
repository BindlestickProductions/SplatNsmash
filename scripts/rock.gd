extends RigidBody

var touched_by
var held_by
var net_priority

func _ready():
	set_physics_process(true)

func set_net_priority(priority):
	net_priority=priority

func set_touched_by(entity_name):
	touched_by=entity_name
	
func set_held_by(entity_name):
	held_by=entity_name

# Sent to everyone else
puppet func do_explosion():
	get_node("anim").play("explode")

# Received by owner of the rock
master func exploded(by_who):
	rpc("do_explosion") # Re-sent to slave rocks
	get_node("../../score").rpc("increase_score", by_who)
	do_explosion()

var netTicks = 5
var netCounter = 0

#remote func update_rock(name, transform, velocity, velocity_angular):

puppet func update_client_rock(rock_name,rock_transform,rock_velocity,rock_angular):
	if(rock_name == name):
		transform = rock_transform
		linear_velocity = rock_velocity
		angular_velocity = rock_angular
		

func _physics_process(delta):
		if (get_tree().is_network_server()):
			netCounter+=1
			if(netCounter > netTicks):
				netCounter = 0
			#if(game_started):
				#var rocks = get_tree().get_root().get_node("level_3d").get_node("rocks")
				#for r in rocks.get_children():
			#var pos= Quat(get_transform().basis)
				rpc_unreliable("update_client_rock",name,get_transform(),linear_velocity,angular_velocity)
			#print(pos)


func _on_rock_body_entered(body):
	#print("ouch! it was: ")
	#for entity in get_colliding_bodies():
	#	print(entity.name)
	
	pass # Replace with function body.
