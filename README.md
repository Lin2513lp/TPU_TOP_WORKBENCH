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

[`code/`](code/) contains all 26 RTL files compiled by TOP, including its AHB, CRG, AXI, CTRL, SA and PE dependencies, plus the single original `tb_tpu_top_smoke.sv`: **27 RTL/TB files**. The source viewer and downloads contain the same files. [`source-manifest.json`](source-manifest.json) records their hashes.

## Repository layout

| Path | Contents |
| --- | --- |
| [`TPU_TOP_WORKBENCH.html`](TPU_TOP_WORKBENCH.html) | Main design workbench; also works offline |
| [`code/TPU_TOP/`](code/TPU_TOP/) | TOP RTL and its smoke testbench |
| [`code/`](code/) | All RTL compiled by TOP and the single TOP smoke testbench |
| [`assets/`](assets/) | Connectivity diagram and Verdi waveform capture |
| [`source-manifest.json`](source-manifest.json) | Source inventory and checksums |
| [`index.html`](index.html) | English project introduction and workbench link |

## Using the project

Open the workbench to browse the report, code and waveforms. Simulation uses the original local integration project.

## Latest simulation update

The current TOP smoke passes **111 checks** in VM VCS: four input beats, seven output beats, sixteen independent arithmetic results, LAST and AHB reports. DONE is read-only; writing one leaves it set. The two software-clear handshake ports and all associated logic are removed.

SA active-size reporting resets to zero, clears on an EN rising edge and latches actual H/W on START. TOP checks zero both after reset and before START, then 4 x 4 after START. Existing configuration defaults and numeric datapaths are unchanged. TB edits are limited to the requested reporting/control changes.

All 14 directed VCS tests pass: TOP, four CTRL/regmap tests, six SA top tests and three SA unit tests. Current native detail captures and logs match the tested source hashes; the supplied primary screenshot is preserved as a reference from the prior run.

The [simulation report](https://lin2513lp.github.io/TPU_TOP_WORKBENCH/TPU_TOP_WORKBENCH.html#smoke-waveform) provides current native screenshots, VCD and VCS logs.

## Related workbenches

- [AHB_SLAVE](https://github.com/Lin2513lp/AHB_SLAVE_WORKBENCH)
- [TPU_CRG](https://github.com/Lin2513lp/TPU_CRG_WORKBENCH)
- [AXI_TOP](https://github.com/Lin2513lp/AXI_TOP_WORKBENCH)
- [TPU_CTRL](https://github.com/Lin2513lp/TPU_CTRL_WORKBENCH)
- [SA_TOP](https://github.com/Lin2513lp/sa-workbench)
- [PE_MP](https://github.com/Lin2513lp/pe-mp-workbench)
