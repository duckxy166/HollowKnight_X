class_name State
extends Node

var character: CharacterBody2D
var state_machine: Node  # StateMachine


func enter() -> void:
	pass


func exit() -> void:
	pass


func process_state(_delta: float) -> void:
	pass


func physics_process_state(_delta: float) -> void:
	pass


func input_state(_event: InputEvent) -> void:
	pass
