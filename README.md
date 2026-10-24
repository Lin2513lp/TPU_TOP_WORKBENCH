# TPU_TOP Design Workbench

**[Open the TPU_TOP Workbench](https://lin2513lp.github.io/TPU_TOP_WORKBENCH/TPU_TOP_WORKBENCH.html)**

Top-level integration of a 16 x 16 multi-precision TPU, connecting AHB configuration, clock/reset control, AXI streams, dataflow control and the systolic array. The workbench runs in a browser and requires no installation.

## Workbench contents

- System architecture and the complete connectivity diagram for seven top-level module instances.
- 36 external ports, 32 register addresses, and current RTL/TB source browsing and downloads.
- 4 x 4 INT8 smoke waveforms, simulation-stage timing, and hexadecimal stimulus, expected results and actual outputs.
- AHB configuration, weight loading, START, stream handshakes, report reads and DONE write-one-to-clear.
- Original 18 SA ports; existing CTRL VALID/LAST carry lane0 vector markers. SA restores PE shared valid internally with 15 single-bit history registers; no numeric buffer or added latency.

## Source files

[`code/`](code/) contains the integrated `TPU_TOP` project and all RTL dependencies used by its compile list. Relative paths and file contents are preserved. The workbench's code viewer displays this same snapshot.

There are **32 project files** in this snapshot. [`source-manifest.json`](source-manifest.json) records the source inventory and SHA-256 checksums. Generated simulator databases, waveform dumps, editor temporary files and license logs are excluded.

## Repository layout

| Path | Contents |
| --- | --- |
| [`TPU_TOP_WORKBENCH.html`](TPU_TOP_WORKBENCH.html) | Main design workbench; also works offline |
| [`code/TPU_TOP/`](code/TPU_TOP/) | Integrated TOP, smoke testbench, Makefile, CDC constraints and notes |
| [`code/`](code/) | Compiled AHB, CRG, AXI, CTRL and SA dependencies, alongside TOP |
| [`assets/`](assets/) | Connectivity diagram and Verdi waveform capture |
| [`source-manifest.json`](source-manifest.json) | Source inventory and checksums |
| [`index.html`](index.html) | English project introduction and workbench link |

## Using the project

Open the workbench through the link above to browse the report, code and waveforms. For simulation, clone this repository, enter `code/TPU_TOP/`, and use its Makefile in a configured Linux EDA environment. Keep the sibling IP directories under `code/`; `rtl/filelist.f` references them.

```bash
cd code/TPU_TOP
make smoke       # Compile, run the self-checking smoke and generate FSDB
make verdi       # Open the existing FSDB/KDB from a Linux desktop terminal
```

| Command | Action |
| --- | --- |
| `make compile` | VCS compilation only |
| `make lint` | VCS static lint |
| `make spyglass` | SpyGlass RTL lint |
| `make cdc-setup` | CDC setup and constraint checks |
| `make cdc` | CDC setup plus structural verification |
| `make all` | Smoke, VCS lint, SpyGlass lint and CDC, stopping on failure |
| `make help` | List all supported targets |

Configure tool paths and licenses for your installation. Native outputs are written to `~/tpu_top_runs/TPU_TOP/`. Core structural CDC rules require the appropriate Advanced_CDC license; skipped rules are treated as incomplete verification, not a passing CDC result.

## Latest simulation update

The unchanged strict TOP smoke now passes **107 checks** in VM VCS: four input beats, seven output beats, sixteen independent arithmetic results, LAST, AHB reports and W1C. This is new evidence for the existing-pin marker correction, not a reused historical result.

Six SA top tests and three units also pass. A dual real-FIFO / CTRL / SA comparison covers 108 tasks across four modes, three sizes and multiple lengths/gaps, checking data, PE valid, output timing and DONE against the pre-midnight version. Only two RTL modules change relative to that version. PE arithmetic, SA_CTRL, Skew numeric data and the collector are byte-identical; SA adds 15 control bits and no numeric delay. Existing VALID/LAST timing semantics are explicitly documented.

The [simulation report](https://lin2513lp.github.io/TPU_TOP_WORKBENCH/TPU_TOP_WORKBENCH.html#smoke-waveform) provides current native Verdi screenshots, VCD and raw VCS logs.

## Related workbenches

- [AHB_SLAVE](https://github.com/Lin2513lp/AHB_SLAVE_WORKBENCH)
- [TPU_CRG](https://github.com/Lin2513lp/TPU_CRG_WORKBENCH)
- [AXI_TOP](https://github.com/Lin2513lp/AXI_TOP_WORKBENCH)
- [TPU_CTRL](https://github.com/Lin2513lp/TPU_CTRL_WORKBENCH)
- [SA_TOP](https://github.com/Lin2513lp/sa-workbench)
- [PE_MP](https://github.com/Lin2513lp/pe-mp-workbench)
