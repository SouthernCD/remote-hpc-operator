# Machine Index

Copy this file to `local/index.md`, replace every placeholder, and keep the
result private. Do not treat this example as a usable machine definition.

| Machine ID | Name | Access entry | Tags | Profile |
| --- | --- | --- | --- | --- |
| `<machine_id>` | `<descriptive_name>` | `<ssh_alias_or_local>` | `<scheduler_and_access_tags>` | [`<machine_id>.md`](<machine_id>.md) |

For each machine:

1. Copy `profile.example.md` to `local/<machine_id>.md`.
2. Add the machine to `local/index.md`.
3. For a remote machine that will use the SSH or scheduler scripts, add the matching fields to `local/config.tsv`. Local machines are profile-only because those scripts require SSH.
