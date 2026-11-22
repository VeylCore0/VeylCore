# Medical (`veyl_medical`)

Being downed, EMS revives, first aid and hospital recovery. It replaces the basic death timer in `veyl_spawn`, which switches itself off while `veyl_medical` is running.

```
ensure veyl_medical   # after veyl_inventory, veyl_interact and veyl_target
```

## States

| State | What the player sees | How it ends |
|---|---|---|
| **Downed** | Lying injured. Can look around, talk, use push-to-talk and the phone. **G** calls for help (once a minute). | EMS revive, a first aid kit, or bleeding out after 5 min (`BleedOutSeconds`). |
| **Unconscious** | Lying still. Phone, inventory and targeting are blocked. | EMS revive, or **E** to respawn at Pillbox after 5 min (1 min when no EMS are on duty). |

The state is stored on the character (`metadata.inlaststand` / `metadata.isdead`), so it survives a resource restart. A character who logs out downed or unconscious comes back at the hospital (`veyl_spawn`).

Players in a vehicle stay in their seat.

## Helping someone

Aim at the person (target key):

| Option | Who | Works on | Time |
|---|---|---|---|
| **Revive** | On-duty EMS | Downed or unconscious | 10 s |
| **Help up (first aid kit)** | Anyone with a `first_aid_kit` | Downed only (not unconscious) | 15 s, uses one kit, back to 130 health |
| **Treat injuries** | On-duty EMS | Conscious and hurt | 8 s, full health |

The person being helped sees "Someone is helping you…". The server checks distance, duty, items and timing again when the action finishes. First aid kits are sold in the 24/7 shops for $250.

## Alerts

When someone goes down, every on-duty EMS gets a notification with the street name and a flashing map blip for 90 s. "Call for help" (G) sends it again.

## Hospital

- **Respawn:** placed at the Pillbox entrance at full health. The bill (`RespawnFee`, $500) comes from the bank first, then cash; it is waived if the player has neither. Hunger and thirst are topped up to the `veyl_needs` minimum.
- **Check-in:** the receptionist at Pillbox treats hurt (conscious) players for $250 (`CheckInFee`) after 12 s. Only open while no EMS are on duty (`CheckInMaxEMS`).

## For other resources

Server exports: `IsDown(src)`, `GetState(src)` (`'down'`, `'dead'` or nil), `Revive(src, health)`.
Client exports: `IsDown()`, `GetState()`.
The player state bag `medical` holds the same value and is readable by every client.

Staff `/vrevive` keeps working: clearing the metadata ends the medical state.

Every revive, help-up, treatment, respawn and check-in is written to the audit log.

## Voice

With pma-voice running, a downed player can only whisper (`VoiceRangeDowned`, 1.5 m) and an unconscious player cannot be heard (`VoiceRangeUnconscious`). The normal range comes back when they are revived or respawn. The HUD shows one bar while the range is overridden.

## Death screen

While downed or unconscious, a full-screen overlay replaces the old help text. It never takes the mouse or keyboard: G and E still go to the game.

| State | What it shows |
|---|---|
| **Downed** | "YOU'RE DOWN" over a red vignette that pulses with your heartbeat. The pulse and the heart-monitor trace speed up as you bleed out, and the last 20% turns critical (darker edges, blinking timer). A ring counts down to passing out. **G** calls for help, then shows the cooldown. |
| **Unconscious** | "UNCONSCIOUS", a flatline and a grey, drained screen (`DeathFailMPIn` effect). The ring counts down to respawn, then **E** respawns at the hospital with the fee shown. |
| **Being helped** | The trace turns green and calm, with a progress bar for the revive or help-up. |

Chips under the timer show how many EMS are on duty and whether they were alerted, or that a first aid kit can get you up when no EMS are around. The page is `packages/medical-ui` (built into `veyl_medical/web/dist`).

## Injuries

Every hit of 5+ damage is recorded on the body part it landed on (head, torso, arms, legs) with its cause, and saved on the character (`metadata.injuries`):

| Kind | Caused by | Effect |
|---|---|---|
| Gunshot wound | Bullets | Bleeding +2 |
| Laceration | Knives, bottles, machetes… | Bleeding +1 |
| Fracture | Hard falls and crashes (arms, legs) | — |
| Bruising | Fists, blunt weapons, light falls | — |
| Burn | Fire, explosions | — |

Severity goes from 1 to 4 per part.
- Injuries do not make you limp or shake the screen.
- **Bleeding (1–4):** you lose 2 health every 30 s at level 1, faster at higher levels, until treated.

`/injuries` lists your own. **EMS:** *Check injuries* on a person shows health, bleeding and every injury; *Treat injuries* (and a revive) heals all of them. A hospital respawn or check-in also clears them.

### Items (24/7 shops)

| Item | Effect |
|---|---|
| Gauze ($40) | Bleeding −2 |
| Painkillers ($60) | +10 health |
| Medkit ($450) | +60 health and stops bleeding. Does not fix fractures |

### Beds

On-duty EMS near Pillbox can *Put in hospital bed* a patient: they lie in the first free bed (`Beds` in `config.lua`, set them to your hospital MLO). Check-in treatment also happens in a bed. Patients get up with **E** once they are conscious.

## EMS pay and bills

- Medics are paid to their bank for every finished revive ($150) and treatment ($50) (`Pay`).
- **Send medical bill** (target a person): amount and reason, charged to the patient's bank; the medic keeps 25 % (`Bills.Commission`). Bills up to $5,000.
- Ambulances and the medical supply cabinet are in [DEPARTMENTS.md](DEPARTMENTS.md).
