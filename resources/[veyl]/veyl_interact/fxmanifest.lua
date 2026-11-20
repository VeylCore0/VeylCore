fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_interact'
description 'VeylCore interaction API: zones and NPCs with an E-key prompt, distance checks and resource cleanup'
version '0.1.0'

dependencies { 'veyl_core', 'veyl_ui' }

shared_script '@veyl_core/lib/shared.lua'
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
