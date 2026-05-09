---
name: opc-ir-init
description: Initialize OPC-IR runtime directory structure at ~/.opc-ir/
allowed-tools: Bash, Read, Write
---

# /opc-ir-init

Create the OPC-IR runtime directory tree if it does not exist.

## Procedure

1. Set `OPC_IR_HOME` to `${OPC_IR_HOME:-$HOME/.opc-ir}`.
2. Create directory structure:
   ```bash
   mkdir -p "$OPC_IR_HOME"/{config,world,forecast,verdict/theses,events,calibration,harness/runs,triggers,logs}
   ```
3. If `$OPC_IR_HOME/config/local.yaml` does not exist, create it with default contents:
   ```yaml
   # OPC-IR local configuration override
   # See defaults/*.yaml in the plugin install directory for all options
   # Uncomment and modify values below to override defaults
   
   # scheduler:
   #   evolve_interval: 1h
   #   calibrate_interval: daily
   ```
4. Report created directories and current configuration.
5. Print: "OPC-IR initialized at $OPC_IR_HOME. Run /opc-ir-status to check health."
