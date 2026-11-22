# MDT (`veyl_mdt`)

The police computer. On-duty officers (`Jobs` in `config.lua`, default `police`) open it with **F10** or `/mdt`.

```
ensure veyl_mdt   # after veyl_core and veyl_ui; veyl_police and veyl_prison add citations and sentencing
```

## Pages

| Page | What it shows |
|---|---|
| **Dashboard** | Active warrants, stolen / BOLO vehicles and the latest reports |
| **People** | Search by name, citizen ID or phone number. A profile shows date of birth, phone, job, licences, vehicles, citations, warrants, reports the person appears in, officer notes, and the prison sentence if they are serving one |
| **Vehicles** | Search by plate (partial plates list matches). Shows model, owner and status. Flag a plate **stolen** or **BOLO** with notes; unregistered plates can be flagged too |
| **Reports** | Incident, arrest, traffic and other reports: title, text and the people involved (suspect, victim, witness, officer). Search by title, text or number |

From a profile an officer can:
- **Issue a warrant** (reason), and mark warrants served or cancelled;
- **Sentence** the person (months and charges) when `veyl_prison` is running;
- edit the shared **officer notes**.

## Data

| Table | Holds |
|---|---|
| `veyl_mdt_reports`, `veyl_mdt_report_people` | Reports and who was involved |
| `veyl_mdt_warrants` | Warrants (active, served, cancelled) |
| `veyl_mdt_vehicle_flags` | Stolen / BOLO flags and notes per plate |
| `veyl_mdt_profiles` | Officer notes per person |

Citations come from `veyl_police` (`veyl_police_citations`). Licences come from the character (`metadata.licences`), live for online players.

Every note, warrant, flag, report and sentence is written to the audit log.

## Penal code, roster and licences

- **Penal code** (`Charges` in `config.lua`, 31 charges in six groups): the *Penal code* page lists them. On a profile, **Charges** opens a picker (up to 5 counts each) that totals the fine and prison months, then **Issue fine** (a citation, also for people who are not in the city) or **Send to prison** (optionally with the fine).
- **Reports** have a charges list with running totals.
- **Roster:** every on-duty officer with callsign and dispatch status.
- **Licences:** officers at `LicenceGrade` (2) or above click a licence on a profile to grant or revoke it, online or offline.
- **Check ID** on a person (police target) opens their profile directly.
