-- veyl_emotes: the emote list (base-game animations and scenarios only).
--
-- id        unique, lowercase; used by /e <id> and favourites
-- cat       'gestures' | 'dances' | 'actions' | 'poses' | 'props' | 'shared'
-- anim      { dict, clip, loop = true|false, upper = true (upper body only: you can walk), ms = duration for one-shots }
-- scenario  a world scenario (brings its own props); used instead of anim
-- prop      { model, bone, pos = { x, y, z }, rot = { x, y, z } }   (bones: 28422 / 57005 right hand, 18905 / 60309 left hand)
-- partner   shared emotes only: the clip the other person plays, and how far in front of you they stand

local CEL = 'anim@mp_player_intcelebrationmale@'
local CAS = 'gestures@m@standing@casual'

EmoteList = {
    -- Gestures (one-shot, upper body)
    { id = 'wave', label = 'Wave', cat = 'gestures', anim = { dict = CEL .. 'wave', clip = 'wave', upper = true, ms = 3000 } },
    { id = 'hello', label = 'Hello', cat = 'gestures', anim = { dict = CAS, clip = 'gesture_hello', upper = true, ms = 2500 } },
    { id = 'bye', label = 'Goodbye', cat = 'gestures', anim = { dict = CAS, clip = 'gesture_bye_soft', upper = true, ms = 2500 } },
    { id = 'comehere', label = 'Come here', cat = 'gestures', anim = { dict = CAS, clip = 'gesture_come_here_soft', upper = true, ms = 2500 } },
    { id = 'nope', label = 'No way', cat = 'gestures', anim = { dict = CAS, clip = 'gesture_no_way', upper = true, ms = 2500 } },
    { id = 'why', label = 'Why?', cat = 'gestures', anim = { dict = CAS, clip = 'gesture_why', upper = true, ms = 2500 } },
    { id = 'damn', label = 'Damn', cat = 'gestures', anim = { dict = CAS, clip = 'gesture_damn', upper = true, ms = 2500 } },
    { id = 'easy', label = 'Easy now', cat = 'gestures', anim = { dict = CAS, clip = 'gesture_easy_now', upper = true, ms = 2500 } },
    { id = 'point', label = 'Point', cat = 'gestures', anim = { dict = CAS, clip = 'gesture_point', upper = true, ms = 2500 } },
    { id = 'shrug', label = 'Shrug', cat = 'gestures', anim = { dict = 'gestures@f@standing@casual', clip = 'gesture_shrug_hard', upper = true, ms = 2000 } },
    { id = 'salute', label = 'Salute', cat = 'gestures', anim = { dict = CEL .. 'salute', clip = 'salute', upper = true, ms = 3000 } },
    { id = 'facepalm', label = 'Facepalm', cat = 'gestures', anim = { dict = CEL .. 'face_palm', clip = 'face_palm', upper = true, ms = 3000 } },
    { id = 'thumbsup', label = 'Thumbs up', cat = 'gestures', anim = { dict = CEL .. 'thumbs_up', clip = 'thumbs_up', upper = true, ms = 3000 } },
    { id = 'peace', label = 'Peace', cat = 'gestures', anim = { dict = CEL .. 'peace', clip = 'peace', upper = true, ms = 3000 } },
    { id = 'vsign', label = 'V sign', cat = 'gestures', anim = { dict = CEL .. 'v_sign', clip = 'v_sign', upper = true, ms = 3000 } },
    { id = 'rock', label = 'Rock on', cat = 'gestures', anim = { dict = CEL .. 'rock', clip = 'rock', upper = true, ms = 3000 } },
    { id = 'finger', label = 'The finger', cat = 'gestures', anim = { dict = CEL .. 'finger', clip = 'finger', upper = true, ms = 3000 } },
    { id = 'shush', label = 'Shush', cat = 'gestures', anim = { dict = CEL .. 'shush', clip = 'shush', upper = true, ms = 3000 } },
    { id = 'blowkiss', label = 'Blow a kiss', cat = 'gestures', anim = { dict = CEL .. 'blow_kiss', clip = 'blow_kiss', upper = true, ms = 3000 } },
    { id = 'slowclap', label = 'Slow clap', cat = 'gestures', anim = { dict = CEL .. 'slow_clap', clip = 'slow_clap', upper = true, ms = 4000 } },
    { id = 'knuckles', label = 'Crack knuckles', cat = 'gestures', anim = { dict = CEL .. 'knuckle_crunch', clip = 'knuckle_crunch', upper = true, ms = 3000 } },
    { id = 'cutthroat', label = 'Cut throat', cat = 'gestures', anim = { dict = CEL .. 'cut_throat', clip = 'cut_throat', upper = true, ms = 3000 } },
    { id = 'nosepick', label = 'Pick nose', cat = 'gestures', anim = { dict = CEL .. 'nose_pick', clip = 'nose_pick', upper = true, ms = 4000 } },
    { id = 'ohsnap', label = 'Oh snap', cat = 'gestures', anim = { dict = CEL .. 'oh_snap', clip = 'oh_snap', upper = true, ms = 3000 } },
    { id = 'surrender', label = 'Surrender', cat = 'gestures', anim = { dict = CEL .. 'surrender', clip = 'surrender', upper = true, ms = 3000 } },
    { id = 'handsup', label = 'Hands up', cat = 'gestures', anim = { dict = 'random@mugging3', clip = 'handsup_standing_base', upper = true, loop = true } },
    { id = 'crossarms', label = 'Cross arms', cat = 'gestures', anim = { dict = 'amb@world_human_hang_out_street@female_arms_crossed@base', clip = 'base', upper = true, loop = true } },

    -- Dances (loop)
    { id = 'dance', label = 'Dance', cat = 'dances', anim = { dict = 'anim@amb@nightclub@mini@dance@dance_solo@male@var_a@', clip = 'high_center', loop = true } },
    { id = 'dance2', label = 'Dance 2', cat = 'dances', anim = { dict = 'anim@amb@nightclub@mini@dance@dance_solo@male@var_a@', clip = 'med_center', loop = true } },
    { id = 'dance3', label = 'Dance 3', cat = 'dances', anim = { dict = 'anim@amb@nightclub@mini@dance@dance_solo@male@var_b@', clip = 'high_center', loop = true } },
    { id = 'dance4', label = 'Dance 4', cat = 'dances', anim = { dict = 'anim@amb@nightclub@mini@dance@dance_solo@female@var_a@', clip = 'high_center', loop = true } },
    { id = 'dance5', label = 'Dance 5', cat = 'dances', anim = { dict = 'anim@amb@nightclub@mini@dance@dance_solo@female@var_b@', clip = 'med_center', loop = true } },
    { id = 'airguitar', label = 'Air guitar', cat = 'dances', anim = { dict = CEL .. 'air_guitar', clip = 'air_guitar', loop = true } },
    { id = 'dj', label = 'DJ', cat = 'dances', anim = { dict = CEL .. 'dj', clip = 'dj', loop = true } },
    { id = 'raisetheroof', label = 'Raise the roof', cat = 'dances', anim = { dict = CEL .. 'raise_the_roof', clip = 'raise_the_roof', loop = true } },
    { id = 'bangingtunes', label = 'Banging tunes', cat = 'dances', anim = { dict = CEL .. 'banging_tunes', clip = 'banging_tunes', loop = true } },
    { id = 'uncledisco', label = 'Uncle disco', cat = 'dances', anim = { dict = CEL .. 'uncle_disco', clip = 'uncle_disco', loop = true } },
    { id = 'salsa', label = 'Salsa roll', cat = 'dances', anim = { dict = CEL .. 'salsa_roll', clip = 'salsa_roll', loop = true } },
    { id = 'heartpump', label = 'Heart pumping', cat = 'dances', anim = { dict = CEL .. 'heart_pumping', clip = 'heart_pumping', loop = true } },
    { id = 'findfish', label = 'Find the fish', cat = 'dances', anim = { dict = CEL .. 'find_the_fish', clip = 'find_the_fish', loop = true } },
    { id = 'chicken', label = 'Chicken', cat = 'dances', anim = { dict = CEL .. 'chicken_taunt', clip = 'chicken_taunt', loop = true } },
    { id = 'jazzhands', label = 'Jazz hands', cat = 'dances', anim = { dict = CEL .. 'jazz_hands', clip = 'jazz_hands', loop = true } },
    { id = 'party', label = 'Party', cat = 'dances', scenario = 'WORLD_HUMAN_PARTYING' },

    -- Actions (scenarios: the game handles props and the exit animation)
    { id = 'smoke', label = 'Smoke', cat = 'actions', scenario = 'WORLD_HUMAN_SMOKING' },
    { id = 'drink', label = 'Drink', cat = 'actions', scenario = 'WORLD_HUMAN_DRINKING' },
    { id = 'coffee', label = 'Coffee', cat = 'actions', scenario = 'WORLD_HUMAN_AA_COFFEE' },
    { id = 'phone', label = 'On the phone', cat = 'actions', scenario = 'WORLD_HUMAN_STAND_MOBILE' },
    { id = 'clipboard', label = 'Clipboard', cat = 'actions', scenario = 'WORLD_HUMAN_CLIPBOARD' },
    { id = 'notes', label = 'Take notes', cat = 'actions', scenario = 'CODE_HUMAN_MEDIC_TIME_OF_DEATH' },
    { id = 'guitar', label = 'Play guitar', cat = 'actions', scenario = 'WORLD_HUMAN_MUSICIAN' },
    { id = 'binoculars', label = 'Binoculars', cat = 'actions', scenario = 'WORLD_HUMAN_BINOCULARS' },
    { id = 'camera', label = 'Take photos', cat = 'actions', scenario = 'WORLD_HUMAN_PAPARAZZI' },
    { id = 'map', label = 'Read a map', cat = 'actions', scenario = 'WORLD_HUMAN_TOURIST_MAP' },
    { id = 'pushups', label = 'Push-ups', cat = 'actions', scenario = 'WORLD_HUMAN_PUSH_UPS' },
    { id = 'situps', label = 'Sit-ups', cat = 'actions', scenario = 'WORLD_HUMAN_SIT_UPS' },
    { id = 'yoga', label = 'Yoga', cat = 'actions', scenario = 'WORLD_HUMAN_YOGA' },
    { id = 'jog', label = 'Jog on the spot', cat = 'actions', scenario = 'WORLD_HUMAN_JOG_STANDING' },
    { id = 'flex', label = 'Flex', cat = 'actions', scenario = 'WORLD_HUMAN_MUSCLE_FLEX' },
    { id = 'cheer', label = 'Cheer', cat = 'actions', scenario = 'WORLD_HUMAN_CHEERING' },
    { id = 'mechanic', label = 'Work on a car', cat = 'actions', scenario = 'WORLD_HUMAN_VEHICLE_MECHANIC' },
    { id = 'weld', label = 'Weld', cat = 'actions', scenario = 'WORLD_HUMAN_WELDING' },
    { id = 'hammer', label = 'Hammer', cat = 'actions', scenario = 'WORLD_HUMAN_HAMMERING' },
    { id = 'clean', label = 'Clean', cat = 'actions', scenario = 'WORLD_HUMAN_MAID_CLEAN' },
    { id = 'leafblower', label = 'Leaf blower', cat = 'actions', scenario = 'WORLD_HUMAN_GARDENER_LEAF_BLOWER' },
    { id = 'fish', label = 'Fish', cat = 'actions', scenario = 'WORLD_HUMAN_STAND_FISHING' },
    { id = 'golf', label = 'Golf swing', cat = 'actions', scenario = 'WORLD_HUMAN_GOLF_PLAYER' },
    { id = 'kneel', label = 'Kneel and inspect', cat = 'actions', scenario = 'CODE_HUMAN_MEDIC_KNEEL' },
    { id = 'think', label = 'Think', cat = 'actions', anim = { dict = 'misscarsteal4@aliens', clip = 'rehearsal_base_idle_director', upper = true, loop = true } },

    -- Poses (loop)
    { id = 'sit', label = 'Sit on the ground', cat = 'poses', scenario = 'WORLD_HUMAN_PICNIC' },
    { id = 'chair', label = 'Sit (chair)', cat = 'poses', scenario = 'PROP_HUMAN_SEAT_CHAIR_MP_PLAYER' },
    { id = 'lean', label = 'Lean', cat = 'poses', scenario = 'WORLD_HUMAN_LEANING' },
    { id = 'leanwall', label = 'Lean on a wall', cat = 'poses', anim = { dict = 'amb@world_human_leaning@male@wall@back@foot_up@idle_a', clip = 'idle_a', loop = true } },
    { id = 'lie', label = 'Lie on your back', cat = 'poses', anim = { dict = 'amb@world_human_sunbathe@male@back@base', clip = 'base', loop = true } },
    { id = 'sunbathe', label = 'Sunbathe', cat = 'poses', scenario = 'WORLD_HUMAN_SUNBATHE_BACK' },
    { id = 'sleep', label = 'Sleep', cat = 'poses', anim = { dict = 'timetable@tracy@sleep@', clip = 'idle_c', loop = true } },
    { id = 'guard', label = 'Stand guard', cat = 'poses', scenario = 'WORLD_HUMAN_GUARD_STAND' },
    { id = 'copidle', label = 'Police idle', cat = 'poses', scenario = 'WORLD_HUMAN_COP_IDLES' },
    { id = 'hangout', label = 'Hang out', cat = 'poses', scenario = 'WORLD_HUMAN_HANG_OUT_STREET' },
    { id = 'impatient', label = 'Impatient', cat = 'poses', scenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
    { id = 'statue', label = 'Statue', cat = 'poses', scenario = 'WORLD_HUMAN_HUMAN_STATUE' },
    { id = 'kneelhands', label = 'Kneel, hands on head', cat = 'poses', anim = { dict = 'random@arrests@busted', clip = 'idle_a', loop = true } },

    -- Props (custom animations with a prop in hand)
    { id = 'box', label = 'Carry a box', cat = 'props', anim = { dict = 'anim@heists@box_carry@', clip = 'idle', upper = true, loop = true },
      prop = { model = 'hei_prop_heist_box', bone = 60309, pos = { 0.025, 0.08, 0.255 }, rot = { -145.0, 290.0, 0.0 } } },
    { id = 'umbrella', label = 'Umbrella', cat = 'props', anim = { dict = 'amb@world_human_drinking@coffee@male@base', clip = 'base', upper = true, loop = true },
      prop = { model = 'p_amb_brolly_01', bone = 57005, pos = { 0.15, 0.005, 0.0 }, rot = { 87.0, -20.0, 180.0 } } },
    { id = 'rose', label = 'Hold a rose', cat = 'props', anim = { dict = 'anim@heists@humane_labs@finale@keycards', clip = 'ped_a_enter_loop', upper = true, loop = true },
      prop = { model = 'prop_single_rose', bone = 18905, pos = { 0.13, 0.15, 0.0 }, rot = { -100.0, 0.0, -20.0 } } },
    { id = 'call', label = 'Phone call', cat = 'props', anim = { dict = 'cellphone@', clip = 'cellphone_call_listen_base', upper = true, loop = true },
      prop = { model = 'prop_npc_phone_02', bone = 28422, pos = { 0.0, 0.0, 0.0 }, rot = { 0.0, 0.0, 0.0 } } },
    { id = 'text', label = 'Texting', cat = 'props', anim = { dict = 'cellphone@', clip = 'cellphone_text_read_base', upper = true, loop = true },
      prop = { model = 'prop_npc_phone_02', bone = 28422, pos = { 0.0, 0.0, 0.0 }, rot = { 0.0, 0.0, 0.0 } } },
    { id = 'beer', label = 'Hold a beer', cat = 'props', anim = { dict = 'amb@world_human_drinking@beer@male@idle_a', clip = 'idle_c', upper = true, loop = true },
      prop = { model = 'prop_amb_beer_bottle', bone = 28422, pos = { 0.0, 0.0, 0.05 }, rot = { 0.0, 0.0, 0.0 } } },
    { id = 'cup', label = 'Hold a cup', cat = 'props', anim = { dict = 'amb@world_human_drinking@coffee@male@idle_a', clip = 'idle_c', upper = true, loop = true },
      prop = { model = 'p_amb_coffeecup_01', bone = 28422, pos = { 0.0, 0.0, 0.0 }, rot = { 0.0, 0.0, 0.0 } } },
    { id = 'notepad', label = 'Notepad', cat = 'props', anim = { dict = 'missheistdockssetup1clipboard@base', clip = 'base', upper = true, loop = true },
      prop = { model = 'prop_notepad_01', bone = 18905, pos = { 0.1, 0.02, 0.05 }, rot = { 10.0, 0.0, 0.0 } } },
    { id = 'touristmap', label = 'Hold a map', cat = 'props', anim = { dict = 'amb@world_human_tourist_map@male@base', clip = 'base', upper = true, loop = true },
      prop = { model = 'prop_tourist_map_01', bone = 28422, pos = { 0.0, 0.0, 0.0 }, rot = { 0.0, 0.0, 0.0 } } },

    -- Shared (both people play their half; the other person must accept)
    { id = 'handshake', label = 'Handshake', cat = 'shared', anim = { dict = 'mp_ped_interaction', clip = 'handshake_guy_a', ms = 3500 },
      partner = { clip = 'handshake_guy_b', distance = 1.0 } },
    { id = 'highfive', label = 'High five', cat = 'shared', anim = { dict = 'mp_ped_interaction', clip = 'highfive_guy_a', ms = 3000 },
      partner = { clip = 'highfive_guy_b', distance = 1.0 } },
    { id = 'hug', label = 'Hug', cat = 'shared', anim = { dict = 'mp_ped_interaction', clip = 'kisses_guy_a', ms = 5000 },
      partner = { clip = 'kisses_guy_b', distance = 1.05 } },
    { id = 'brohug', label = 'Bro hug', cat = 'shared', anim = { dict = 'mp_ped_interaction', clip = 'hugs_guy_a', ms = 4000 },
      partner = { clip = 'hugs_guy_b', distance = 1.05 } },
}

EmoteById = {}
for _, e in ipairs(EmoteList) do EmoteById[e.id] = e end
