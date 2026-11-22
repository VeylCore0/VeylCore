# Departments (`veyl_departments`)

Vehicle garages and equipment lockers for on-duty police and EMS.

```
ensure veyl_departments   # after veyl_vehicles, veyl_inventory, veyl_interact and veyl_target
```

| Point | What it does |
|---|---|
| **Department vehicles** (Mission Row back lot, Pillbox) | Pick a vehicle; it spawns with keys and you are placed in it. Vehicles are rank-locked (`grade`). One each: taking another returns the first |
| **Equipment locker / Medical supplies** | Free kit for the shift (radio, flashlight, first aid, gauze, door ram for police rank 1+; medkits, gauze, painkillers… for EMS). Restocks every 10 min per person |
| **Return to garage** (target a department vehicle) | Within 25 m of your garage |

Department vehicles are also returned when you go off duty or leave. Plates start with the department prefix (`LSPD`, `EMS`). Everything is in `config.lua`: vehicles and ranks, locker contents, locations.
