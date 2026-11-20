fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_interact'
description 'VeylCore interaction API: zones, NPCs and entities via ox_target, with an E-key fallback and per-resource cleanup'
version '0.2.0'

dependencies { 'veyl_core', 'veyl_ui' }

shared_scripts { '@veyl_core/lib/shared.lua', 'config.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
