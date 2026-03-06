class_name StateMachine
extends Node

var current_state: State
var states: Dictionary = {}


func _ready() -> void:
	for child in get_children():
		if child is State:
			states[child.name.to_lower()] = child
			child.character = owner as CharacterBody2D
			child.state_machine = self

	# Defer initial state to ensure owner @onready vars are initialized
	call_deferred("_initialize_state")


func _initialize_state() -> void:
	for child in get_children():
		if child is State:
			current_state = child
			break
	if current_state:
		current_state.enter()


func _process(delta: float) -> void:
	if current_state:
		current_state.process_state(delta)


func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_process_state(delta)


func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		current_state.input_state(event)


func transition_to(state_name: String) -> void:
	var new_state = states.get(state_name.to_lower())
	if new_state == null or new_state == current_state:
		return
	current_state.exit()
	current_state = new_state
	current_state.enter()
