# Boss menus (`veyl_management`)

Bosses manage their job or gang from one screen: employee list, hiring, promotions, demotions and firing.

```
ensure veyl_management   # after veyl_core, veyl_ui and veyl_interact
```

## Who is a boss

Any grade marked `isboss = true` in `veyl_core/shared/jobs.lua` or `gangs.lua`. A character can be a boss of several jobs; the menu asks which one.

Bosses can only:

- give ranks **below** their own (when hiring, promoting or demoting);
- change or remove members ranked **below** them.

Two bosses of the same rank cannot fire each other. Staff change the top of a group with the core commands.

## Opening the menu

| Group | How |
|---|---|
| Job | The **Boss menu** spot at the job's office (`Offices` in `config.lua`), or `/bossmenu` while standing there. Set `JobMenuAnywhere = true` to allow `/bossmenu` anywhere. |
| Gang | `/gangmenu`, anywhere. |

The office spots shipped in the config are for police (Mission Row), EMS (Pillbox) and LS Customs (Burton). Move them to match your MLOs.

## What the menu shows

- **Employees / Members:** everyone in the group, online or not, with their rank and whether they are on duty. "Side job" means it is not their main job. Change a rank with the drop-down, or fire someone (asks first).
- **Hire / Recruit:** people within 5 m (`HireDistance`). Pick a starting rank and send an offer. The other person sees an Accept / Decline prompt and has 30 s (`OfferSeconds`) to answer. Names are not shown until they accept.

When someone accepts a job, it becomes their main job only if they were unemployed; otherwise they are told to switch with `/jobs`. A gang can only be joined by someone who is not already in one.

Every offer, hire, rank change and firing is written to the audit log.

## Not included yet

Business bank accounts (society funds) arrive with the Businesses milestone.
