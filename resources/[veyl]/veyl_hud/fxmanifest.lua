fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_hud'
description 'VeylCore HUD: health, armor, needs, stamina, oxygen, voice, money and vehicle speed/fuel'
version '0.2.0'

dependency 'veyl_core'

shared_script '@veyl_core/lib/shared.lua'
client_scripts { '@veyl_core/lib/client.lua', '@veyl_core/modules/playerdata.lua', 'client.lua' }

ui_page 'web/index.html'
files { 'web/index.html', 'web/style.css', 'web/app.js' }
