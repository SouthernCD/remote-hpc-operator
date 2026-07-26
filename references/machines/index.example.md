# Machine Index

Copy this file to `local/index.md`, replace every placeholder, and keep the
result private. Do not treat this example as a usable machine definition.

| Machine ID | Name | SSH entry | Tags | Profile |
| --- | --- | --- | --- | --- |
| `<machine_id>` | `<descriptive_name>` | `<ssh_alias>` | `<scheduler_and_access_tags>` | [`<machine_id>.md`](<machine_id>.md) |

For each machine:

1. Copy `profile.example.md` to `local/<machine_id>.md`.
2. Add the machine to `local/index.md`.
3. Add the matching script fields to `local/config.tsv`.
