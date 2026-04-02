---
name: godot-gdscript
description: Write, refactor, and debug Godot 4 GDScript with engine-idiomatic patterns (scenes/nodes, signals, resources, input, physics, UI). Use when the user mentions Godot, GDScript, .gd scripts, scenes, nodes, signals, autoload/singleton, exported variables, or Godot 4 APIs.
---

# Godot GDScript (Godot 4)

## Quick Start

When writing or modifying GDScript:

1. Prefer Godot 4 idioms: scenes + nodes, signals, resources, groups, and the SceneTree lifecycle.
2. Use typed GDScript where practical (typed members/params/returns) and `@export` for editor wiring.
3. Keep code node-centric: scripts attach to nodes, avoid global state unless using Autoload intentionally.
4. Validate for runtime safety: `is_instance_valid`, null checks, and safe node lookups.

## Default Conventions

- **Godot version**: Target Godot 4.x APIs and syntax (`@onready`, `@export`, `Callable`, etc.).
- **Typing**: Prefer typed declarations:
  - `var speed: float = 5.0`
  - `func take_damage(amount: int) -> void:`
- **Node paths**: Prefer editor wiring via `@export var foo_path: NodePath` or direct `@export var foo: Node` over brittle hard-coded paths.
- **Signals**: Prefer declaring custom signals and connecting explicitly; avoid “magic” connections without showing where they are made.
- **Frames**: Use `_process(delta)` for frame logic, `_physics_process(delta)` for physics; avoid mixing.
- **Coroutines**: Use `await` with signals/timers (`await get_tree().create_timer(0.2).timeout`).

## Workflow (Do This Every Time)

### 1) Clarify the gameplay/UI intent (infer if not stated)

- **Node type & responsibilities**: What node owns the script (`CharacterBody2D`, `Control`, `Node`, etc.)?
- **Scene context**: Where is it in the tree? Any required child nodes?
- **Signals / inputs**: What events drive behavior?

If details are missing, pick the most common default for Godot 4 and state assumptions in the response.

### 2) Implement with engine-friendly structure

- Put initialization in `_ready()`
- Cache dependencies with `@onready`
- Prefer signals over polling where appropriate
- Keep per-frame code minimal and deterministic

### 3) Add safety checks

- `if not is_instance_valid(target): return`
- Guard missing nodes/resources with clear errors (`push_error`) or early returns

### 4) Provide a mini integration guide

- Where to attach the script
- What to add in the scene tree (child nodes, timers, areas, etc.)
- What to wire in the Inspector (`@export` fields)

## Common Patterns (Copy/Paste Friendly)

### Typed exports + onready cache

```gdscript
extends Node

@export var target_path: NodePath
@onready var target: Node = get_node_or_null(target_path)
```

### Connect a signal in code (Godot 4)

```gdscript
extends Area2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	# ...
	pass
```

### Timer with await

```gdscript
func flash_and_wait(duration: float) -> void:
	# ... do something ...
	await get_tree().create_timer(duration).timeout
	# ... continue ...
```

## Debugging Checklist (Godot-Specific)

- **Script not running**: Is it attached to the correct node/scene instance?
- **Null node refs**: Is the node path correct? Is the node created later (needs `await` or deferred setup)?
- **Signals not firing**: Is the node type correct (e.g., `Area2D` vs `PhysicsBody2D`)? Is monitoring enabled? Is the connection happening?
- **Physics weirdness**: Are physics changes done in `_physics_process`? Are you mixing kinematic movement with direct position changes?
- **Autoload issues**: Is it registered in Project Settings → Autoload with the expected name?

## Examples (What “Good Output” Looks Like)

### Example: Player movement (2D)

```gdscript
extends CharacterBody2D

@export var speed: float = 220.0

func _physics_process(_delta: float) -> void:
	var input_dir := Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	).normalized()

	velocity = input_dir * speed
	move_and_slide()
```

### Example: UI button to emit signal

```gdscript
extends Control

signal start_pressed

@onready var start_button: Button = %StartButton

func _ready() -> void:
	start_button.pressed.connect(func() -> void:
		start_pressed.emit()
	)
```

