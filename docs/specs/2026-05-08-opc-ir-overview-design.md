# OPC-IR Overview Design

> **Status**: Draft (awaiting user review)
> **Date**: 2026-05-08
> **Author**: brainstormed via OPC's brainstorming flow
> **Scope**: System-wide architecture overview. Phase 1 (Core Engine) gets its own implementation plan after this spec is approved.
> **Forked from**: OPC at commit `6f83dde` (`/Users/michaelfei_0/Workspace/Vibe Personal/opc`)

---

## §1 Project Definition

**OPC-IR** (One Person Company — Investment Research) is an open-source Claude Code Plugin that converts the OPC multi-role independent voting methodology into an investment-research system. It produces three outputs:

1. **World-Model evolution** — a continuously-updated macro snapshot across 7 weighted dimensions. Persisted as `world-model.jsonl` (append-only history) + `world-model.md` (current snapshot).
2. **Macro Forecast** — every 8 hours, a 5-tier probability distribution × multiple horizons over ~14 cross-market assets. Persisted as `forecast.jsonl` + `forecast.md`.
3. **Verdict** — event-triggered or user-invoked single-asset judgment using a dual-axis role pool (5 schools × 2 advocates). Persisted as `verdicts.jsonl` + `theses/{ticker}.md` + `digest.md`.

### 1.1 Phase 1 geographic scope

US + China.

### 1.2 Default watch-assets (14)

`NDX, SPX, RUT, VIX, HSI, HSCEI, CSI300, CYB, DXY, CNH, GLD, ZB, WTI, BTC`.

### 1.3 7 macro dimensions with weights

| Dimension | Weight |
|---|---|
| Politics | 1.5 |
| Econ-finance | 1.5 |
| Military | 1.0 |
| Tech-AI | 1.3 (sub-weighted toward AI) |
| Humanities | 0.8 |
| Energy-commodity | 1.0 |
| Corp-fundamentals | 1.2 |

### 1.4 5 forecast strategists

`macro-strategist, cross-asset-allocator, regime-detector, historical-analogist, contrarian-strategist`

### 1.5 Twelve design principles

1. **OPC methodology inheritance** — multi-role independent evaluation, harness-based file state, dispatch via Agent tool.
2. **Three-stream layered architecture** — World-Model → Forecast → Verdict, each with independent time constants.
3. **Falsifier-first** — every thesis and forecast must carry a specific invalidator (numeric + temporal + asset/event), enforced by lint gate.
4. **Cold-start honesty** — calibration-derived posterior weights only kick in after N≥30 samples per role.
5. **Dissent preservation** — minority opinions persisted in jsonl, never discarded by synthesis.
6. **LLM only where semantics are required** — routing, weighted aggregation, file IO, price-fetch are code, not LLM.
7. **Configuration as enhancement, not prerequisite** — repo ships `defaults/`, user override is optional.
8. **Stateless re-entrant slash commands** — all state lives in files under `~/.opc-ir/`.
9. **Three outputs are mutually-reinforcing yet independently calibratable** — Forecast reads World-Model snapshot; Verdict reads both; each layer has its own ground-truth alignment.
10. **Compliant by default, premium optional** — defaults use public RSS / authorized APIs; premium-source hooks preserved for users with their own credentials.
11. **User decides, system reduces cognitive load** — never present output as "advice"; conviction values, split warnings, regime warnings are first-class.
12. **Independent runtime** — OPC-IR is a hard fork of OPC methodology at commit `6f83dde`; no install-time or runtime dependency on OPC repo.

### 1.6 MVP runtime

Pure Claude Code plugin. MVP execution path:

```
/loop 1h    /opc-ir-evolve
/loop daily /opc-ir-calibrate
```

Future (Phase 5): Desktop scheduled tasks + Cloud Routines abstraction.

### 1.7 Configuration layering

```
defaults/*.yaml (in repo)
  ← override by ~/.opc-ir/config/local.yaml
  ← override by env vars
  ← override by ~/.opc-ir/calibration/role-weights.yaml (runtime-learned)
```

---

## §2 Architecture Overview

### 2.1 Plugin directory structure (GitHub repo layout)

```
opc-ir/
├── .claude-plugin/plugin.json
├── commands/
│   ├── opc-ir-init.md
│   ├── opc-ir-evolve.md            # default /loop entry, runs every 1h
│   ├── opc-ir-forecast.md          # macro forecast, runs every 8h
│   ├── opc-ir-verdict.md           # single-ticker verdict, event-triggered
│   ├── opc-ir-calibrate.md
│   ├── opc-ir-digest.md
│   └── opc-ir-status.md
├── agents/
│   ├── triage-classifier.md
│   ├── role-evaluator.md
│   ├── synthesizer.md
│   └── verdict-judge.md            # dual-purpose: verdict synthesis + calibration falsifier check
├── skills/opc-ir/skill.md
├── roles/
│   ├── _schools/         (5 files)
│   ├── _advocates/       (2 files)
│   ├── _forecast/        (5 files)
│   └── _watchers/        (7 files)
├── pipeline/
│   ├── ingest-protocol.md
│   ├── triage-protocol.md
│   ├── evolve-protocol.md
│   ├── forecast-protocol.md
│   ├── vote-protocol.md
│   ├── verdict-protocol.md
│   ├── calibration-protocol.md
│   ├── invalidator-lint.md
│   └── (forked-verbatim from OPC: discussion-protocol.md, role-evaluator-prompt.md, gate-protocol.md, role-spec.md)
├── bin/
│   ├── fetch-rss.sh
│   ├── fetch-prices.sh
│   └── ground-truth-linker.sh
├── defaults/
│   ├── sources.yaml
│   ├── watch-assets.yaml
│   ├── dimension-weights.yaml
│   ├── role-weights.yaml
│   ├── horizons.yaml
│   └── triage-thresholds.yaml
├── docs/
│   ├── README.md
│   ├── ARCHITECTURE.md
│   ├── CUSTOMIZE.md
│   ├── PREMIUM-SOURCES.md
│   ├── INHERITS-FROM-OPC.md
│   ├── specs/                       # this file lives here
│   └── plans/                       # phase plans live here
└── LICENSE
```

**Key design points**:
- `roles/_*/` underscore prefix groups roles visually; OPC's `tags:` filter still works orthogonally.
- `defaults/` ships in the repo; first-run requires zero config.
- `bin/` minimal: only deterministic IO (RSS fetch, price fetch, file alignment); all judgment stays in LLM agents.
- User local override lives in `~/.opc-ir/config/local.yaml`, never in repo.

### 2.2 Subsystem topology (data flow)

```
                    ┌─────────────────────┐
                    │  External Sources   │
                    │  RSS / Public APIs  │
                    └──────────┬──────────┘
                               │
                    ┌──── /opc-ir-evolve (atomic command) ────┐
                    │                                          │
                    ▼                                          │
                Step 1: fetch (bin/fetch-rss.sh)               │
                    │ → events.jsonl                           │
                    ▼                                          │
                Step 2: triage-classifier (LLM agent)          │
                    │ → triage.json                            │
                    ▼                                          │
        ┌───────────┴───────────┐                              │
        ▼ matched dim threshold ▼ matched hard-rule            │
   Step 3: watchers       Step 5: trigger marker               │
   (concurrent dispatch)   for /opc-ir-verdict                 │
        │                                                       │
        ▼                                                       │
   Step 4: synthesizer                                          │
        │ → world-model.md (rewrite)                            │
        │ → world-model.jsonl (append delta)                    │
        │                                                       │
        ▼                                                       │
   Step 6: forecast.md mtime > 8h? → /opc-ir-forecast            │
                                                               │
   /opc-ir-forecast    /opc-ir-verdict (async, on next tick) ◄─┘
        │                       │
        ├── reads world-model   ├── reads world-model + forecast + theses/{ticker}.md
        ├── 5 strategists       ├── 5 schools + 2 advocates (concurrent)
        ├── vote + invalidator-lint
        │                       ├── vote + falsifier-lint
        ▼                       ▼
   forecast.jsonl/md       verdicts.jsonl, theses/{ticker}.md, digest.md
                                       │
                                       ▼
                              /opc-ir-calibrate (daily)
                                       │
                                       ▼
                              ~/.opc-ir/calibration/role-weights.yaml
```

Note: ingestion has no separate user-facing command; it is Step 1 of `/opc-ir-evolve`. The atomic-command design ensures no "fetched-but-not-understood" intermediate state.

### 2.3 Phase division

| Phase | Scope |
|---|---|
| **Phase 1: Core Engine (POC)** | Forecast + Verdict flows with manually-fed events; risk mitigations (D2/M3/M4/P1/P2). |
| **Phase 2: Memory Layer** | World-Model + thesis persistence; 7 watchers + evolve-protocol full chain. |
| **Phase 3: Auto-loop Polish** | Automatic ingestion + hard-rule async verdict trigger; `--light`/`--dry-run`/cool-down. |
| **Phase 4: Calibration** | Ground-truth alignment + posterior role-weights + regime detection. |
| **Phase 5: Scheduling + Premium** | Desktop tasks / Routines abstraction; quota visibility (T1/T2); premium-source hooks. |

### 2.4 Runtime file layout (on user machine)

All runtime data under `~/.opc-ir/` (single root, dotfile convention):

```
~/.opc-ir/
├── config/                   # user config (gitignored, hand-editable)
│   ├── local.yaml
│   └── secrets.env
├── world/
│   ├── world-model.jsonl     # append-only evolution log
│   └── world-model.md        # current snapshot (rewrite)
├── forecast/
│   ├── forecast.jsonl
│   └── forecast.md
├── verdict/
│   ├── verdicts.jsonl
│   ├── digest.md
│   └── theses/
│       ├── NDX.md
│       └── ...
├── events/
│   └── events.jsonl
├── calibration/
│   ├── predictions-vs-truth.jsonl
│   └── role-weights.yaml     # runtime override of defaults/
├── harness/
│   └── runs/{run-id}/
│       ├── meta.json
│       ├── triage.json
│       ├── role-{name}/evaluation.md
│       └── synthesis.md
└── logs/
    └── {YYYY-MM-DD}.log
```

Top-level split is by **business stream** (`world/`, `forecast/`, `verdict/`, `events/`, `calibration/`), not by data role. Each stream colocates its `.jsonl` (machine, append-only, source of truth) with its `.md` (human, rewrite, derivable from jsonl).

### 2.5 Slash commands inventory

| Command | Frequency | Trigger | Action |
|---|---|---|---|
| `/opc-ir-init` | once (optional) | user | create `~/.opc-ir/` tree, optionally guide config override |
| `/opc-ir-evolve` | **1h** (default `/loop`) | `/loop` or manual | fetch → triage → watchers → world-model update; auto-trigger forecast (if 8h elapsed) and verdict (hard-rule via marker) |
| `/opc-ir-forecast` | 8h (driven by evolve) | scheduler / manual | 5 strategists → vote → invalidator-lint → forecast.jsonl/md |
| `/opc-ir-verdict <ticker>` | event-triggered / manual | hard-rule marker / user | 5 schools × 2 advocates → vote → falsifier-lint → verdict + thesis + digest |
| `/opc-ir-calibrate` | daily | `/loop` or manual | align ground truth → update role-weights |
| `/opc-ir-digest` | any time | user | regenerate digest.md |
| `/opc-ir-status` | any time | user | last evolve/forecast/verdict timestamps + health |

### 2.6 OPC mechanism mapping (how LLM uses OPC's flow + tick)

OPC supplies three reusable mechanisms; OPC-IR maps each:

| OPC mechanism | OPC-IR usage |
|---|---|
| **Digraph flow templates** (discussion / build / review / execute / gate node types) | New flows: forecast-flow, verdict-flow, evolve-flow, all using same `dot` node syntax |
| **Multi-role independent voting + harness** (each role dispatched as independent sub-agent via Agent tool, writes to `.harness/runs/{run-id}/role-{name}/evaluation.md`) | Reused unchanged. New roles (5 schools, 2 advocates, 5 strategists, 7 watchers) plug into the same dispatch / synthesis pipeline |
| **Tick-based gate checking** (lint protocol decides if pipeline can advance; failure ticks back to upstream) | Forecast → invalidator-lint gate; Verdict → falsifier-lint gate; both retry max 2 times |

**Where LLM is used vs not used** (principle #6):

| LLM | Code |
|---|---|
| Content judgment (strategist gives probability distribution) | Routing (triage outputs JSON, main flow dispatches per JSON) |
| Form judgment (invalidator-lint: "did role provide a falsifier?") | Weighted aggregation (read weights file + arithmetic) |
| Reflection (which role got things badly wrong this round) | File IO / RSS fetch / price alignment |

### 2.7 Relationship to OPC (independent runtime)

OPC-IR is a **hard fork** of OPC methodology at commit `6f83dde` (2026-05-08).

- **Forked verbatim**: `pipeline/discussion-protocol.md`, `role-evaluator-prompt.md`, `gate-protocol.md`, `role-spec.md`
- **Forked + specialized**: `loop-protocol.md` (added financial exit conditions)
- **OPC-IR-native**: `forecast-protocol.md`, `vote-protocol.md`, `verdict-protocol.md`, `invalidator-lint.md`, `triage-protocol.md`, `evolve-protocol.md`, `calibration-protocol.md`

Each forked file carries frontmatter:

```yaml
---
forked-from: opc/pipeline/<file>.md
forked-at: 2026-05-08  # OPC commit 6f83dde
modifications:
  - "..."
---
```

**No automatic upstream sync.** Future OPC upgrades will be evaluated and selectively ported manually; CHANGELOG records each port. (Sync tooling explicitly deferred indefinitely.)

OPC-IR users do **not** need OPC installed. Plugin ships self-contained.

---

## §3 Subsystem Contracts

(Schemas for each subsystem. Output media is JSONL append-only + MD rewrite per stream.)

### 3.1 Ingestion Step (evolve Step 1)

**Location**: `bin/fetch-rss.sh` (non-LLM)

**Input**: `defaults/sources.yaml` overridden by `~/.opc-ir/config/local.yaml`; reads tail of `events/events.jsonl` for incremental dedup.

**Output**: append to `events/events.jsonl`, each line:

```json
{
  "id": "<source>-<published-utc>-<hash>",
  "source": "reuters-business",
  "fetched_at": "2026-05-08T14:23:01Z",
  "published_at": "2026-05-08T14:15:00Z",
  "title": "...",
  "summary": "...",
  "url": "https://...",
  "raw_text": "..."
}
```

**Conventions**: exit 0 = success (possibly 0 new); per-source failure does not abort other sources; failures logged in `logs/{date}.log`.

**Failure modes**: timeout → skip source; parse fail → skip entry; all-source fail → exit 0 with 0 new events (evolve decides next).

**Invariant**: `events.jsonl` is append-only; `id` globally unique.

### 3.2 Triage Classifier (evolve Step 2)

**Location**: `agents/triage-classifier.md` (LLM agent)

**Input**: incremental events since last triage; `defaults/dimension-weights.yaml`; `defaults/triage-thresholds.yaml`:

```yaml
watcher-route-threshold: 0.6
hard-rule-verdict-threshold: 0.85
hard-rules:
  - "central bank policy decision"
  - "war declaration / ceasefire"
  - "earnings of NDX top-10 constituent"
  - "circuit breaker / market halt"
```

**Output**: `harness/runs/{run-id}/triage.json` with per-event 7-dimension scores, `watchers_to_dispatch`, `hard_rule_hit`, `verdict_targets`.

**Invariant**: triage is a pure function of (events, weights, thresholds); deterministic output enables tracking config changes via calibration.

**Failure modes**: long event text → truncate to 2000 chars; invalid JSON → retry once, else mark `triage_failed: true`; all-events fail → terminate evolve, do not update world-model.

### 3.3 Watcher Roles (evolve Step 3)

**Location**: `roles/_watchers/{dimension}-watcher.md` × 7, dispatched via `agents/role-evaluator.md`.

**Input per watcher**: routed event subset; `world/world-model.md` snapshot (read-only); own role file.

**Output**: `harness/runs/{run-id}/role-{dimension}-watcher/evaluation.md` with frontmatter (role, run_id, events_considered) and sections: Disturbance to World-Model, Cross-dimension implications.

**Conventions**: 7 watchers fully independent concurrent dispatch; cannot see each other's outputs.

**Failure modes**: single watcher fail → dimension skipped this round, warning; all fail → evolve terminates.

**Invariant**: all watchers see the same world-model snapshot frozen at Step 3 start.

### 3.4 Evolve Synthesizer (evolve Step 4)

**Location**: `pipeline/evolve-protocol.md` + `agents/synthesizer.md`

**Output**:
1. **Rewrite** `world/world-model.md` with frontmatter (`updated_at`, `evolved_from_run`, `schema_version`) and per-dimension sections.
2. **Append** delta to `world/world-model.jsonl`:
   ```json
   {
     "run_id": "...",
     "ts": "...",
     "deltas": [
       {"dimension": "...", "field": "...", "before": {...}, "after": {...},
        "trigger_events": [...], "watcher": "...", "watcher_confidence": 0.7}
     ]
   }
   ```

**Conventions**: synthesizer does not do content judgment; only merges N watcher proposals by weight per `evolve-protocol.md` rules. Conflicts → weighted average for same field, dissent recorded for contradicting fields.

**Invariant**: `world-model.md` is reconstructible from `world-model.jsonl`; jsonl is single source of truth.

### 3.5 Forecast Engine

**Location**: `commands/opc-ir-forecast.md` + `pipeline/forecast-protocol.md` + `pipeline/vote-protocol.md` + `roles/_forecast/*.md`

**Input**: world-model snapshot; previous forecast tail; watch-assets.yaml; horizons.yaml; calibration/role-weights.yaml strategist section.

**5 strategists' output (each)**: 5-tier probability distribution × 4 horizons × 14 assets, plus mandatory invalidator per asset/horizon.

**Synthesis output**:
- `forecast/forecast.jsonl` append, each line one full forecast referencing `world_model_ref` run_id, with `forecasts`, `strategist_dissent` (kept for audit), `invalidators`.
- `forecast/forecast.md` rewrite, human-readable with ASCII probability bars.

**Conventions**: vote weight = `prior_weight × posterior_weight`; if N<30, posterior degenerates to 1.0 (equal weight); dissent threshold L1 distance > 0.3 from majority.

**Failure modes**: single strategist fail → weight 0, warning; ≥3 fail → forecast terminates, prior version retained; invalidator-lint fail → retry max 2.

**Invariants**: every forecast row has invalidator; every forecast references concrete world-model run_id.

### 3.6 Verdict Pipeline

**Location**: `commands/opc-ir-verdict.md` + `pipeline/verdict-protocol.md` + `roles/_schools/*.md` + `roles/_advocates/*.md`; synthesis via `agents/verdict-judge.md`.

> Note: `verdict-judge.md` is dual-purpose. In §3.6 it synthesizes 7 role evaluations into a verdict. In §3.7 it judges (post-hoc) whether a thesis's falsifier was triggered by subsequent events. Both uses share the same prompt-engineered judgment behavior; the calling protocol differentiates the mode.

**Input**: ticker (CLI arg) or verdict_targets (from evolve Step 5 hard-rule); world-model.md snapshot; forecast.md snapshot; theses/{ticker}.md (if exists, as continuity); calibration role-weights school + advocate sections.

**Dual-axis dispatch**: 5 schools + 2 advocates (advocate weight = 0.5, cannot override schools).

**Each role's evaluation.md** (frontmatter + sections: Stance, Thesis, Falsifier (mandatory), Key risks acknowledged).

**Synthesis output**:
1. `verdict/verdicts.jsonl` append: `consensus`, `votes` (with per-role weight), `preserved_dissent`, `falsifiers`, refs to `world_model_ref` and `forecast_ref`.
2. `verdict/theses/{ticker}.md` rewrite: current active stance + accumulated history.
3. `verdict/digest.md` rewrite: human summary with disclaimer banner, conviction values, split warnings.

**Failure modes**: school fail → weight 0; ≥3 fail → verdict terminates; falsifier missing → falsifier-lint retries max 2; complete role split (no clear majority) → consensus.direction = "split", highlighted in digest.

**Invariants**: every verdict references concrete world-model + forecast versions; preserved_dissent never lost.

### 3.7 Calibration Loop

**Location**: `commands/opc-ir-calibrate.md` + `pipeline/calibration-protocol.md` + `bin/ground-truth-linker.sh` + `agents/verdict-judge.md` (in calibration-judge mode)

**Three ground-truth sources** (priority human > event > price):
1. **Price truth** (auto): t+horizon price → 5-tier bucket
2. **Event truth** (LLM judge): did the thesis falsifier trigger?
3. **Human truth** (optional): user's `human-overrides.jsonl`

**Output**:
- `calibration/predictions-vs-truth.jsonl` append per (run_id, asset, horizon, role)
- `calibration/role-weights.yaml` rewrite (only if N≥30 per role); posterior = `clamp(prior_brier / role_brier, 0.5, 1.5)`

**Failure modes**: missing prices → skip sample, do not count toward N; N<30 → no posterior write; anomaly distribution (all 1.0/0.0/NaN) → reject write, log warning.

**Invariants**: Brier score is publicly verifiable; N≥30 floor prevents small-sample bias.

### 3.8 Cross-subsystem contract summary

| Upstream | Downstream | Medium | Invariant |
|---|---|---|---|
| ingestion | triage | events.jsonl (incremental tail) | id unique, append-only |
| triage | watchers | triage.json (in-run) | each event ≥1 dim ≥ threshold to route |
| watchers | evolve-synth | harness/runs/.../evaluation.md × N | frontmatter: role + run_id |
| evolve | forecast | world-model.md snapshot | reconstructible from jsonl |
| evolve | verdict | hard-rule trigger marker | explicit trigger field |
| world-model + forecast | verdict | dual snapshot ref | verdict records ref run_id |
| forecast/verdict | calibration | jsonl + prices | timestamp + horizon align |
| calibration | all votes | role-weights.yaml | N<30 degenerates to equal weight |

---

## §4 Key Flows

(Time-sequence diagrams for the four main paths. See sequence diagrams in brainstorming history; reproduced here in compressed form. Full diagrams retained in `docs/ARCHITECTURE.md` after Phase 1.)

### 4.1 `/opc-ir-evolve` one round (atomic)

`fetch (Step 1)` → `triage (Step 2)` → `watchers concurrent (Step 3)` → `synthesizer (Step 4)` → rewrite world-model.md + append world-model.jsonl → **Step 5**: write hard-rule trigger markers (consumed at next tick by verdict, async) → **Step 6**: if `forecast.md` mtime > 8h, dispatch `/opc-ir-forecast` synchronously.

Decisions:
- Step 1 → 0 new events: short-circuit exit (no LLM cost, mitigates T7).
- Step 2 → no dimension matches: skip Step 3 & 4, world-model unchanged.
- Step 5 fire-and-forget pattern: marker file consumed by next evolve tick, avoiding nested Agent dispatch (mitigates T4).

Expected duration: 3–6 min per round.

### 4.2 `/opc-ir-forecast` one round (every 8h)

read world-model + previous forecast tail → 5 strategists concurrent dispatch (each produces 5-tier × 4 horizons × 14 assets + invalidator) → vote-protocol weighted aggregation → invalidator-lint gate → on pass: append forecast.jsonl + rewrite forecast.md.

Decisions:
- 5 strategists fully independent (echo-chamber elimination preserved from OPC).
- Vote formula: `final[asset][horizon][tier] = Σ (strategist_prob × prior_weight × posterior_weight)`, then normalize.
- Dissent threshold: per-strategist L1 distance > 0.3 from majority → preserved_dissent.
- Invalidator-lint is form-checking (specificity: numeric + temporal + asset/event), not content-checking.

Expected duration: 2–3 min.

### 4.3 hard-rule triggered `/opc-ir-verdict <ticker>`

read world-model + forecast + theses/{ticker}.md → 7 roles concurrent (5 schools + 2 advocates) → vote (advocates capped at 0.5 weight) → falsifier-lint gate → on pass: append verdicts.jsonl + rewrite theses/{ticker}.md (active stance + history) + rewrite digest.md (with disclaimer + conviction + split warning).

Decisions:
- Existing thesis injected into all 7 roles' input (continuity vs revision signal).
- Split detection: weighted long/short/neutral spread < 0.15 → consensus = "split", flagged in digest.

Expected duration: 3–4 min.

### 4.4 `/opc-ir-calibrate` daily

identify horizons-due-but-not-judged predictions → fetch prices (multi-source fallback) → verdict-judge in calibration mode (event truth) → merge with human overrides if any → compute Brier per (run_id, asset, horizon, role) → if N≥30: update calibration/role-weights.yaml (per role, with anomaly check).

Expected duration: 1–2 min.

### 4.5 Four-flow interaction

Frequency layering (high → low): verdict (event-driven) > evolve (1h) > forecast (8h) > calibration (daily). Higher-frequency flows read lower-frequency snapshots, never the reverse — this prevents oscillation. Calibration updates take effect on next round of vote-protocol read.

Note: ingestion does not appear as a separate node — it is internalized as Step 1 of evolve.

---

## §5 Risks & Open Questions

### 5.1 Technical risks (T)

| # | Risk | Sev | Mitigation | Phase |
|---|---|---|---|---|
| T1 | `/loop` 7-day expiry → world-model stalls | H (prod) / **L (POC)** | status command shows expiry; Phase 5 Desktop/Routine abstraction | **Phase 5** (deferred per user — POC has 7d trial sufficient) |
| T2 | Quota exhaustion → `/loop` silently stuck | H (prod) / **L (POC)** | per-run token logging; status quota visibility; `--light` mode | **Phase 5** (deferred — POC has unlimited tokens) |
| T3 | Concurrent watcher failure → world-model drift | M | jsonl `missing_dimensions`; 3-round-miss alert | Phase 2 |
| T4 | Agent tool nesting depth | M | trigger-marker file pattern (verdict in fresh session next tick) | Phase 2 (M2.3) |
| T5 | logs/{date}.log concurrent write | L | flock | Phase 3 |
| T6 | Plugin file tampering | L | install lock + status SHA check | Phase 5 |
| T7 | 1h frequency empty-tick waste | L | Step 1 short-circuit on 0 new events (already in §4.1) | **Phase 1 (auto-resolved)** |

### 5.2 Data risks (D)

| # | Risk | Sev | Mitigation | Phase |
|---|---|---|---|---|
| D1 | RSS instability | M | ≥10 sources default; status stale-flag | Phase 3 |
| D2 | Public-RSS info density vs Bloomberg | H | README "limitations"; Phase 5 premium hooks; `--inject-event` manual | **Phase 1 (doc) + Phase 5 (hooks)** |
| D3 | yfinance latency / errors (CN) | M | multi-source fallback; calibration tolerance | Phase 4 (M4.1) |
| D4 | events.jsonl unbounded growth | L | monthly rolling | Phase 4 (M4.5) |
| D5 | Duplicate events double-counted | M | URL+title fuzzy dedup; LLM fallback in triage | Phase 3 |
| D6 | Triage token explosion on busy days | M | batch ≤20 events; merge in Step 4 | Phase 2 (M2.1) |

### 5.3 Methodology risks (M)

| # | Risk | Sev | Mitigation | Phase |
|---|---|---|---|---|
| M1 | 5-tier discretization loses tail | M | Brier still differentiates; reassess in Phase 4 | Phase 4 (revisit) |
| M2 | N≥30 cold-start ~30 days | M | status shows accumulator progress; `--trust-prior` flag | Phase 4 |
| M3 | Weight collapse (single role dominates) | H | posterior cap [0.5, 1.5]; 3-cap-touch rejection; preserved_dissent never weighted out | **Phase 1** |
| M4 | Falsifier becomes formality ("if X significantly changes") | H | invalidator-lint specificity check (numeric+temporal+asset); calibration tracks falsifier trigger rate | **Phase 1** |
| M5 | Role pseudo-independence (shared world-model bias) | H | partial: world-model itself synthesized from 7 watchers; world-model.md "dissent" section | Phase 2 |
| M6 | No backtest / survivorship | M | accepted; no fake-backtest functionality offered | (accepted) |
| M7 | Reflexivity (system affects subject) | L | individual-plugin form mitigates; recorded | (accepted) |

### 5.4 Psychological risks (P)

| # | Risk | Sev | Mitigation | Phase |
|---|---|---|---|---|
| P1 | User treats verdict as advice | H | digest disclaimer banner; conviction value; split highlight; init prompt | **Phase 1** |
| P2 | Over-trust on long Brier (regime change unseen) | H | regime-detection: 30-day Brier deterioration → reset posterior to 1.0 + digest warning | **Phase 1 (placeholder field) + Phase 4 (full detection)** |
| P3 | Daily anxiety from digest | M | doc recommends weekly cadence; "changes since last view" section | Phase 5 |
| P4 | User edits role-weights.yaml manually → calibration zeroed | M | runtime weights separate from defaults/; status shows weight provenance | Phase 4 |
| P5 | User expects "73% up tomorrow" point estimate | M | digest uses emoji + natural-language translation; README explains why | Phase 1 |

### 5.5 Open questions (Q)

| # | Question | Tendency | Decide-when |
|---|---|---|---|
| Q1 | Separate `cn-events-watcher`? | reuse 7-dim watchers (bilingual prompt); revisit if Phase 1 shows underweighting | Phase 2 end |
| Q2 | `--dry-run` validation? | yes | Phase 3 |
| Q3 | ASCII probability bar in forecast.md? | yes | **Phase 1** |
| Q4 | Multi-user shared instance? | no; export world-model snapshot for sharing instead | (out of 5-phase scope) |
| Q5 | Asymmetric loss for contrarian? | unclear; revisit with N≥30 data | Phase 4 retro |
| Q6 | Thesis history-comparison section? | yes | Phase 2 (M2.4) |
| Q7 | User persona? | individual w/ finance background, accepts 8h forecast lag, 5-tier probability literacy | (decided) |
| Q8 | Verdict cool-down per ticker? | yes, default 6h, configurable | Phase 3 |
| Q9 | `--light` mode scope? | skip forecast, top-1 watcher only | Phase 1 retro |
| Q10 | Web dashboard? | no for MVP; markdown + terminal sufficient | (out of 5-phase scope) |

### 5.6 Phase 1 mandatory mitigations

After deferring T1/T2 to Phase 5 (POC has unlimited tokens + 7d trial sufficient):

1. **D2** — README "limitations" section documenting public-RSS density gap.
2. **M3** — vote-protocol with posterior cap [0.5, 1.5].
3. **M4** — invalidator-lint specificity check (numeric + temporal + asset/event).
4. **P1** — digest disclaimer + conviction + split warning.
5. **P2** — `regime_marker` field placeholder in jsonl (full detection in Phase 4).

---

## §6 Build Order & Milestones

> Time estimates are calendar days assuming 4–6 hours/day of LLM-assisted implementation.

### Phase 1: Core Engine (POC, 5–8 days)

Goal: prove multi-role voting in financial setting, with sample-data inputs.

| Milestone | Output | Exit condition |
|---|---|---|
| **M1.1** Plugin scaffold | `.claude-plugin/plugin.json` + empty `commands/`/`agents/`; `/opc-ir-init` + `/opc-ir-status` minimal stubs | `claude plugin install ../opc-ir` succeeds; status reports "Phase 1 POC" |
| **M1.2** Roles + pipeline (fork from OPC) | 5 schools + 2 advocates + 5 strategists; OPC verbatim files (with frontmatter `forked-from`); new pipeline files; `defaults/*.yaml` priors=1.0; `INHERITS-FROM-OPC.md` | All role files pass OPC role-spec validation |
| **M1.3** Forecast flow | `/opc-ir-forecast` + synthesizer + role-evaluator; uses sample world-model.md fixture; ASCII bars (Q3) | Manual run produces forecast.jsonl/md; jsonl includes 5-strategist votes + dissent + invalidators |
| **M1.4** Verdict flow | `/opc-ir-verdict` + verdict-judge; uses sample fixtures | Manual `/opc-ir-verdict NDX` produces verdicts.jsonl + theses/NDX.md + digest.md; falsifier-missing fixture correctly rejected by gate |
| **M1.5** Phase 1 risk mitigations | M3 cap, M4 specificity check, P1 disclaimer template, P2 placeholder field, D2 README section | `docs/ARCHITECTURE.md` cross-references each mitigation to file location |

**Phase 1 exit**: from-zero install + sample fixtures → 3 commands → readable digest. Both lint gates exercised at least once.

### Phase 2: Memory Layer (5–7 days)

| Milestone | Output | Exit |
|---|---|---|
| M2.1 triage | `agents/triage-classifier.md` + `dimension-weights.yaml` + `triage-thresholds.yaml` | 10 sample events → §3.2-conformant triage.json |
| M2.2 7 watchers | `roles/_watchers/*.md` × 7 | each independently dispatchable; single-failure does not block others |
| M2.3 evolve full chain | `commands/opc-ir-evolve.md` (no ingestion yet) | batch events → world-model.md readable + jsonl deltas recorded; hard-rule writes trigger marker |
| M2.4 thesis history | theses/{ticker}.md rewrite with History section (Q6) | second verdict on same ticker preserves first stance |

### Phase 3: Auto-loop Polish (4–5 days)

| Milestone | Output |
|---|---|
| M3.1 fetch-rss + dedup + per-source fault tolerance | bin/fetch-rss.sh + sources.yaml ≥10 |
| M3.2 evolve integrates ingestion | Step 1 active in evolve |
| M3.3 hard-rule async trigger marker consumption | next-tick consumption pattern |
| M3.4 helper commands | `--light`, `--dry-run`, `--inject-event` |

### Phase 4: Calibration (6–8 days)

| Milestone | Output |
|---|---|
| M4.1 price truth | bin/fetch-prices.sh + ground-truth-linker.sh; multi-source fallback |
| M4.2 event truth | verdict-judge in calibration mode |
| M4.3 posterior calc | N≥30 floor, cap [0.5, 1.5], anomaly rejection |
| M4.4 regime detection | 30d Brier deterioration → reset + digest warning (P2 full) |
| M4.5 events.jsonl monthly rolling (D4) | monthly file split with cross-month grep |

### Phase 5: Scheduling Abstraction + Premium (5–7 days)

| Milestone | Output |
|---|---|
| M5.1 scheduler abstraction | `/loop` / Desktop / Routine backends |
| M5.2 quota & expiry visibility (T1, T2) | status reports tokens/quota/loop-expiry |
| M5.3 premium-source framework | `defaults/sources.yaml` `type: api` + secrets.env conventions; PREMIUM-SOURCES.md |
| M5.4 plugin integrity check (T6) | install lock + status SHA |

### Dependency graph

```
Phase 1 ─┬─ M1.1
         ├─ M1.2
         ├─ M1.3 (depends on M1.1, M1.2)
         ├─ M1.4 (depends on M1.1, M1.2)  -- M1.3 and M1.4 parallelizable
         └─ M1.5 (depends on M1.3, M1.4)
                          │
Phase 2 ─┬─ M2.1          │
         ├─ M2.2 (M2.1)   │
         ├─ M2.3 (M2.1, M2.2)
         └─ M2.4 (M1.4)
                          │
Phase 3 ─┬─ M3.1
         ├─ M3.2 (M2.3, M3.1)
         ├─ M3.3 (M3.2)
         └─ M3.4 (M3.2)
                          │
Phase 4 ─┬─ M4.1 (Phase 1, 2 jsonl)
         ├─ M4.2
         ├─ M4.3 (M4.1, M4.2)
         ├─ M4.4 (M4.3)
         └─ M4.5
                          │
Phase 5 ── M5.x
```

### Total timeline

| Phase | Effort | Cumulative |
|---|---|---|
| Phase 1 | 5–8 d | 5–8 |
| Phase 2 | 5–7 d | 10–15 |
| Phase 3 | 4–5 d | 14–20 |
| Phase 4 | 6–8 d | 20–28 |
| Phase 5 | 5–7 d | 25–35 |

**MVP-publishable point**: end of Phase 3 (14–20 days) — auto-running plugin produces world-model + forecast + verdict + digest, lacking only calibration learning. Phase 4 is the quality flywheel; Phase 5 is long-term productionization.

### Next plan

The `superpowers:writing-plans` skill will be invoked next, with **Phase 1 (M1.1–M1.5) as the input scope**. Phase 2–5 each get their own plan after their predecessor completes; we do not pre-write all plans.

---

## Appendix A: Glossary

- **Verdict** — single-asset judgment (long/short/neutral + conviction + horizon + falsifier).
- **Forecast** — multi-asset probability distribution over time horizons.
- **World-Model** — 7-dimension macro snapshot continuously updated from events.
- **Thesis** — persistent narrative for a ticker, accumulated across verdicts.
- **Falsifier / Invalidator** — explicit condition under which the prediction/thesis is admitted invalid.
- **Brier score** — mean squared distance between predicted probability distribution and one-hot truth.
- **Cold start** — period before N≥30 samples per role; posterior weights inactive, prior used.
- **Regime change** — structural shift in market dynamics making historical calibration obsolete.
- **Hard-rule** — pre-defined event categories that auto-trigger verdicts (central bank policy, war, top-10 earnings, market halt).
- **Run-id** — unique identifier per evolve/forecast/verdict invocation, enabling immutable lineage across jsonl files.
