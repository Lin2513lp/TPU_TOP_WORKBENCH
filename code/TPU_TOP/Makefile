SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.NOTPARALLEL:

PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
RUN_DIR ?= $(HOME)/tpu_top_runs/TPU_TOP
BUILD_DIR := $(RUN_DIR)/vcs
RTL_LIST := $(RUN_DIR)/rtl.f
SIMV := $(BUILD_DIR)/simv
FSDB := $(RUN_DIR)/tb_tpu_top_smoke.fsdb
VCS ?= vcs
VERDI ?= verdi
SPYGLASS ?= spyglass
LICENSE_DEFAULT := $(or $(SNPSLMD_LICENSE_FILE),$(LM_LICENSE_FILE),27000@localhost.localdomain)
LICENSE_SERVER ?= $(LICENSE_DEFAULT)
export SNPSLMD_LICENSE_FILE = $(LICENSE_SERVER)
export LM_LICENSE_FILE = $(LICENSE_SERVER)
SCL_ROOT ?= $(HOME)/Synopsys/scl/2024.06
LMUTIL ?= $(SCL_ROOT)/linux64/bin/lmutil
LMGRD ?= $(SCL_ROOT)/linux64/bin/lmgrd
LICENSE_FILE ?= $(SCL_ROOT)/admin/license/synopsys.lic
VERDI_BIN := $(shell readlink -f "$$(command -v $(VERDI))" 2>/dev/null)
VERDI_ROOT := $(or $(VERDI_HOME),$(NOVAS_HOME),$(abspath $(dir $(VERDI_BIN))/..))
SG_BIN := $(shell readlink -f "$$(command -v $(SPYGLASS))" 2>/dev/null)
SG_ROOT := $(or $(SPYGLASS_HOME),$(abspath $(dir $(SG_BIN))/..))
SIM_ARGS ?=

.PHONY: all help prepare license compile smoke run lint spyglass cdc cdc-setup verdi spyglass-gui cdc-gui
all: smoke lint spyglass cdc

help:
	@printf '%s\n' \
	 'make compile      : VCS compile only' \
	 'make license      : check license service; start existing local service if needed' \
	 'make smoke / run  : compile, self-checking smoke and FSDB' \
	 'make lint         : VCS +lint=all' \
	 'make spyglass     : SpyGlass RTL lint' \
	 'make cdc-setup    : CDC clock/reset and constraint checks' \
	 'make cdc          : CDC setup + structural checks' \
	 'make all          : smoke + VCS lint + SpyGlass lint + CDC' \
	 'make verdi        : open the existing FSDB and KDB' \
	 'make spyglass-gui : open the RTL lint project' \
	 'make cdc-gui      : open the structural CDC project' \
	 'All generated files stay in $(RUN_DIR); shared sources stay unchanged.'

prepare:
	@mkdir -p "$(RUN_DIR)"
	@while read -r file; do \
	 file=$${file%$$'\r'}; \
	 case "$$file" in ''|//*) continue ;; esac; \
	 source=$$(realpath "$(PROJECT_ROOT)/$$file"); \
	 test -f "$$source" || { echo "Missing RTL: $$source"; exit 1; }; \
	 printf '%s\n' "$$source"; \
	 done < "$(PROJECT_ROOT)/rtl/filelist.f" > "$(RTL_LIST)"

# Use the existing license file. Never change licenses or restart a remote server.
license:
	@mkdir -p "$(RUN_DIR)"
	@test -x "$(LMUTIL)" || { echo 'lmutil missing; set SCL_ROOT or LMUTIL.'; exit 1; }
	@exec 9>"$(RUN_DIR)/license.lock"; flock -w 30 9; \
	 status="$(RUN_DIR)/license_status.log"; \
	 if timeout 3 "$(LMUTIL)" lmstat -a -c "$(LICENSE_SERVER)" >"$$status" 2>&1 && grep -q 'snpslmd: UP' "$$status"; then \
	   echo '[LICENSE] UP: $(LICENSE_SERVER)'; exit 0; \
	 fi; \
	 case '$(LICENSE_SERVER)' in \
	   27000@localhost.localdomain|27000@localhost|27000@127.0.0.1) ;; \
	   *) echo 'License service unavailable: $(LICENSE_SERVER). Check its server; no local recovery attempted.'; exit 1 ;; \
	 esac; \
	 test -f "$(LICENSE_FILE)" -a -x "$(LMGRD)" || { echo 'Existing local license file or lmgrd missing; set LICENSE_FILE / LMGRD.'; exit 1; }; \
	 if pgrep -u "$$(id -u)" -x lmgrd >/dev/null; then \
	   echo '[LICENSE] Requesting reread from existing local service'; \
	   timeout 5 "$(LMUTIL)" lmreread -c "$(LICENSE_SERVER)" >>"$(RUN_DIR)/license_daemon.log" 2>&1 || true; \
	 else \
	   echo '[LICENSE] Starting local service with existing license file'; \
	   nohup "$(LMGRD)" -c "$(LICENSE_FILE)" -l "$(RUN_DIR)/license_daemon.log" </dev/null >/dev/null 2>&1 9>&- & \
	 fi; \
	 for attempt in {1..20}; do \
	   if timeout 3 "$(LMUTIL)" lmstat -a -c "$(LICENSE_SERVER)" >"$$status" 2>&1 && grep -q 'snpslmd: UP' "$$status"; then \
	     echo '[LICENSE] UP: $(LICENSE_SERVER)'; exit 0; \
	   fi; \
	   sleep 1; \
	 done; \
	 echo 'License service unavailable; inspect $(RUN_DIR)/license_daemon.log'; exit 1

compile: prepare license
	@mkdir -p "$(BUILD_DIR)"
	@cd "$(BUILD_DIR)" && $(VCS) -full64 -sverilog -timescale=1ns/1ps \
	 -kdb -debug_access+all +define+FSDB_TRACE \
	 -P "$(VERDI_ROOT)/share/PLI/VCS/LINUX64/novas.tab" \
	 "$(VERDI_ROOT)/share/PLI/VCS/LINUX64/pli.a" \
	 -f "$(RTL_LIST)" "$(PROJECT_ROOT)/tb/tb_tpu_top_smoke.sv" \
	 -top tb_tpu_top_smoke -Mdir=csrc -o "$(SIMV)" \
	 2>&1 | tee "$(RUN_DIR)/compile.log"

smoke run: compile
	@cd "$(RUN_DIR)" && "$(SIMV)" +FSDB_FILE="$(FSDB)" $(SIM_ARGS) \
	 2>&1 | tee "$(RUN_DIR)/smoke.log"
	@grep -q TPU_TOP_SMOKE_PASS "$(RUN_DIR)/smoke.log"
	@test -s "$(FSDB)"

lint: prepare license
	@mkdir -p "$(RUN_DIR)/vcs_lint"
	@cd "$(RUN_DIR)/vcs_lint" && $(VCS) -full64 -sverilog \
	 -timescale=1ns/1ps +lint=all -f "$(RTL_LIST)" -top tpu_top \
	 -Mdir=csrc -o simv_lint 2>&1 | tee "$(RUN_DIR)/lint.log"

# Only the tool's native project/report files are generated, on the VM disk.
spyglass: prepare license
	@mkdir -p "$(RUN_DIR)/sg_lint"
	@printf '%s\n' \
	 '#!SPYGLASS_PROJECT_FILE' '#!VERSION 2.7' \
	 'read_file -type sourcelist $(RTL_LIST)' \
	 'set_option top tpu_top' \
	 'set_option projectwdir $(RUN_DIR)/sg_lint/work' \
	 'set_option language_mode mixed' \
	 'set_option enableSV yes' \
	 'set_option mthresh 65536' \
	 'set_option auto_save yes' \
	 'set_option active_methodology $(SG_ROOT)/GuideWare/latest/block/rtl_handoff' \
	 'current_methodology $(SG_ROOT)/GuideWare/latest/block/rtl_handoff' \
	 'current_goal lint/lint_rtl -top tpu_top' > "$(RUN_DIR)/sg_lint/tpu_top.prj"
	@cd "$(RUN_DIR)/sg_lint" && $(SPYGLASS) -batch -project tpu_top.prj \
	 -goals lint/lint_rtl 2>&1 | tee "$(RUN_DIR)/spyglass.log"
	@report=$$(find "$(RUN_DIR)/sg_lint/work" -path '*/consolidated_reports/*/moresimple.rpt' -print -quit); \
	 test -n "$$report"; \
	 ! grep -Eq '^[[:space:]]*\[[[:xdigit:]]+\].*[[:space:]](Error|Fatal|Syntax|SynthesisError)[[:space:]]' "$$report"

cdc-setup cdc: prepare license
	@status=0; goals='cdc_setup cdc_setup_check'; \
	 if [ '$@' = cdc ]; then goals="$$goals cdc_verify_struct"; fi; \
	 for goal in $$goals; do \
	 work="$(RUN_DIR)/sg_cdc/$$goal"; mkdir -p "$$work"; \
	 printf '%s\n' \
	 '#!SPYGLASS_PROJECT_FILE' '#!VERSION 2.7' \
	 "read_file -type sourcelist $(RTL_LIST)" \
	 "read_file -type sgdc $(PROJECT_ROOT)/tpu_top_cdc.sgdc" \
	 'set_option top tpu_top' \
	 "set_option projectwdir $$work/work" \
	 'set_option language_mode mixed' \
	 'set_option enableSV yes' \
	 'set_option mthresh 65536' \
	 'set_option auto_save yes' \
	 'set_option active_methodology $(SG_ROOT)/GuideWare/latest/block/rtl_handoff' \
	 'current_methodology $(SG_ROOT)/GuideWare/latest/block/rtl_handoff' \
	 "current_goal cdc/$$goal -top tpu_top" > "$$work/tpu_top.prj"; \
	 (cd "$$work"; $(SPYGLASS) -batch -project tpu_top.prj -goals "cdc/$$goal") \
	 2>&1 | tee "$$work/run.log"; \
	 report=$$(find "$$work/work" -path '*/consolidated_reports/*/moresimple.rpt' -print -quit); \
	 test -n "$$report"; \
	 if grep -Eq 'Ac_license.*(not run|unavailab|not available)' "$$report"; then \
	   echo "CDC_INCOMPLETE_LICENSE: $$goal has rules that did not run."; status=1; \
	 elif grep -Eq '^[[:space:]]*\[[[:xdigit:]]+\].*[[:space:]](Error|Fatal|Syntax|SynthesisError)[[:space:]]' "$$report"; then \
	   echo "CDC findings: $$report"; status=1; \
	 fi; \
	 done; exit $$status

verdi:
	@test -n "$${DISPLAY:-}" || { echo 'Run make verdi in the VM desktop terminal.'; exit 1; }
	@test -s "$(FSDB)" -a -d "$(SIMV).daidir" || { echo 'Run make smoke first.'; exit 1; }
	@cd "$(RUN_DIR)" && $(VERDI) -full64 -nologo -ssf "$(FSDB)" -dbdir "$(SIMV).daidir"

spyglass-gui:
	@test -n "$${DISPLAY:-}" -a -f "$(RUN_DIR)/sg_lint/tpu_top.prj"
	@cd "$(RUN_DIR)/sg_lint" && $(SPYGLASS) -project tpu_top.prj

cdc-gui:
	@test -n "$${DISPLAY:-}" -a -f "$(RUN_DIR)/sg_cdc/cdc_verify_struct/tpu_top.prj"
	@cd "$(RUN_DIR)/sg_cdc/cdc_verify_struct" && $(SPYGLASS) -project tpu_top.prj
