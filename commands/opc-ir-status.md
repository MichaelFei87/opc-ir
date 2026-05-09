---
name: opc-ir-status
description: "Full system health dashboard: streams, scheduler, tokens, integrity"
allowed-tools: Bash, Read
---

# /opc-ir-status

Display comprehensive system health dashboard.

## Procedure

Run the status script directly — do NOT reimplement its logic inline:

```bash
opc-ir-status.sh
```

Display the output as-is. If the script exits non-zero, report the error.
