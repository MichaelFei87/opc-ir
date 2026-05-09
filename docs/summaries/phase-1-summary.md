# Phase 1 Summary: Plugin Scaffold + Core Flows

> Completed: 2026-05-08

## What Was Built

Phase 1 establishes the OPC-IR plugin skeleton and proves the two core voting flows (forecast + verdict) work end-to-end with sample data.

### Milestone Breakdown

| Milestone | Description | Files |
|-----------|-------------|-------|
| M1.1 | Plugin scaffold | `plugin.json`, 7 commands, 4 agents, 1 skill, LICENSE |
| M1.2 | Roles + Pipeline + Defaults | 12 roles, 11 protocols, 6 YAML configs |
| M1.3 | Forecast flow | `vote-aggregate.sh`, `invalidator-lint.sh`, `forecast-render.sh` |
| M1.4 | Verdict flow | `verdict-aggregate.sh`, `falsifier-lint.sh`, `verdict-render-digest.sh` |
| M1.5 | Risk mitigations + E2E | README, ARCHITECTURE, mitigation tests |

### File Count

```
.claude-plugin/plugin.json     1 manifest
commands/opc-ir-*.md            7 command stubs
agents/*.md                     4 agent stubs
skills/opc-ir/skill.md          1 skill entry
roles/_schools/*.md             5 school roles
roles/_advocates/*.md           2 advocate roles
roles/_forecast/*.md            5 strategist roles
pipeline/*.md                  11 protocols (4 forked, 4 native, 3 stubs)
defaults/*.yaml                 6 configuration files
bin/*.sh                        5 executable scripts
tests/*.bats                    8 test suites
tests/fixtures/*                5 fixture files
tests/schemas/*.json            2 JSON schemas
docs/*                          4 documentation files
README.md + LICENSE             2 project files
```

## How to Run

### Prerequisites

```bash
# Install dependencies (macOS)
brew install bats-core shellcheck yq jq python3
```

### Run All Tests

```bash
cd opc-ir

# Run the full test suite (57+ assertions)
bats tests/scaffold.bats tests/roles.bats tests/forked-meta.bats \
     tests/invalidator-lint.bats tests/forecast.bats tests/verdict.bats \
     tests/falsifier-lint.bats tests/mitigations.bats

# Or run the e2e test which includes all of the above
bats tests/e2e-phase1.bats
```

### Test Individual Flows

```bash
# Forecast flow: aggregate 5 strategist votes
bin/vote-aggregate.sh tests/fixtures/strategist-votes.json defaults/role-weights.yaml /tmp/agg.json
cat /tmp/agg.json | jq '.aggregated'

# Verdict flow: aggregate 7 school+advocate votes
bin/verdict-aggregate.sh tests/fixtures/verdict-votes-ndx.json defaults/role-weights.yaml /tmp/verdict.json
cat /tmp/verdict.json | jq '.consensus'

# Invalidator lint: test specificity
bin/invalidator-lint.sh "If SPX drops below 4200 by Q3 2026"  # PASS
bin/invalidator-lint.sh "If things change"                      # FAIL

# Falsifier lint with retry counter
bin/falsifier-lint.sh "If NDX P/E exceeds 35 by June 2026"    # PASS
bin/falsifier-lint.sh "Markets unclear" --retry-counter /tmp/rc # FAIL (retry 1/2)
```

### Generate Readable Output

```bash
# Create a sample forecast markdown with ASCII bars
mkdir -p /tmp/opc-ir-test/forecast
echo '{"run_id":"demo","timestamp":"2026-05-08T12:00:00Z","world_model_ref":"wm-demo","regime_marker":null,"forecasts":{"NDX":{"1w":{"strongly_bearish":0.05,"bearish":0.15,"neutral":0.40,"bullish":0.30,"strongly_bullish":0.10}}},"strategist_dissent":[],"invalidators":{"NDX":{"1w":"If NDX falls below 18000 within 7 days"}}}' > /tmp/opc-ir-test/forecast/forecast.jsonl
bin/forecast-render.sh /tmp/opc-ir-test
cat /tmp/opc-ir-test/forecast/forecast.md

# Create a sample verdict digest with disclaimer
mkdir -p /tmp/opc-ir-test/verdict
echo '{"run_id":"demo","timestamp":"2026-05-08T12:00:00Z","ticker":"NDX","world_model_ref":"wm-demo","forecast_ref":"fc-demo","regime_marker":null,"consensus":{"direction":"long","conviction":0.65,"horizon":"1m"},"votes":[],"preserved_dissent":[],"falsifiers":[{"role":"fundamental-analyst","condition":"If NDX P/E exceeds 35 by June 2026"}]}' > /tmp/opc-ir-test/verdict/verdicts.jsonl
bin/verdict-render-digest.sh /tmp/opc-ir-test
cat /tmp/opc-ir-test/verdict/digest.md
```

## Test Results

```
tests/scaffold.bats ............ 8 tests, 0 failures
tests/roles.bats ............... 10 tests, 0 failures
tests/forked-meta.bats ......... 4 tests, 0 failures
tests/invalidator-lint.bats .... 7 tests, 0 failures
tests/forecast.bats ............ 7 tests, 0 failures
tests/verdict.bats ............. 7 tests, 0 failures
tests/falsifier-lint.bats ...... 6 tests, 0 failures
tests/mitigations.bats ......... 8 tests, 0 failures
tests/e2e-phase1.bats .......... 5 tests, 0 failures
─────────────────────────────────────────────────────
Total:                          62 tests, 0 failures
```

## Git History

```
6201766 feat: P1.5 risk mitigations, README, ARCHITECTURE, e2e acceptance
5cce2a9 feat: P1.4 verdict flow — verdict-aggregate, falsifier-lint, digest, tests
5133ff6 feat: P1.3 forecast flow — vote-aggregate, invalidator-lint, render, tests
ca93855 feat: P1.2 roles, pipeline protocols, and defaults configuration
b3f0d7c fix: P1.1R review — add agent stubs, fix .gitignore
afce655 feat: P1.1 plugin scaffold — manifest, 7 commands, skill, tests
2bc287c docs: add OPC-IR overview design spec
```

## What's Next (Phase 2: Memory Layer)

Phase 2 adds the world-model evolution flow:
- M2.1: Triage classifier (event → dimension routing)
- M2.2: 7 dimension watchers (world-model deltas)
- M2.3: Evolve synthesizer (delta → snapshot)
- M2.4: Thesis persistence (verdict history tracking)
