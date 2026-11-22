# Emotes (`veyl_emotes`)

A searchable emote menu with favourites, props and shared emotes.

```
ensure veyl_emotes   # after veyl_core and veyl_ui
```

## Using it

| Key / command | What it does |
|---|---|
| **F3** | Open or close the emote menu (a side panel: you can keep walking; typing in search pauses movement) |
| **X** | Stop the current emote |
| `/e <name>` | Play an emote by name, e.g. `/e wave`. `/e` on its own opens the menu |
| `/emotes`, `/emotecancel` | Same as F3 / X |

Both keys can be rebound in Settings → Key Bindings → FiveM. Every row in the menu shows its `/e` name.

- **Search** matches the name and the `/e` name.
- **Favourites (★):** star an emote to keep it on the first tab. Up to 20 per character, saved on the player's computer.
- **Props:** some emotes put an item in your hand (box, umbrella, phone, cup…). Other players see it.
- **Shared** emotes (handshake, high five, hug, bro hug) ask the person standing nearest to you (within 3 m). They get an Accept / Decline prompt for 20 s. On accept, they are placed facing you and you both play your half.

Emotes stop by themselves when you ragdoll, get in a vehicle or go down. They cannot be started while downed, restrained, swimming, falling or in a vehicle.

## The list

About 90 emotes in six groups: gestures, dances, actions, poses, props and shared. They are all base-game animations and scenarios, defined in `shared/emotes.lua`. To add one:

```lua
{ id = 'mywave', label = 'My wave', cat = 'gestures', anim = { dict = 'anim@mp_player_intcelebrationmale@wave', clip = 'wave', upper = true, ms = 3000 } },
{ id = 'mylean', label = 'My lean', cat = 'poses', scenario = 'WORLD_HUMAN_LEANING' },
```

`upper = true` plays on the upper body only (you can walk). `loop = true` keeps playing until stopped; otherwise `ms` is the length.

## For other resources

Client exports: `Play(id)`, `Stop()`, `IsPlaying()`.
