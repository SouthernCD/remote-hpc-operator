# Operation Recipes

这些模板适用于已确认的目标机器。使用前必须先解析 `${REMOTE_HPC_OPERATOR_CONFIG_DIR:-<skill-root>/references/machines/local}`，读取其中的 `index.md`，再读取对应的 `<machine-id>.md`。

不要把模板里的占位符当作真实值；真实值只能来自目标机器 profile 或脚本配置。

## Connectivity Check

本地到入口节点的最小验证：

```bash
ssh <login_alias> hostname
```

验证当前节点、用户和目录：

```bash
ssh <login_alias> 'hostname && whoami && pwd'
```

如果 profile 声明需要从入口节点继续进入执行节点：

```bash
ssh <login_alias> "ssh <execution_node> hostname"
```

如果 profile 声明单独的联网安装节点：

```bash
ssh <login_alias> "ssh <install_node> hostname"
```

## Robust Remote Script Execution

复杂命令不要堆叠多层引号。只要命令包含多行、变量、管道、重定向、循环、`awk`/`sed`、环境激活或嵌套 SSH，就把业务逻辑作为 stdin script 发送给 `bash -s`。

单跳模板：

```bash
ssh <login_alias> 'bash -s' <<'REMOTE'
set -euo pipefail
cd <work_dir>
<commands>
REMOTE
```

多跳模板：

```bash
ssh <login_alias> "ssh <target_node> bash -s" <<'REMOTE'
set -euo pipefail
cd <work_dir>
<commands>
REMOTE
```

在本 skill 的脚本里，优先使用 `scripts/common.sh` 提供的 helper：

```bash
ssh_target_script "${TARGET}" <<'REMOTE'
set -euo pipefail
cd <work_dir>
<commands>
REMOTE
```

对中等复杂但不需要远程持久脚本文件的操作，可在本地创建或生成脚本后通过 helper 执行：

```bash
scripts/run_remote_script.sh --machine <machine_id> --target <node> --name <label> <<'REMOTE'
set -euo pipefail
cd <work_dir>
<commands>
REMOTE
```

## File Transfer

目标路径应位于目标机器 profile 允许的工作根目录中。不要把需要跨节点使用的结果放到 profile 标记为非共享的临时目录。

常用模板：

```bash
scp local_file <login_alias>:<work_root>/<project>/
```

```bash
rsync -av local_dir/ <login_alias>:<work_root>/<project>/
```

如果后续要在执行节点、联网节点或调度节点上继续使用，确认该路径位于 profile 声明的共享存储中。

## Environment Setup

按目标机器 profile 的软件策略创建或使用环境。不要假设存在管理员权限、模块系统、conda、micromamba 或网络访问。

默认安装顺序：

- 先读目标机器的 software root 索引，复用已有环境。
- 对生信、基因组学、群体遗传、系统发育、统计计算和常见 CLI 工具，优先用 software root 中的 `micromamba` 从 `bioconda` + `conda-forge` 安装。
- 若 micromamba 尚未安装，优先在 software root 下安装 micromamba 本体，再创建环境。
- 只有确认 bioconda/conda-forge 不适用、官方二进制/模块系统也不合适，或用户明确要求时，才源码安装；选择源码安装前要记录原因。

创建项目目录：

```bash
ssh <login_alias> 'mkdir -p <work_root>/<project>'
```

如果 profile 声明需要在联网节点安装软件：

```bash
ssh <login_alias> "ssh <install_node> bash -s" <<'REMOTE'
set -euo pipefail
export MAMBA_ROOT_PREFIX=<software_root>/micromamba-root
<software_root>/micromamba/bin/micromamba create -y \
  -p <software_root>/micromamba-root/envs/<env_name> \
  -c bioconda -c conda-forge \
  <package_specs>
REMOTE
```

如果只是使用已有环境，可在目标执行节点上检查：

```bash
ssh <login_alias> "ssh <execution_node> bash -s" <<'REMOTE'
set -euo pipefail
<environment_list_command>
REMOTE
```

## Batch Job

只有当目标机器 profile 明确声明调度系统时，才使用对应调度命令。不要把一个机器的调度命令套用到另一台机器。

通用提交前检查：

- 作业脚本位于 profile 允许的工作目录中
- 日志目录位于 profile 允许的共享或持久目录中
- 资源请求符合 profile 记录的队列、分区、账户或节点限制

SGE 机器的只读检查命令模板：

```bash
qstat
qhost
qconf -sql
```

最小 SGE 作业脚本模板：

```bash
#!/bin/bash
#$ -cwd
#$ -V
#$ -N <job_name>
#$ -o <work_root>/<project>/logs/$JOB_NAME.$JOB_ID.out
#$ -e <work_root>/<project>/logs/$JOB_NAME.$JOB_ID.err

cd <work_root>/<project>
<run_command>
```

SGE 提交模板：

```bash
qsub <job_script>
```

Slurm 机器的只读检查命令模板：

```bash
sinfo
squeue -u "$(whoami)"
scontrol show partition
```

最小 Slurm 作业脚本模板：

```bash
#!/bin/bash
#SBATCH --job-name=<job_name>
#SBATCH --partition=<partition>
#SBATCH --chdir=<work_root>/<project>
#SBATCH --output=<work_root>/<project>/logs/%x.%j.out
#SBATCH --error=<work_root>/<project>/logs/%x.%j.err

<run_command>
```

Slurm 提交模板：

```bash
sbatch <job_script>
```

Slurm 状态检查模板：

```bash
squeue -u "$(whoami)"
scontrol show job <job_id>
```

## Direct or Interactive Execution

如果 profile 声明某个节点允许直接执行业务任务，可以按 profile 的路径进入：

```bash
ssh <login_alias>
ssh <execution_node>
cd <work_root>/<project>
<activate_environment_command>
```

如果 profile 声明必须通过调度系统获取交互资源，则按该机器的调度说明执行，不要凭空补命令。

## Long-Running Task Tooling

本 skill 自带一组脚本，优先用它们管理长任务，而不是临时手写零散命令。所有脚本都必须显式传入 `--machine <machine_id>`。

- `scripts/start_remote_task.sh`
  - 在目标机器允许的执行节点上启动长任务
  - 自动记录 `stdout.log`、`stderr.log`、`pid.txt`、`status.txt`、`heartbeat.txt`
- `scripts/check_remote_task.sh`
  - 汇总当前运行状态、PID 是否存活、心跳时间、stdout/stderr 尾部输出
- `scripts/diagnose_remote_task.sh`
  - 用启发式方式判断任务可能卡在启动、IO、报错或缓冲输出
- `scripts/submit_sge_job.sh`
  - 仅适用于 `scheduler=sge` 的机器，提交已有 SGE 脚本并记录 `qsub` 输出与 `job_id`
- `scripts/check_sge_job.sh`
  - 仅适用于 `scheduler=sge` 的机器，查询 `qstat -j`、当前队列摘要和节点视图
- `scripts/diagnose_sge_job.sh`
  - 仅适用于 `scheduler=sge` 的机器，帮助判断作业为什么排队、卡在哪类资源约束上

运行目录由机器脚本配置中的 `runs_root` 决定。

启动后使用对应的状态脚本做有限检查。直接任务在 `status=running`、PID 存活，并且心跳或日志显示任务已越过启动阶段时，可以交接；如果程序本身长时间不输出，以进程状态和适合该程序的进度证据判断，不要仅凭空日志判为故障。调度作业先确认 job ID 和队列状态；仍在排队时报告排队并交接，已经开始运行时检查近期日志。无需为等作业开始或完成反复轮询。

交接时记录实际返回值，不填示例值：

- 直接任务：`machine`、`target`、`project`、`run_id`、`run_dir`、`pid.txt` 中的 PID、当前 `status`，以及 `<run_dir>/stdout.log`、`<run_dir>/stderr.log`。后续用 `scripts/check_remote_task.sh --machine <machine_id> --project <project> --run-id <run_id>` 查询。
- SGE 作业：`machine`、`project`、`job_id`、`submit_dir`、作业脚本位置，以及脚本中配置的 stdout/stderr 路径。后续用 `scripts/check_sge_job.sh --machine <machine_id> --job-id <job_id>` 查询；调度作业的 PID 通常不可从提交结果获得。
- 其他调度系统：按目标机器 profile 记录 job ID、队列/分区、脚本与日志路径，并使用该系统的只读状态命令查询。

在最终回复中留下这些标识和查询入口，请用户查看日志或稍后让 agent 根据这些标识重新检查。重新查询时以远程状态为准，不能把上次交接时的状态当作当前状态。

## Troubleshooting

积累常见故障及对应检查项，例如：

- SSH 连接超时
- 权限拒绝
- 在禁止业务运行的节点上误跑任务
- 软件安装失败但当前节点不能联网
- 环境与任务不匹配
- 作业排队过久
- 目录配额不足

排障时先回到目标机器 profile，确认节点角色、目录规则、联网能力和调度系统是否匹配当前操作。
