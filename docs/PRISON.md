# Prison (`veyl_prison`)

Sentences at Bolingbroke Penitentiary that persist across logouts and restarts, and end only when served or released.

```
ensure veyl_prison   # after veyl_core and veyl_interact
```

## Sentencing

- **From the MDT:** a person's profile → **Sentence** (months and charges).
- **In person:** `/jail <id> <months> <charges>`, standing within 10 m.

Both need an on-duty officer (`PoliceJobs`) or staff (`veyl.prison.manage` / `veyl.admin`). The person must be in the city. They are uncuffed and placed in the yard.

## Serving

- **1 month = 1 minute online** (`SecondsPerMonth`). Time does not pass while logged out.
- The time left shows at the top of the screen.
- **Yard work:** three spots in the yard. Each finished job (15 s) takes 1 month off, once every 45 s. It never takes the sentence below 1 month: the last month is always served.
- **No escape:** leaving the grounds (`Grounds`), dying and respawning at the hospital, or reconnecting all put the prisoner back inside.

## Release

- Automatically when the time runs out, at the gate (`Release`).
- Early by an on-duty officer or staff: `/release <id>`.

Every sentence and release is kept in `veyl_prison_history` (who sentenced, who released) and the audit log. The current sentence is in `veyl_prison_sentences` and mirrored to `metadata.jailtime`.

## For other resources

Server exports: `Sentence(officerSrc, citizenid, months, reason)`, `GetSentence(citizenid)`, `Release(citizenid, by)`.

## More

- **Belongings:** everything except ID and licence cards (`KeepItems`) is taken on entry and handed back on release. If they are released while offline, or something does not fit, they get it at their next login.
- **Canteen:** a free meal (sandwich and water) every 10 min.
- **Offline time** (`CountOffline = true`): the sentence also runs down while logged out.
- **Escapes** (`AllowEscape = true`): leaving the grounds is an escape instead of being put back. Police get an urgent "Prison break" dispatch call, the MDT gets a warrant, and the remaining time waits: the next sentence starts fresh with their belongings still kept.
