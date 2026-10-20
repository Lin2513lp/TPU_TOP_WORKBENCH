# TOP CDC 检查

CDC约束为工程根目录的 `tpu_top_cdc.sgdc`。Makefile直接生成SpyGlass原生工程并调用工具，不依赖外部脚本。

```
cd /mnt/hgfs/share/tpu/tpu/TPU_TOP
make cdc-setup
make cdc
make cdc-gui
```

`make cdc-setup` 执行 cdc_setup 和 cdc_setup_check；`make cdc` 额外执行 cdc_verify_struct。`make cdc-gui` 在Linux图形会话打开结构检查工程。

原生报告和运行日志在 `~/tpu_top_runs/TPU_TOP/sg_cdc/<目标>/`。没有独立汇总器，不复制报告到共享目录。工具产生Error或报告规则因许可证缺失未执行时，Makefile返回非零。

约束：SYS周期2.5ns、AHB周期10ns，两个独立域；门控SYS/PE时钟沿RTL传播；DFT固定为功能模式；AHB端口属于AHB、AXI端口属于SYS。这对应已有单时钟FIFO接口约定，不能用于独立外部AXI时钟。没有quasi_static、报告直连路径豁免或CRG控制常量。

当前为七个既有模块直接集成，重点审查：

| 路径 | 当前结构与检查重点 |
|---|---|
| AHB START/EN → CTRL | 原有两级电平同步；先开钟，START须覆盖足够有效SYS采样沿，同步高电平可超过一个SYS周期 |
| AHB LOCK/权重/行号 → SA | SA_CTRL同步LOCK后锁存稳定数据；LOCK前数据稳定，且至少保持四个有效SYS周期 |
| H/W/MODE → CRG/SA | 直接静态配置；检查软件稳定窗口、掩码采样时刻和物理路径 |
| SYS报告/DONE → reg_list | 直接接AHB组合读口，没有额外返回同步或一致快照；检查计数一致性、亚稳态和读回协议 |
| W1C往返 | reg_list请求toggle → CTRL同步与处理 → reg_list ACK两级同步；期间必须保持开钟 |
| 复位和门控 | CRG公共异步断言、SYS释放及TOP独立AHB同步释放；继续审查复位域交互和停钟行为 |

当前没有命令桥或报告桥，TOP不自动屏蔽危险配置写入，也不自动保持时钟。4×4 INT8 smoke检查算术、握手、报告值和W1C，不能证明跨域在真实亚稳态或所有相位下安全。静态CDC之外仍需协议和物理实现验证。

2026-10-19历史实测的授权缺口为Advanced_CDC；核心Ac_unsync等规则未执行，该历史结果也不是当前直连结构的CDC通过报告。获得有效授权后重跑make cdc。不能靠改约束、删规则把未执行当作通过。
