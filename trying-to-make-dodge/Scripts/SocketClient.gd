extends Node

var socket := StreamPeerTCP.new()
var connected := false
var message_buffer := ""  # Buffer for incomplete messages

signal action_received(action_data)

func _ready():
	connect_to_server()

func connect_to_server():
	print("Attempting to connect to Python server...")
	var err = socket.connect_to_host("127.0.0.1", 5555)
	if err != OK:
		print("Failed to initiate connection: ", err)
		return
	
	# Poll connection status until connected or failed
	for i in range(50):  # Try for 5 seconds (50 * 0.1s)
		await get_tree().create_timer(0.1).timeout
		socket.poll()
		
		var status = socket.get_status()
		
		if status == StreamPeerTCP.STATUS_CONNECTED:
			connected = true
			print("✓ Connected to Python server!")
			return
		elif status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			print("✗ Connection failed, status: ", status)
			return
		# If STATUS_CONNECTING (1), keep waiting
	
	print("✗ Connection timeout")

func _process(_delta):
	if not connected:
		return
	
	# Poll the connection
	socket.poll()
	
	# Check connection status
	var status = socket.get_status()
	if status != StreamPeerTCP.STATUS_CONNECTED:
		connected = false
		print("Disconnected from server")
		return
	
	# Check for incoming messages
	if socket.get_available_bytes() > 0:
		var data = socket.get_utf8_string(socket.get_available_bytes())
		if data.length() > 0:
			message_buffer += data
			process_buffer()

func process_buffer():
	# Process all complete messages (separated by newlines)
	while "\n" in message_buffer:
		var newline_pos = message_buffer.find("\n")
		var message = message_buffer.substr(0, newline_pos)
		message_buffer = message_buffer.substr(newline_pos + 1)
		
		if message.length() > 0:
			parse_action(message)

func send_state(state_dict: Dictionary):
	if not connected:
		return
	
	var json_string = JSON.stringify(state_dict)
	# Add newline as message delimiter
	json_string += "\n"
	
	socket.put_data(json_string.to_utf8_buffer())

func parse_action(json_string: String):
	var json = JSON.new()
	var error = json.parse(json_string)
	
	if error == OK:
		var data = json.data
		action_received.emit(data)
	else:
		print("JSON Parse Error: ", json.get_error_message())
		print("Problematic JSON: ", json_string)

func disconnect_from_server():
	if connected:
		socket.disconnect_from_host()
		connected = false
		print("Disconnected from Python server")
