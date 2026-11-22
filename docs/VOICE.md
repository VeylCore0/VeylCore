# Voice (pma-voice)

VeylCore uses [pma-voice](https://github.com/AvarianKnight/pma-voice) for proximity voice and phone calls. The txAdmin recipe downloads it and starts it for you.

```
ensure pma-voice                  # before veyl_hud: the HUD detects it once at start
setr voice_useNativeAudio true    # native 3D audio
setr voice_enableUi 0             # pma-voice's own overlay is off: the VeylCore HUD shows talking and range
```

OneSync must be on (pma-voice requires it).

## Version

The last tagged pma-voice release (v6.6.2) is from 2022, so the recipe pins a commit of its maintained `main` branch: `6c9d96ed7a02e30912f1a0ce92629bf9afbbca8c` (June 2026, reports version 7.0.1). Update the `ref` in `recipe.yaml` to move to a newer commit.

## Controls (pma-voice defaults)

| Key | Action |
|---|---|
| **N** | Push to talk (the FiveM voice key; players can rebind it in Settings → Key Bindings → FiveM) |
| **F11** | Cycle range: whisper, normal, shout |

With native audio the ranges are 1.5 m, 3 m and 6 m (pma-voice's native-audio defaults).

## What uses it

| Resource | How |
|---|---|
| `veyl_hud` | Mic icon lights up while you talk; the bars show your range (whisper 2, normal 3, shout 4; one bar when another resource has overridden it). |
| `veyl_phone` | Calls put both people on a private pma-voice call channel (`ChannelBase + call id`). Without pma-voice the dialler says calls need a voice resource. See [PHONE.md](PHONE.md). |
| `veyl_medical` | Downed players can only whisper; unconscious players cannot be heard. See [MEDICAL.md](MEDICAL.md). |
| `veyl_apartments` | Teleport-mode homes use routing buckets; pma-voice keeps voice inside each bucket automatically. |

Radios are not part of VeylCore yet. pma-voice's radio support is left at its default and does nothing until a radio resource sets channels.
