extends KinematicBody

#
#class CommandPacket:
#	var cp_key
#	var cp_mousex
#	var cp_mousey
#	var cp_seq

#class StateSyncPacket:
#	var ssp_transform : Transform 
#	var ssp_linear : Vector3
#	var ssp_angular : Vector3
#	var ssp_seq
#

# Declare member variables here. Examples:
puppet var slave_pos : Vector3 = Vector3()
puppet var slave_dir : Vector3 = Vector3()
puppet var slave_motion : Vector3 = Vector3()

export var stunned = false

var current_anim = ""
var prev_bombing = false
var bomb_index = 0

var gravity : Vector3 = Vector3.DOWN * 12.0
export var speed : float = 4.0

var velocity : Vector3 = Vector3()


# Use sync because it will be called everywhere
sync func setup_bomb(bomb_name, pos, by_who):
	var bomb = preload("res://scenes/bomb3d.tscn").instance()
	bomb.set_name(bomb_name) # Ensure unique name for the bomb
	bomb.set_translation(pos)
	bomb.from_player = by_who
	# No need to set network mode to bomb, will be owned by master by default
	get_node("../..").add_child(bomb)


# Called when the node enters the scene tree for the first time.
func _ready():
	slave_pos = self.get_translation()
	pass # Replace with function body.

var old_rpc_player_command_time=0
puppet func rpc_player_command(velocity,direction,timestamp):
	if(timestamp > old_rpc_player_command_time):
		old_rpc_player_command_time = timestamp
		slave_dir = direction
		self.set_rotation(slave_dir)
		slave_motion = velocity
	
var old_rpc_state_sync_time=0
puppet func rpc_player_sync(rock_transform,velocity,timestamp):
	if(timestamp > old_rpc_state_sync_time):
		old_rpc_state_sync_time=timestamp
		transform = rock_transform
		slave_motion = velocity

var netCounter=0
var ticksPerUpdate=10
var buttonPressed=false
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):
	buttonPressed=false
	var sink = velocity.y # we want to stor eonly the downward velocity for this game ( you would not normaly do this
	# This removes any latteral movements we dont want 
	velocity = Vector3( 0.0, sink , 0.0 )
	if is_on_floor():
		velocity += gravity * 0.1 * delta
	else:
		velocity += gravity * delta
	
	if (is_network_master()):
		if(netCounter%ticksPerUpdate == 0):
			rpc_unreliable("rpc_player_sync",get_transform(),slave_motion,OS.get_system_time_msecs())	
	
	if (is_network_master()):
		# get teh imput here  
		

		
		var bombing = Input.is_action_pressed("set_bomb")
		if (stunned):
			bombing = false
			velocity = Vector3()
			
		else:
			if (Input.is_action_pressed("move_left")):
				velocity += Vector3.LEFT * speed
				buttonPressed=true
				self.set_rotation( Vector3( 0 , -.5*PI , 0 ) )
			if (Input.is_action_pressed("move_right")):
				buttonPressed=true
				velocity += Vector3.RIGHT * speed
				self.set_rotation( Vector3( 0 , .5*PI , 0 ))
			if (Input.is_action_pressed("move_up")):
				buttonPressed=true
				velocity += Vector3.FORWARD * speed
				self.set_rotation( Vector3( 0 , PI , 0 ) )
			if (Input.is_action_pressed("move_down")):
				buttonPressed=true
				velocity += Vector3.BACK * speed
				self.set_rotation( Vector3( 0 ,2*PI , 0 ) )
			
			
		if (bombing and not prev_bombing):
			var bomb_name = get_name() + str(bomb_index)
			var bomb_pos = self.get_translation() 
			#todo make this:
			rpc("setup_bomb", bomb_name, bomb_pos, get_tree().get_network_unique_id())

		prev_bombing = bombing
		
		if(buttonPressed):
			var send_timestamp=OS.get_system_time_msecs()
			rpc_unreliable("rpc_player_command",velocity,self.get_rotation(),send_timestamp)
		#rset("slave_motion", velocity)
		#var mpos : Vector3 = self.get_translation() 
		#rset("slave_pos", self.get_translation()  )
		#rset("slave_dir" , self.get_rotation() )
	else:
		#self.set_translation(slave_pos)
		#self.set_rotation(slave_dir)
		velocity = slave_motion

	var new_anim = "standing"
	if (velocity.z < 0):
		new_anim = "walk_up"
	elif (velocity.z > 0):
		new_anim = "walk_down"
	elif (velocity.x < 0):
		new_anim = "walk_left"
	elif (velocity.x > 0):
		new_anim = "walk_right"

	if (stunned):
		new_anim = "stunned"
	
	# possibly add the animations for the directions  
	if (new_anim != current_anim):
		current_anim = new_anim 
		if ( current_anim == "stunned" ): # or ( current_anim == "standing" ):
			get_node("AnimationPlayer").play(current_anim)
		else:
			get_node("AnimationPlayer").stop()
		print(current_anim)
		
	velocity = move_and_slide( velocity , Vector3.UP)
	if (not is_network_master() ):
		slave_pos = self.get_translation() # To avoid jitter
#
	var pos = get_translation()
	var cam = get_tree().get_root().get_camera()
	var screenpos = cam.unproject_position(pos)
	get_node("PlayerName").set_position(Vector2(screenpos.x , screenpos.y ) )
	netCounter+=1

func set_player_name(new_name):
	get_node("PlayerName/label").set_text(new_name)
	
puppet func stun():
	stunned = true

master func exploded(by_who):
	if (stunned):
		return
	print("stunned by: "+ str(by_who) )
	rpc("stun") # Stun slaves
	stun() # Stun master - could use sync to do both at once
