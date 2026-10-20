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

约束：SYS周期2.5ns、AHB周期10ns，两个独立域；门控SYS/PE时钟沿RTL传播；DFT固定为功能模式；AHB端口属于AHB、AXI端口属于SYS。这对应已有单时钟FIFO接口约定，不能用于独立外部AXI时钟。没有quasi_static、邮箱路径豁免或CRG控制常量。

重点审查START/LOCK权重邮箱、99bit报告快照、W1C往返握手、EN及开钟、直接跨域的H/W/MODE配置，以及门控/复位。静态CDC之外仍需协议和物理实现验证。

2026-10-19实测的既有授权缺口为Advanced_CDC；核心Ac_unsync等规则未执行。获得有效授权后重跑make cdc。不能靠改约束、删规则把未执行当作通过。
