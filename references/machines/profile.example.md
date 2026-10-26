# Machine: `<machine_id>`

Keep the completed profile in `references/machines/local/` or in the private
directory selected by `REMOTE_HPC_OPERATOR_CONFIG_DIR`. Never commit real
accounts, hosts, paths, authentication details, or cluster topology.

## Quick Facts

- Machine ID: `<machine_id>`
- Cluster name: `<descriptive_name>`
- Access: `<ssh_or_local>`
- Scheduler: `<Slurm_SGE_PBS_LSF_or_none>`
- Login host alias: `<ssh_alias_or_not_applicable>`
- Login node hostname: `<login_node_or_not_applicable>`
- Username: `<username>`

## Authentication

For `access=local`, record that SSH and remote authentication do not apply.

- SSH access: `ssh <ssh_alias>`
- Login mode: `<passwordless_password_MFA_or_other>`
- Jump host requirement: `<requirement>`
- Browser-based login requirement: `<requirement>`

## Access Path

For `access=local`, record direct local shell access instead of the SSH path below.

```text
local machine -> ssh <ssh_alias> -> <login_node>
```

Document any additional hops without exposing credentials.

## Node Roles

For `access=local`, document that there are no separate login or compute nodes.

- `<login_node>`: `<allowed_management_and_submission_roles>`
- `<execution_node_or_scheduler>`: `<allowed_execution_roles>`
- `<installation_node>`: `<network_and_installation_roles>`

## Directory Conventions

- Allowed working root: `<remote_work_root>`
- Runs root for agent tooling: `<runs_root>`
- Software install root: `<software_root_or_pending>`
- Shared storage policy: `<policy>`
- Temporary storage policy: `<policy>`

## Scheduler

- Scheduler: `<scheduler>`
- Read-only status commands: `<commands>`
- Submission policy: `<policy>`
- Execution policy: `<profile_controlled_or_scheduler_only>`
- Default queue or partition: `<value_or_unknown>`

## Software and Environment Policy

- Internet-capable node: `<node_or_none>`
- Compute-node internet access: `<yes_no_or_unknown>`
- Agent-managed software root: `<software_root_or_pending>`
- Environment index: `<software_index_or_pending>`

## Machine-Specific Recipes

Connectivity check:

```bash
ssh <ssh_alias> 'hostname && whoami && pwd'
```

Add only the minimal commands needed to operate this machine safely.

## Safety Notes

- Do not run business workloads on `<forbidden_nodes>`.
- Do not write outside `<allowed_roots>` without explicit user approval.
- Do not assume node roles, networking, or scheduler behavior not documented here.
