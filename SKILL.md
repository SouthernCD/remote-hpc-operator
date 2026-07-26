---
name: remote-hpc-operator
description: Use this skill when the user needs the agent to access, inspect, transfer files to, submit jobs to, or troubleshoot one of their documented remote HPC or workstation environments over SSH, login nodes, schedulers, and remote development workflows.
---

# Remote HPC Operator

## Machine Selection

- 将 private config directory 解析为 `${REMOTE_HPC_OPERATOR_CONFIG_DIR:-<skill-root>/references/machines/local}`。
- 每次远程任务都先读取 private config directory 中的 `index.md`。
- 如果 private config directory、`index.md`、目标 profile 或 `config.tsv` 不存在，停止并说明缺少哪项配置。可参考 `references/machines/*.example.*` 创建私有配置，但绝不能把示例当作真实机器使用。
- 不存在默认机器。若用户没有在当前请求中明确指定机器，先询问用户选择哪台机器。
- 用户指定机器后，读取该机器的 profile，再继续执行任务。
- 不要把任意 profile 中的节点、目录、联网能力、调度系统或安全规则当作其他机器的普适事实。
- 如果机器索引和机器 profile 冲突，以 profile 为准，并在输出中说明冲突。
- 将真实账号、主机、路径、认证方式和集群拓扑仅保存在 private config directory；不要写入公开模板或其他可跟踪文件。

## Operating Principles

- 默认优先只读探索：先看连接配置、远程身份、目录、队列、节点角色，再做写操作或提交作业。
- 登录节点、管理节点、专用节点、联网节点、计算节点等角色必须从目标机器 profile 中确认。
- 工作目录、共享存储、临时目录、环境目录和日志目录必须从目标机器 profile 中确认。
- 调度系统和命令必须从目标机器 profile 中确认；不要凭经验假设是 Slurm、SGE、PBS 或 LSF。
- 软件安装前先确认目标机器的联网节点、包管理策略和用户权限。
- 生信、群体遗传、基因组学、系统发育、统计计算和常见 CLI 工具安装时，默认优先使用目标机器 software root 中的 `micromamba`，按 `bioconda` + `conda-forge` 渠道解决依赖；只有在确认目标软件不在合适 channel、版本不可用、包损坏、许可证/性能要求不适合 conda 包，或用户明确要求源码构建时，才转向源码安装。
- 软件、环境、依赖、包管理器或已有工具检查任务，必须按目标机器 profile 的 software root 约定执行；不要默认把可复用软件装到 scratch 或项目目录。
- 遇到需要密码、MFA、硬件令牌或人工确认的步骤，暂停在明确断点，不要伪造结果。
- 涉及大规模作业、批量删除、覆盖远程文件、取消作业等高影响操作前，先明确风险。

## Software Root Convention

- 每台机器 profile 的 `Software and Environment Policy` 必须说明 agent-managed software root 的状态。
- 若任务涉及软件安装、环境选择、依赖检查、包管理器、已有工具查找或生信工具复用，读取目标机器 profile 后先检查该机器的 software root 约定。
- 若 profile 声明了 software root，先读 `<software_root>/AGENT_SOFTWARE.md`；只有当某个环境可能相关时，再按索引读取对应的环境详情文件或运行环境检查命令。
- 新安装的可复用软件、`micromamba`、conda/mamba root、长期环境、激活脚本和环境说明默认放入 software root，除非用户明确指定其他位置。
- 新建软件环境的默认路径是 micromamba environment：先复用或安装 `<software_root>/micromamba/bin/micromamba`，设置 `MAMBA_ROOT_PREFIX=<software_root>/micromamba-root`，优先从 `bioconda` 和 `conda-forge` 创建环境。源码安装是 fallback，而不是首选路径。
- 每个 agent-managed 长期环境都必须有可 source 的激活脚本、环境详情文件和 `AGENT_SOFTWARE.md` 索引条目。最小必需文件是 `<software_root>/activate_<env_name>.sh`、`<software_root>/env-docs/<env_name>.md` 和顶层索引中的对应记录。
- 激活脚本必须自包含：用 `<software_root>/micromamba/bin/micromamba` 绝对路径加载 shell hook，不能依赖用户 `PATH`、shell 启动文件，或 `<software_root>/micromamba/etc/profile.d/micromamba.sh` 存在；创建或修复后用 `bash --noprofile --norc -lc 'source <script> && echo "$CONDA_PREFIX"'` 验证。
- 如果检查到已有环境缺少激活脚本、环境详情或索引条目，不要继续把缺失状态当作正常状态复用；先补齐 metadata，或在只读任务中明确报告缺口和建议的补齐命令。
- 选择源码安装前，必须在输出或记录中说明为什么 micromamba/bioconda 不适用，并尽量把源码构建产物也隔离到 software root 下，而不是混入项目目录。
- `<software_root>/bin` 是所有已配置 software root 的通用快捷启动目录，用于放置用户可直接加入 `PATH` 的可执行 wrapper。
- 当用户要求“快捷启动”、`shortcut launcher`、`command wrapper` 或类似能力时，在 `<software_root>/bin` 创建对应可执行入口；wrapper 应调用该机器 software root 中的激活脚本或真实可执行文件。
- 创建快捷启动后，告诉用户应把哪个具体 `<software_root>/bin` 加入 `PATH`；除非用户明确要求，不要修改用户的 `.bashrc`、`.zshrc`、`.bash_profile` 或其他 shell 启动文件。
- 项目运行文件、日志、临时脚本、下载的任务数据和 run metadata 仍放入 profile 声明的 operation/work root，不要混入 software root。
- 如果 profile 把 software root 标记为 pending、not configured 或 unknown，不要自行选择长期安装目录；先询问用户或只做一次性临时环境安排。
- 通用目录组织见 [references/software-environments.md](references/software-environments.md)。

## Workflow

1. 解析 private config directory 并读取其中的机器索引，确认用户本次要操作的机器。
2. 若机器未明确，询问用户选择；不要自行使用上次机器或默认机器。
3. 读取目标机器 profile，确认：
   - SSH 入口和认证方式
   - 登录节点、执行节点、联网节点和禁止业务运行的节点
   - 工作目录、共享存储和临时目录规则
   - 调度系统、队列或直接执行策略
   - 软件环境、模块系统或用户态包管理策略
   - agent-managed software root 及其索引文件状态
4. 用最小化只读命令验证链路是否通。
5. 根据任务类型选择路径：
   - 连接和环境检查：保持只读，报告已验证事实
   - 文件传输：先确认目标路径和覆盖行为
   - 直接执行：先确认目标节点允许业务任务
   - 调度作业：先确认调度系统和脚本位置
   - 软件检查或安装：先确认联网能力、software root、`AGENT_SOFTWARE.md` 和是否已有可复用环境
6. 输出时明确区分：
   - 已验证的信息
   - 从机器 profile 读取的信息
   - 基于当前上下文推断的信息
   - 需要用户补充或手动完成的步骤

## Command Strategy

- 搜索本地配置时，优先查看 `~/.ssh/config`、项目里的连接脚本、README、作业脚本。
- 搜索文本优先用 `rg`。
- 对远程命令保持最小化和可审计，避免一次执行过长的链式命令。
- SSH quoting avoidance protocol:
  - 只有非常短、只读、单层的检查命令可以直接内联到 `ssh <host> '<cmd>'`，例如 `hostname`、`whoami`、`pwd`、`ls -ld <path>`。
  - 一旦命令包含多行、变量展开、管道、重定向、循环、函数、`awk`/`sed`、环境激活、嵌套引号，或需要从登录节点继续 SSH 到目标节点，默认必须使用 quoted heredoc / stdin script，不要继续加深 shell quoting。
  - 单跳复杂命令使用：
    ```bash
    ssh <login_alias> 'bash -s' <<'REMOTE'
    set -euo pipefail
    cd <work_dir>
    <commands>
    REMOTE
    ```
  - 多跳复杂命令只在本地命令中表达连接层，把业务脚本从 stdin 送到最终节点：
    ```bash
    ssh <login_alias> "ssh <target_node> bash -s" <<'REMOTE'
    set -euo pipefail
    cd <work_dir>
    <commands>
    REMOTE
    ```
  - 编写 skill 脚本时，使用 `scripts/common.sh` 中的 `ssh_target_script <target>` 从 stdin 执行远程脚本；保留 `ssh_target` 只用于短命令。
  - 中等复杂、一次性、无需远程留档的操作可用 `scripts/run_remote_script.sh --machine <machine_id> --target <node> --name <label> < script.sh`。
  - 长任务、可复用任务、会修改远程状态或需要审计记录的任务，优先使用 `scripts/start_remote_task.sh`、调度脚本或明确保存到远程工作目录的脚本文件。
- 优先使用不会修改状态的命令，例如：
  - `ssh -G <login_alias>`
  - `ssh <login_alias> hostname`
  - `whoami`
  - `pwd`
  - 目标机器 profile 中列出的调度只读检查命令
- 文件传输或远程执行前，先确认目标路径和覆盖行为。
- 如果任务结果需要跨节点复用，只能使用目标机器 profile 中声明为共享的存储。

## Safety Boundaries

不要在未经确认的情况下：

- 在登录节点或禁止业务运行的节点执行业务命令
- 提交高资源占用作业
- 取消正在运行的关键作业
- 覆盖远程结果目录
- 删除远程文件
- 在 profile 允许范围之外创建项目环境
- 混用彼此无关任务的软件环境

若命令失败，要优先区分：

- 本地网络问题
- SSH 配置问题
- 认证问题
- 机器权限问题
- 调度系统或队列限制
- 节点联网能力限制
- 远程环境缺失

## References

根据任务类型按需读取，不要一次性全部加载：

- 机器索引：见 private config directory 中的 `index.md`
- 每台机器的详细说明：见 private config directory 中的 `<machine-id>.md`
- 私有配置模板：见 `references/machines/index.example.md`、`references/machines/profile.example.md` 和 `references/machines/config.example.tsv`
- 软件环境目录组织：见 [references/software-environments.md](references/software-environments.md)
- 通用操作模板与命令约定：见 [references/operation-recipes.md](references/operation-recipes.md)
- 长任务启动、监控、诊断脚本：见 [scripts/](scripts/)

## Expected Output Style

- 用简洁步骤说明 agent 正在验证什么。
- 给出可直接执行的命令时，尽量一次只给一组清晰命令。
- 如果信息不足，明确指出缺什么，不要模糊假设。
- 如果某一步依赖用户交互，例如 MFA、密码输入、浏览器登录，要显式停下来。
- 涉及节点选择时，明确写出该节点角色来自哪个机器 profile。
