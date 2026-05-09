---
name: opc-ir-digest
description: Regenerate digest.md from latest verdicts
allowed-tools: Bash, Read, Write
---

# /opc-ir-digest

Regenerate the verdict digest from existing verdicts.jsonl.

## Procedure
3. Check `$OPC_IR_HOME/verdict/verdicts.jsonl` exists; if not, print "No verdicts found. Run /opc-ir-verdict <ticker> first." and exit.
4. Run `verdict-render-digest.sh "$OPC_IR_HOME"` to regenerate `$OPC_IR_HOME/verdict/digest.md`. **You MUST call the actual script — do NOT reimplement digest rendering inline.**
5. Print the contents of `digest.md`.

## Style Rules

- **No abbreviations in user-facing output.** Use full names: 欧洲央行 (not ECB), 美联储 (not Fed), 中国人民银行 (not PBOC), 日本央行 (not BOJ), 政府支持企业 (not GSE). Abbreviations are fine in internal data fields.
