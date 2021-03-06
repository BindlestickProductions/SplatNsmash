extends Node

class RemotePlayer:
	var p_name
	var p_rtt=50
	var clock_skew
	
	func _init(name):
		p_name=name

class CommandPacket:
	var cp_key
	var cp_mousex
	var cp_mousey
	var cp_seq

class StateSyncPacket:
	var ssp_transform : Transform 
	var ssp_linear : Vector3
	var ssp_angular : Vector3
	var ssp_seq
	
var game_clock = 0
	
# Default game port
var DEFAULT_PORT : int = 10567

# Max number of players
const MAX_PEERS = 12

# Name for my player
var player_name = "The Warrior"

var level_3d
var game_started = false


# Names for remote players in id:name format
var players = {}

# Signals to let lobby GUI know what's going on
signal player_list_changed()
signal connection_failed()
signal connection_succeeded()
signal game_ended()
signal game_error(what)


	
		

# Callback from SceneTree
func _player_connected(id):
	# This is not used in this demo, because _connected_ok is called for clients
	# on success and will do the job.
	pass

# Callback from SceneTree
func _player_disconnected(id):
	if (get_tree().is_network_server()):
		if (has_node("/root/level_3d")): # Game is in progress
			emit_signal("game_error", "Player " + str(players[id]) + " disconnected")
			end_game()
		else: # Game is not in progress
			# If we are the server, send to the new dude all the already registered players
			unregister_player(id)
			for p_id in players:
				# Erase in the server
				rpc_id(p_id, "unregister_player", id)

# Callback from SceneTree, only for clients (not server)
func _connected_ok():
	# Registration of a client beings here, tell everyone that we are here
	rpc("register_player", get_tree().get_network_unique_id(), player_name)
	emit_signal("connection_succeeded")

# Callback from SceneTree, only for clients (not server)
func _server_disconnected():
	emit_signal("game_error", "Server disconnected")
	end_game()

# Callback from SceneTree, only for clients (not server)
func _connected_fail():
	get_tree().set_network_peer(null) # Remove peer
	emit_signal("connection_failed")

# Lobby management functions

remote func register_player(id, new_player_name):
	if (get_tree().is_network_server()):
		# If we are the server, let everyone know about the new player
		#rpc_id(id,"ping_test")
		rpc_id(id, "register_player", 1, player_name) # Send myself to new dude
		for p_id in players: # Then, for each remote player
			rpc_id(id, "register_player", p_id, players[p_id]) # Send player to new dude
			rpc_id(p_id, "register_player", id, new_player_name) # Send new dude to player

	players[id] = RemotePlayer.new(new_player_name)
	
	
	print("New Player Joined: " + new_player_name)
	emit_signal("player_list_changed")

remote func unregister_player(id):
	players.erase(id)
	emit_signal("player_list_changed")




remote func pre_start_game(spawn_points):
	# Change scene
	level_3d = load("res://scenes/level_3d.tscn").instance()
	get_tree().get_root().add_child(level_3d)

	get_tree().get_root().get_node("lobby").hide()

	var player_scene = load("res://scenes/Player3d.tscn")

	for p_id in spawn_points:
		var spawn_pos = level_3d.get_node("spawn_points/" + str(spawn_points[p_id])).get_translation()
		var player = player_scene.instance()

		player.set_name(str(p_id)) # Use unique ID as node name
		player.set_translation(spawn_pos)
		player.set_network_master(p_id) #set unique id as master

		if (p_id == get_tree().get_network_unique_id()):
			# If node for this peer id, set name
			player.set_player_name(player_name)
		else:
			# Otherwise set name from peer
			player.set_player_name(players[p_id].p_name)

		level_3d.get_node("players").add_child(player)

	# Set up score
	level_3d.get_node("score").add_player(get_tree().get_network_unique_id(), player_name)
	for pn in players:
		level_3d.get_node("score").add_player(pn, players[pn].p_name)

	if (not get_tree().is_network_server()):
		# Tell server we are ready to start
		rpc_id(1, "ready_to_start", get_tree().get_network_unique_id())
	elif players.size() == 0:
		post_start_game()

remote func post_start_game():
	get_tree().set_pause(false) # Unpause and unleash the game!
	game_started=true

var players_ready = []
var players_delay = []

func just_testingit():
	print("can I do this?")

remote func ready_to_start(id):
	assert(get_tree().is_network_server())

	if (not id in players_ready):
		players_ready.append(id)
		players_delay.append(0)

	if (players_ready.size() == players.size()):
		for p in players:
			rpc_id(p, "post_start_game")
		post_start_game()

var old_delay
var ravg_rtt = 50
var server_time
# Running on Server
remote func ping_master(id,time,client_time):
	var sv_time = OS.get_system_time_msecs()
	var delay = sv_time-time
	players[id].p_rtt=delay;
	players[id].clock_skew=client_time-sv_time;
	ravg_rtt=(ravg_rtt+delay)/2.0
	print(" Player " + str(id))
	print("   #  RTT : " + str(players[id].p_rtt))
	print("   # Skew : " + str(players[id].clock_skew))



# Running on Clients 
remote func ping_test(time):
	server_time=time
	rpc_unreliable_id(1,"ping_master",get_tree().get_network_unique_id(),time,OS.get_system_time_msecs())
	
# Running on clients:	
remote func update_rtt(rtt_time):
	print("got new rtt drop: " + str(rtt_time))
	players[1].p_rtt = rtt_time
	


var process_throttle=10
var process_throttle_counter=0
func _physics_process(delta):
	process_throttle_counter+=1
	if(process_throttle_counter % process_throttle == 0):
		if(get_tree().is_network_server()):
			if (players_ready.size() == players.size()):
				var i = 0
				for p in players:
					print("Sending RPC to "+str(p))
					rpc_id(p,"update_rtt",players[p].p_rtt)
					rpc_unreliable_id(p,"ping_test",OS.get_system_time_msecs())
					i+=1
		else:
			if(players):	
				print("My RTT is: " + str(players[1].p_rtt))
		

func host_game(port, new_player_name):
	player_name = new_player_name
	DEFAULT_PORT = port
	var host = NetworkedMultiplayerENet.new()
	host.create_server(DEFAULT_PORT, MAX_PEERS)
	get_tree().set_network_peer(host)

func join_game(port, ip, new_player_name):
	player_name = new_player_name
	DEFAULT_PORT = port
	var host = NetworkedMultiplayerENet.new()
	host.create_client(ip, DEFAULT_PORT)
	get_tree().set_network_peer(host)

func get_player_list():
	return players.values()

func get_player_name():
	return player_name

func begin_game():
	assert(get_tree().is_network_server())

	# Create a dictionary with peer id and respective spawn points, could be improved by randomizing
	var spawn_points = {}
	spawn_points[1] = 0 # Server in spawn point 0
	var spawn_point_idx = 1
	for p in players:
		spawn_points[p] = spawn_point_idx
		spawn_point_idx += 1
	# Call to pre-start game with the spawn points
	for p in players:
		rpc_id(p, "pre_start_game", spawn_points)

	pre_start_game(spawn_points)

func end_game():
	if (has_node("/root/level_3d")): # Game is in progress
		# End it
		get_node("/root/level_3d").queue_free()

	emit_signal("game_ended")
	players.clear()
	get_tree().set_network_peer(null) # End networking

func _ready():
	set_physics_process(true)
	get_tree().connect("network_peer_connected", self, "_player_connected")
	get_tree().connect("network_peer_disconnected", self,"_player_disconnected")
	get_tree().connect("connected_to_server", self, "_connected_ok")
	get_tree().connect("connection_failed", self, "_connected_fail")
	get_tree().connect("server_disconnected", self, "_server_disconnected")
	
