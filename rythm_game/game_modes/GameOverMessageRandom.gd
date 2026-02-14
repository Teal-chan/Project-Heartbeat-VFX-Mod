extends Label

const QUOTES = [
	"Mistakes were made...", # MVG
	"Game over yeah!!!", # Sega Rally Championship
	"Whoops...", # I made it up
	"Mission failed, we'll get 'em next time", # MW2
	"Dear diary, today I failed", # Binding of isaac
	"Heartbreak!", # Original proposal for game over quote
	"Love is over", # Catherine
	"Snake??? Snake??? Snake!!!!!", # Metal gear solid
	"YOU FAILED", # Dark souls,
	"ASSIGNMENT: TERMINATED\nSUBJECT: AIKO\nREASON: FAILURE TO PRESS MISSION-CRITICAL BUTTONS", # Half-Life 2
	"#pwned", # You got pwned, son.
	"Hammond you insufferable idiot! You've failed the button-mashing game!", # Richard hammond
	"Skill issue", # Yahooey reference,
	"All you had to do was follow the damn rhythm, CJ!", # GTA San andreas
	"Even the VFX couldn't save you", # PH Extend
	"The modding was great, the playing... not so much", # PH Extend
]

var _last_index := -1

func _ready():
	randomize()
	reroll()

func reroll():
	var index := randi() % QUOTES.size()
	# Avoid repeating the same message twice in a row
	if QUOTES.size() > 1:
		while index == _last_index:
			index = randi() % QUOTES.size()
	_last_index = index
	text = QUOTES[index]
