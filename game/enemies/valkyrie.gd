extends StaticBody2D

signal emit_bullet(name, creator, pos, rot, speed, bounces)
signal score(amount)

onready var hit_aid_tween = get_node("hit_aid/tween")
onready var hit_aid_label = get_node("hit_aid/label")
onready var hit_aid = get_node("hit_aid")
onready var dying_tween = get_node("dying_tween")

# Where to target the shoot
enum target_e {
	FIXED,	# Point the shooting at the current body's rotation
	PLAYER,	# Point the shooting at the ship
}

# Pattern of the shooting
enum pattern_e {
	SINGLE,		# Shoot shoot_amount bullets at the target every shoot_delay seconds
	SPREAD,		# Shoot shoot_amount bullets at the target at once with shoot_degree_step between each other
	ROTATION,	# Shoot a bullet every shoot_delay seconds with the body rotating shoot_degree_step after each shoot
	RING,		# Shoot all bullet at once in a ring
}

export(int, "FIXED", "PLAYER") var shoot_target = target_e.FIXED
export(int, "SINGLE", "SPREAD", "ROTATION", "RING") var shoot_pattern = pattern_e.SINGLE
export(int, 0, 64) var shoot_amount = 0
export(int, -360, 360) var shoot_degree_step = 0
export(float, 0.1, 2.0, 0.1)  var shoot_delay = 0.1
export(int, 0, 9999) var health = 5
export(float, 128.0, 512.0, 16.0) var bullet_speed = 300.0
export(int, 1, 999) var bullet_bounces = 1
export(float, 0.01, 10.0, 0.001) var path_speed = 1.0
export(int, 1, 999) var path_loops = 1
export(float, 0.0, 1.0, 0.01) var path_offset = 0.0
export(bool) var on_screen = false
export(bool) var active = true setget set_active, get_active
export(NodePath) var pickable

enum status_e {
	FLYING,			# Flying
	SHOOTING,		# Shooting
	DYING,			# Fading away
}
var status = status_e.FLYING
var shoots = 0
var path_position
var initial_rotation
var initial_position
onready var animation = get_node("sprite")
onready var timer = get_node("timer")
onready var path_follow = get_node("path/follow")
onready var activate_trigger = get_node("trigger")

func _ready():
	path_follow
	initial_position = get_pos()
	initial_rotation = get_rot()
	path_position = 0.0
	set_fixed_process(true)
	hit_aid_tween.interpolate_property(hit_aid_label, "rect/scale", Vector2(0.0, 0.0), Vector2(0.75, 0.75), 1.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	hit_aid_tween.interpolate_property(hit_aid_label, "rect/pos", Vector2(0.0, 0.0), Vector2(-16.0*0.75, -16.0*0.75), 1.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	hit_aid_tween.interpolate_property(hit_aid_label, "visibility/opacity", 1.0, 0.0, 1.0, Tween.TRANS_BACK, Tween.EASE_IN)
	hit_aid_tween.reset_all()
	dying_tween.interpolate_property(animation, "visibility/opacity", 1.0, 0.0, 0.5, Tween.TRANS_SINE, Tween.EASE_IN)
	path_position += path_offset
	if activate_trigger != null:
		activate_trigger.connect("body_enter", self, "_on_body_enter_trigger")
	if pickable != null and get_node(pickable) != null:
		get_node(pickable).hide()

func set_active(val):
	active = val
	status = status_e.SHOOTING

func get_active():
	return active

func _fixed_process(delta):
	if active:
		var view_rect_half = (get_viewport_rect().size / get_canvas_transform().get_scale()) / 2.0
		var view_pos = (get_viewport_transform().get_origin() - view_rect_half) * -1.0
		
		if status == status_e.DYING:
			set_collision_mask(0)
			set_layer_mask(0)
		else: #VISIBLE
			set_collision_mask(1)
			set_layer_mask(1)
		
		if status != status_e.DYING:
			face_ship()
		
		hit_aid.set_global_rot(0.0)
		
		path_position += delta * path_speed
		path_follow.set_unit_offset(path_position)
		var base = initial_position;
		if on_screen:
			base += view_pos
		set_pos(base + path_follow.get_pos())
		if shoot_target == target_e.FIXED:
			set_rot(path_follow.get_rot()+3.0*PI/2.0)
		
		if path_position > path_loops:
			queue_free()

func face_ship():
	if shoot_target == target_e.PLAYER:
		var enemy = Globals.get("currentShip")
		if(enemy!=null):
			set_rot((get_pos()-enemy.get_pos()).angle()+3.0*PI/2.0 + initial_rotation)

func _on_timer_timeout():
	animation.stop()
	animation.play("shoot")
	status = status_e.SHOOTING

func gets_hurt(damage, pos, normal, emitter, travel_time):
	var score = damage
	if emitter == self:
		# 5 more points of karma bonus
		score+=5
	if travel_time > 1.0:
		# 7 more points for shoot from far away
		score+=7
	if emitter == self and travel_time > 1.0:
		# super combo bonus
		score+=4
	health-=score
	emit_signal("score", score)
	if health <= 0:
		status = status_e.DYING
		animation.play("dying")
		dying_tween.interpolate_property(animation, "transform/rot", get_rot(), get_rot()+32.0*PI, 0.5, Tween.TRANS_LINEAR, Tween.EASE_IN)
		dying_tween.start()
	hit_aid_label.set_text(str(score))
	hit_aid_tween.resume_all()
	hit_aid_tween.reset_all()
	hit_aid_tween.start()

func _on_visibility_enter_screen():
	_start_shooting()

func _start_shooting():
	status = status_e.SHOOTING
	animation.set_frame(0)
	animation.play("shoot")

func _on_sprite_finished():
	if status == status_e.FLYING:
		if(get_node("visibility").is_on_screen()):
			timer.set_wait_time(shoot_delay)
			timer.start()
	elif status == status_e.SHOOTING:
		if shoot_pattern != pattern_e.ROTATION:
			face_ship()
		
		if shoot_pattern == pattern_e.SINGLE:
			emit_signal("emit_bullet", "arrow", self, get_node("origin").get_global_pos(), get_rot()+PI/2.0, bullet_speed, bullet_bounces)
			get_node("sounds").play("shoot")
			shoots+=1
		if shoot_pattern == pattern_e.SPREAD:
			var angle = get_rot()+PI/2.0
			var vec = Vector2(0.0, -24.0)
			emit_signal("emit_bullet", "arrow", self, vec.rotated(angle) + get_global_pos(), angle, bullet_speed, bullet_bounces)
			for b in range(1, 1+shoot_amount/2):
				var sub_angle = deg2rad(shoot_degree_step*b)
				emit_signal("emit_bullet", "arrow", self, vec.rotated(angle + sub_angle) + get_global_pos(), angle + sub_angle, bullet_speed, bullet_bounces)
				emit_signal("emit_bullet", "arrow", self, vec.rotated(angle - sub_angle) + get_global_pos(), angle - sub_angle, bullet_speed, bullet_bounces)
			get_node("sounds").play("shoot")
			shoots+=shoot_amount
		if shoot_pattern == pattern_e.ROTATION:
			set_rotd(get_rotd() + shoot_degree_step)
			emit_signal("emit_bullet", "arrow", self, get_node("origin").get_global_pos(), get_rot()+PI/2.0, bullet_speed, bullet_bounces)
			get_node("sounds").play("shoot")
			shoots+=1
		if shoot_pattern == pattern_e.RING:
			var angle = get_rot()+PI/2.0
			var vec = Vector2(0.0, -24.0) #TODO: make it dynamic
			for b in range(0, shoot_amount):
				var sub_angle = deg2rad((360.0/shoot_amount)*b)
				emit_signal("emit_bullet", "arrow", self, vec.rotated(angle + sub_angle) + get_global_pos(), angle + sub_angle, bullet_speed, bullet_bounces)
			get_node("sounds").play("shoot")
			shoots+=shoot_amount
		
		if shoots > shoot_amount:
			status = status_e.FLYING
			animation.set_frame(0)
			animation.play("fly")
	
	else: #DYING
		pass

func _on_dying_complete( object, key ):
	if pickable != null and get_node(pickable) != null:
		get_node(pickable).set_pos(get_pos())
		get_node(pickable).show()
	queue_free()

func _on_tween_tween_complete( object, key ):
	hit_aid_tween.reset_all()
	hit_aid_tween.stop_all()

func _on_body_enter_trigger( body ):
	if body==Globals.get("currentShip"):
		set_active(true)