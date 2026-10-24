# TPU_TOP 直连集成说明

当前结构更新于 2026-10-24。TOP 保留既有模块接口，直接连接现有代码。

## 层级与数据路径

rtl/tpu_top.sv 保留36个对外端口：6个时钟/复位/DFT、12个AHB、18个AXI-Stream。TOP直接实例化七个模块：

- ahb_slave：AHB请求、合法性判断和响应。
- reg_list：控制、配置、W1P、W1C请求及状态组合读回。
- tpu_crg：系统/PE门控时钟与公共复位。
- AXI_M_TOP：内部axi2fifo与单时钟fifo_in。
- tpu_ctrl：原有EN/START同步、任务控制、16路Skew、计数和计算DONE。
- sa_top：原有LOCK/权重接收、PE阵列和输出收集。
- AXI_S_TOP：内部单时钟fifo_out与fifo2axi。

顶层不再增加命令桥、报告桥、配置写屏蔽、忙状态管理或自动开钟保持。工作台展示七个直接实例及四个AXI内部子模块，共11个模块；完整逐端口连接由TOP_CONNECTIVITY.md自动生成。

lane0仍对应bits[31:0]。SA只通过既有dat_in_a、dat_in_vld、dat_in_last接收CTRL的Skew输出；不增加原始FIFO有效或LAST输入，TOP也不生成这类旁路标记。包内必须连续输入。SA根据共享VALID起点与物理Skew LAST，在内部延后15拍恢复连续向量边界，并暂存PE结果15拍后输出完整波前；不能从共享VALID还原任意包内气泡。CTRL的SA完成反馈仍为dat_out_vld && dat_out_last，与AXI最后一拍被接收是不同边界。

## 沿用原有CDC

START/EN直接来自AHB寄存器，经tpu_ctrl_sync两级电平同步。CTRL在使能且空闲时接受同步START的上升沿。同步START可以高多个SYS周期，不要求仅一拍。

LOCK、512位权重和行号直接接SA。sa_ctrl对LOCK两级同步并检测上升沿，再锁存稳定的权重与行号，延迟一拍控制PE写入。源端须在LOCK前稳定数据，且至少保持四个有效sys_ckg周期；需要软件满足稳定窗口，并通过实际时序路径约束验证。

H/W/MODE沿用原静态配置接口，使用期间必须稳定。H/W还参与CRG保存PE分组掩码，应在门控关闭时修改，再开钟。TOP不在任务中自动拦住配置写。

W1C沿用原握手：reg_list翻转cpu_done_clear_req，CTRL两级同步、处理并返回done_clear_ack，再由reg_list两级同步ACK。未确认的重复W1C合并，清除不擦除计数。请求在停钟时保持，但TOP不会自动开钟，软件必须保证清除及确认期间时钟继续运行。

## 报告和DONE的含义

报告原信号直接接reg_list组合读口：

| 字索引 | 字节偏移 | 内容与来源 |
|---|---|---|
| 0x100 | 0x400 | SA实际H/W，{H[15:0],W[15:0]} |
| 0x101 | 0x404 | fifo2axi实际输出握手数，不是计算耗时 |
| 0x102 | 0x408 | CTRL FIFO实际读拍数 |
| 0x103 | 0x40C | CTRL提前SA LAST错误次数，3位饱和计数 |
| 0x104 | 0x410 | CTRL保持型计算DONE，bit0写1清除 |
| 0x105 | 0x414 | 软件独立开钟请求 |
| 0x106 | 0x418 | CTRL累计错误标志 |

没有AHB结果副本、整组一致快照或汇总发布DONE。CTRL DONE只代表既有计算完成条件满足，不保证外部消费者已经接收最后一拍输出。SYS计数和DONE直接返回AHB，跨域读回一致性仍需CDC、协议和物理实现审查；正常功能仿真通过不能代替该结论。

## 软件操作顺序

AHB使用对齐32位SINGLE NONSEQ访问，HADDR[11:2]为字索引，高位基址由外部HSEL译码负责；原从接口有等待周期。

1. 等待复位完成。软件复位经CRG复位整个TOP，包括配置与任务。
2. 清CRG_EN（字0x105）和BYPASS（字0x003），等门控关闭后写H−1（字0x004）、W−1（字0x005）及MODE（字0x006）。CRG仅在同步开钟请求低时保存PE掩码。
3. 置EN（字0x000），再置CRG_EN，等待时钟及同步EN稳定。停钟时不能直接发一个START/LOCK脉冲指望目标域接住。
4. 写一行权重（字0x009～0x018）与行号（字0x007），稳定后向LOCK（字0x008）写1。至少保持四个有效SYS周期后再改行数据。当前smoke每行LOCK后等待200ns，适用于400MHz SYS / 100MHz AHB本次测试。
5. 预载各行后向START（字0x002）写1。连续提供一包完整输入，最后一拍置rd_tlast；本项目流量约定wr_tready=1。
6. 保持EN、开钟和H/W/MODE/权重，等待CTRL DONE与最后一拍输出已接收，再读取稳定后的报告。TOP不延迟危险写入，也不自动保持EN或时钟。
7. 如需W1C，向字0x104 bit0写1；继续开钟，等待请求处理及ACK返回，再确认DONE清除。当前smoke在W1C后保留200ns等待。
8. 修改尺寸或关钟前还需确认流水线尾部结束。原模块存在固定16路输入填充，单独看到CTRL DONE或一瞬间SA empty不证明所有未来尾部都排完；等待界限须按具体精度、流水线和停顿条件验证。下一项任务重新按配置、开钟、权重、START顺序执行。

START/LOCK的AHB单周期W1P必须覆盖足够有效SYS采样边沿。100MHz AHB对连续400MHz SYS的正常测试满足该前提；频率、门控、复位或软件间隔变化后应重验。

## 时钟、复位与验证范围

CRG提供公共异步复位断言，并对常开SYS同步释放。TOP保留AHB独立两级同步释放。SYS/PE门控时钟来自同一SYS源；DFT保留原测试复位旁路和门控覆盖。复位源、模式切换及复位域交互还需独立审查。

tb/tb_tpu_top_smoke.sv针对当前直连结构执行一项4×4 INT8任务：AHB配置、四行权重、一次被CTRL接受的START、4拍输入、7拍输出、16个有效lane独立算术比较、LAST/侧带、报告与W1C。其范围是这组正常时钟、软件顺序与流量；不得沿用带桥历史回归声称所有精度、任务重叠、停钟命令或CDC已经重新验证。

FP2FIX此前舍入为零和组合默认赋值修正保留。各历史回归及静态结果见带日期报告，仅对应其中记录的源码版本。

## Linux VM命令

在/mnt/hgfs/share/tpu/tpu/TPU_TOP执行：

| 指令 | 动作 |
|---|---|
| make help | 列出当前有效目标 |
| make license | 检查现有许可服务，必要时启动既有本地服务 |
| make compile | VCS编译TOP及当前smoke TB |
| make smoke / make run | 编译、自检仿真、生成FSDB |
| make lint | VCS +lint=all |
| make spyglass | SpyGlass lint_rtl |
| make cdc-setup | CDC setup及约束检查 |
| make cdc | 再执行结构CDC检查 |
| make all | 依次执行smoke、VCS lint、SpyGlass lint、CDC |
| make verdi | Linux图形终端打开已生成FSDB/KDB |
| make spyglass-gui | 打开lint原生工程 |
| make cdc-gui | 打开结构CDC原生工程 |

共享运行工程仅需rtl/、tb/、Makefile、tpu_top_cdc.sgdc；既有依赖是原兄弟目录。原生产物位于Linux本地~/tpu_top_runs/TPU_TOP/，可用RUN_DIR覆盖，无外部报告汇总和自动截图脚本。当前没有make check、make cdc-summary或make cdc-check目标。

此前确认缺少Advanced_CDC。核心规则未完整执行时，make cdc / make all返回失败，不能视为CDC通过；有效许可补齐后再重跑并逐项审查实际结果。
