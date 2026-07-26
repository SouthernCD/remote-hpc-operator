# Agent-Managed Software Environments

这个文件定义各台机器 software root 的通用组织方式。真实路径必须来自目标机器 profile，不要把某一台机器的路径推广到另一台机器。

## Directory Layout

在声明了 software root 的机器上，默认按以下结构组织：

```text
<software_root>/
  AGENT_SOFTWARE.md
  micromamba/
    bin/micromamba
  micromamba-root/
    envs/<env_name>/
  activate_<env_name>.sh
  bin/
    <command>
  env-docs/
    <env_name>.md
  manifests/
    <env_name>.*
```

## File Roles

- `<software_root>/AGENT_SOFTWARE.md`: 顶层索引。只写环境用途、激活入口、详情文件路径和少量关键约束，避免 agent 一次读入完整包列表。
- `<software_root>/micromamba/bin/micromamba`: 默认 agent-managed `micromamba` 可执行文件位置。
- `<software_root>/micromamba-root`: 默认 `MAMBA_ROOT_PREFIX`。
- `<software_root>/micromamba-root/envs/<env_name>`: 默认环境实际位置。
- `<software_root>/activate_<env_name>.sh`: 必需激活入口。脚本应设置 `MAMBA_ROOT_PREFIX`，用 `<software_root>/micromamba/bin/micromamba` 的绝对路径加载 shell hook，并按绝对路径激活环境。不要依赖用户 shell 启动文件、`PATH` 中已有 `micromamba`，或 `<software_root>/micromamba/etc/profile.d/micromamba.sh` 存在。
- `<software_root>/bin/<command>`: 用户快捷启动入口。用于放置小型 executable wrapper，让用户把 `<software_root>/bin` 加入 `PATH` 后直接调用命令。
- `<software_root>/env-docs/<env_name>.md`: 单个环境详情。只有当该环境与当前任务相关时才读取。
- `<software_root>/manifests/<env_name>.*`: 可选包清单、安装记录、`micromamba env export` 或其他重建材料。

## Agent Behavior

- 遇到软件相关任务时，先读目标机器 profile，再读 `AGENT_SOFTWARE.md`。
- 优先复用索引中已有环境；只有确认没有合适环境时才考虑新建环境。
- 新建长期环境时，默认使用 `<software_root>/micromamba/bin/micromamba` 创建环境，放入 `<software_root>/micromamba-root/envs/<env_name>`，并新增或更新激活脚本、环境详情和索引条目。激活脚本必须是自包含的可 source 脚本，能在 `bash --noprofile --norc -lc 'source <script> && echo "$CONDA_PREFIX"'` 中通过。
- 复用已有长期环境前，必须确认它在顶层索引中登记，并且存在可 source 的 `<software_root>/activate_<env_name>.sh` 与 `<software_root>/env-docs/<env_name>.md`。如果环境目录存在但这些文件缺失，优先补齐 metadata，再把该环境作为可复用环境使用。
- 补齐旧环境 metadata 时，不要重装环境；根据真实环境路径创建激活脚本、记录主要用途/关键包/创建或发现时间/维护注意事项，并更新 `AGENT_SOFTWARE.md`。
- 对生信、基因组学、群体遗传、系统发育、统计计算和常见 CLI 软件，安装优先级是：
  1. 复用 `AGENT_SOFTWARE.md` 中已有的合适 micromamba 环境。
  2. 用 micromamba 从 `bioconda` + `conda-forge` 创建或扩展环境。
  3. 如果 bioconda/conda-forge 没有合适版本，再检查官方二进制 release、容器或模块系统。
  4. 只有上述路径不适用、用户明确要求，或目标软件确实需要本地编译时，才源码安装。
- 选择源码安装前，记录 micromamba/bioconda 不适用的原因，例如包不存在、版本不满足、包损坏、许可证限制、性能需求或编译选项需求。
- 使用 micromamba 创建环境时，默认 channel 顺序为 `-c bioconda -c conda-forge`；如涉及非生信通用包，可只用 `conda-forge` 或按软件官方说明调整 channel，但要在环境详情中记录原因。
- 如果 `<software_root>/micromamba/bin/micromamba` 不存在，优先在 software root 下安装 micromamba 本体，再继续创建环境；不要因为系统没有 conda/mamba 就直接改为源码安装。
- 当用户要求“快捷启动”、`shortcut launcher`、`command wrapper` 或类似能力时，创建 `<software_root>/bin/<command>`，并在 `AGENT_SOFTWARE.md` 和相关 `env-docs/` 条目中记录 launcher 路径。
- 快捷启动 wrapper 应保持小而可审计：source 对应的 `activate_<env_name>.sh` 或其他激活入口，再运行真实命令。
- wrapper 转发参数时使用 `"$@"`，不要使用 `$*`；适合直接移交进程时优先使用 `exec`。
- 为避免 `<software_root>/bin` 在 `PATH` 前置后发生自递归，wrapper 应在激活后通过绝对路径调用真实可执行文件，例如 `${CONDA_PREFIX}/bin/<command>`。
- 创建快捷启动后，只提示用户自行加入 `export PATH="<software_root>/bin:$PATH"`；除非用户明确要求，不要修改 shell 启动文件。
- 不要把任务输出、日志、临时脚本、下载的工作数据或 run metadata 放在 software root；这些内容应放入目标机器 profile 声明的 operation/work root。
- 如果 software root 未配置，除非用户明确指定，否则不要为该机器创建新的长期软件目录。

## Micromamba Environment Example

创建或更新长期环境时，先替换真实 `<software_root>` 和 `<env_name>`，再按目标机器 profile 的联网节点执行：

```bash
export MAMBA_ROOT_PREFIX=<software_root>/micromamba-root
<software_root>/micromamba/bin/micromamba create -y \
  -p <software_root>/micromamba-root/envs/<env_name> \
  -c bioconda -c conda-forge \
  <package_specs>
```

激活脚本应使用绝对路径，并避免改变调用者 shell 的 `set` 选项：

```bash
#!/usr/bin/env bash
export MAMBA_ROOT_PREFIX=<software_root>/micromamba-root
_MICROMAMBA=<software_root>/micromamba/bin/micromamba
if [ ! -x "$_MICROMAMBA" ]; then
  echo "micromamba not found or not executable: $_MICROMAMBA" >&2
  return 1 2>/dev/null || exit 1
fi
eval "$("$_MICROMAMBA" shell hook --shell bash)"
micromamba activate <software_root>/micromamba-root/envs/<env_name>
```

不要写成 `source <software_root>/micromamba/etc/profile.d/micromamba.sh`，因为 standalone micromamba 安装不一定提供这个文件。也不要在 shell hook 之前直接调用裸 `micromamba activate`；用户的 `PATH` 和 shell init 状态不可假设。

创建或修复激活脚本后，至少用下面的形式验证一次：

```bash
bash --noprofile --norc -lc 'source <software_root>/activate_<env_name>.sh && echo "$CONDA_PREFIX" && command -v <representative_tool>'
```

## Launcher Example

当用户要求在某台机器上安装 `gemma` 并创建快捷启动时，先按目标机器 profile 确认真实 `<software_root>`，安装或复用对应环境，然后创建类似下面的 wrapper：

```bash
#!/usr/bin/env bash
set -euo pipefail

source <software_root>/activate_gemma_latest.sh

if [[ -n "${CONDA_PREFIX:-}" && -x "${CONDA_PREFIX}/bin/gemma" ]]; then
  exec "${CONDA_PREFIX}/bin/gemma" "$@"
fi

printf 'gemma launcher error: activated environment does not expose $CONDA_PREFIX/bin/gemma\n' >&2
exit 127
```
