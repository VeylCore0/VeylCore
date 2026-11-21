fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_hud'
description 'VeylCore HUD: status, voice, money, compass/street, minimap frame and vehicle display (passive NUI)'
version '0.4.0'

dependencies { 'veyl_lib', 'veyl_core' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
client_scripts { '@veyl_core/lib/client.lua', '@veyl_core/modules/playerdata.lua', 'client.lua' }

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
