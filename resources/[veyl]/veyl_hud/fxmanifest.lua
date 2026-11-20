fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_hud'
description 'VeylCore HUD: health, armor, needs, stamina, oxygen, money and vehicle speed/fuel'
version '0.1.0'

dependency 'veyl_core'

shared_script '@veyl_core/lib/shared.lua'
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }

ui_page 'web/index.html'
files { 'web/index.html', 'web/style.css', 'web/app.js' }
