# Transitional ox profile (v0.2)

This folder holds the ox_inventory framework bridge used by the **transitional** profile (repo v0.2, commit `9715b7a`),
where ox_lib, ox_target and ox_inventory provided the library, targeting and item storage.

The current **native** profile replaces them with `veyl_lib`, `veyl_target` and the `veyl_inventory` engine.
Do not install this bridge alongside the native `veyl_inventory`: only one inventory may own a character's items.
Moving existing ox inventories to the native engine requires the converter planned in phase 7
(`tools/migrate-inventory/`, not built yet).
