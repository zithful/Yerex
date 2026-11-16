--!strict
-- Tunable gameplay values. Replicated to clients, so nothing secret lives here,
-- and the server never trusts a client-reported value taken from this file.
-- Units are studs and seconds. 1 metre is roughly 2.8 studs at avatar scale.

return table.freeze({
	-- Match flow
	MATCH_LENGTH = 300, -- seconds of play per match
	WARMUP_TIME = 8,
	KICKOFF_FREEZE = 3,
	GOAL_CELEBRATION = 4,
	FULLTIME_PAUSE = 10,

	-- Ball
	BALL_DIAMETER = 2,
	BALL_DENSITY = 0.25,
	BALL_ELASTICITY = 0.45,
	BALL_FRICTION = 0.35,
	-- Roblox gravity (196 studs/s^2) makes a ball fly like a rock at avatar scale.
	-- An upward force on the ball brings its effective gravity down to this.
	BALL_GRAVITY = 70,
	AIR_DRAG = 0.12, -- fraction of velocity lost per second while airborne
	ROLL_DRAG = 0.9, -- fraction of horizontal velocity lost per second on the ground
	CURL_STRENGTH = 0.9, -- Magnus-style lateral acceleration multiplier
	SPIN_DECAY = 0.15,

	-- Possession and dribbling
	PICKUP_RADIUS = 4,
	PICKUP_MAX_HEIGHT = 4.5,
	TRAP_MAX_SPEED = 75, -- faster balls bounce off instead of being controlled
	KICK_PICKUP_BLOCK = 0.35, -- kicker cannot re-collect for this long
	DRIBBLE_DISTANCE = 2.6, -- ball distance in front of the feet when jogging
	DRIBBLE_SPEED_LEAD = 0.09, -- extra distance per stud/s of speed (sprint = bigger touches)
	DRIBBLE_STIFFNESS = 14,
	DRIBBLE_LOSE_DISTANCE = 9,

	-- Movement and stamina
	JOG_SPEED = 17,
	SPRINT_SPEED = 25,
	DRIBBLE_SPEED_MULT = 0.9,
	STAMINA_MAX = 100,
	STAMINA_DRAIN = 14, -- per second while sprinting
	STAMINA_REGEN = 9, -- per second while not sprinting
	FATIGUE_THRESHOLD = 30, -- below this, top speed starts to drop
	FATIGUE_MIN_MULT = 0.85,

	-- Passing
	PASS_ASSIST_ANGLE = 40, -- degrees either side of aim to search for a receiver
	PASS_MAX_RANGE = 140,
	PASS_DEFAULT_DISTANCE = 35,
	GROUND_PASS_BASE = 38,
	GROUND_PASS_PER_STUD = 1.05,
	GROUND_PASS_MAX = 115,
	THROUGH_LEAD_TIME = 0.9,
	LOB_SPEED = 75, -- horizontal speed used to pick lob flight time

	-- Shooting
	CHARGE_TIME = 1.0, -- seconds of hold for a full power bar
	SHOT_MIN_SPEED = 75,
	SHOT_MAX_SPEED = 145,
	FINESSE_MIN_SPEED = 62,
	FINESSE_MAX_SPEED = 108,
	FINESSE_CURL_ANGLE = 11, -- degrees the finesse shot starts wide of target
	LOW_DRIVEN_MIN_SPEED = 85,
	LOW_DRIVEN_MAX_SPEED = 128,
	SHOT_AIM_ASSIST_ANGLE = 50,
	SHOT_BASE_ERROR = 1.5, -- degrees
	SHOT_DISTANCE_ERROR = 0.035, -- degrees per stud from goal
	SHOT_SPRINT_ERROR = 2.5,
	SHOT_OFFBALANCE_ERROR = 5, -- shooting across the body
	SHOT_OVERPOWER_START = 0.85,
	SHOT_OVERPOWER_ERROR = 14, -- extra degrees at full overpower
	FIRST_TIME_RADIUS = 5, -- volleys and headers when the ball is close but not owned

	-- Defending
	TACKLE_RANGE = 6.5,
	TACKLE_FRONT_CHANCE = 0.7,
	TACKLE_BEHIND_CHANCE = 0.3,
	TACKLE_COOLDOWN = 0.9,
	TACKLE_MISS_STUN = 0.5,
	TACKLED_STUN = 0.45,
	SLIDE_DURATION = 0.45,
	SLIDE_REACH = 4.5,
	SLIDE_COOLDOWN = 2.0,
	SLIDE_RECOVERY = 0.9,
	SLIDE_FOUL_STUN = 1.0,

	-- Skill moves
	KNOCK_ON_SPEED = 52,
	DRAG_BACK_SPEED = 22,
	SKILL_COOLDOWN = 0.6,

	-- Goalkeepers (AI)
	KEEPER_SPEED = 16,
	KEEPER_DIVE_SPEED = 32,
	KEEPER_REACTION = 0.16,
	KEEPER_CATCH_SPEED = 95,
	KEEPER_CATCH_RADIUS = 4,
	KEEPER_HOLD_TIME = 1.4,
	KEEPER_RUSH_DISTANCE = 30,

	-- Networking
	ACTIONS_PER_SECOND = 12,
})
