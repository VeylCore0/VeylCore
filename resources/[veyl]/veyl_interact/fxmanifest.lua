fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_interact'
description 'VeylCore interaction API (forwards to veyl_target; E-key fallback) with per-resource cleanup'
version '0.3.0'

dependencies { 'veyl_core', 'veyl_ui' }

shared_scripts { '@veyl_core/lib/shared.lua', 'config.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
