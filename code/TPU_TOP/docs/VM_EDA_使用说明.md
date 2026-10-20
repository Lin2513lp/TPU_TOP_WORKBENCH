# TPU_TOP 简洁运行方式

共享工程只包含：

```
TPU_TOP/
├── rtl/
├── tb/
├── Makefile
└── tpu_top_cdc.sgdc
```

在虚拟机 Linux 终端进入 `/mnt/hgfs/share/tpu/tpu/TPU_TOP`，执行：

| 指令 | 动作 |
|---|---|
| `make help` | 查看命令 |
| `make license` | 检查许可证服务；默认本地服务未运行时，使用现有许可证文件启动 |
| `make compile` | VCS编译，不运行仿真 |
| `make smoke` 或 `make run` | 编译并运行INT8 4×4自检查Smoke，生成FSDB |
| `make lint` | VCS RTL Lint |
| `make spyglass` | SpyGlass RTL Lint，遇到Error返回失败 |
| `make cdc-setup` | 时钟/复位识别和CDC约束覆盖检查 |
| `make cdc` | 上述两步加结构CDC检查 |
| `make all` | Smoke、VCS Lint、SpyGlass Lint和CDC |
| `make verdi` | 打开已有FSDB/KDB；可在Verdi里选择dut端口加入波形 |
| `make spyglass-gui` | 在虚拟机桌面终端打开RTL Lint工程 |
| `make cdc-gui` | 在虚拟机桌面终端打开结构CDC工程 |

所有编译产物、波形、原始工具日志/报告位于虚拟机本地 `~/tpu_top_runs/TPU_TOP/`，可用 `RUN_DIR=/路径` 改位置。共享目录不生成results、脚本、截图或汇总JSON。没有自动截图、哈希清单或许可证服务管理脚本。

工具和许可证环境需在Linux终端中已配置。当前机器缺少Advanced_CDC功能授权；make cdc / make all会对此返回失败，不能视为CDC已通过。正常Lint Warning不等于编译失败，也不等于零告警签核。

操作说明与工作台保留在本地开发目录，不复制到共享运行目录。

2026-10-20修正：许可证服务重启后未运行会导致VCS Error255。Makefile已内联license目标，编译、Lint和CDC前自动检查服务，必要时启动既有本地lmgrd，不新增脚本、不修改许可证。默认优先使用终端已有许可环境，也可用LICENSE_SERVER显式指定服务器；远程/自定义服务器故障只报错，不尝试本地启动。
