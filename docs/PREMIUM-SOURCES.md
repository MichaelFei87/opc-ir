# Premium Sources Guide

OPC-IR ships with 10+ free RSS sources for macro analysis. For users with access
to premium data providers, the plugin supports API-based sources.

## Quick Start

1. **Get credentials** from your data provider

2. **Add credentials** to `~/.opc-ir/config/secrets.env`:
   ```bash
   touch ~/.opc-ir/config/secrets.env
   chmod 600 ~/.opc-ir/config/secrets.env
   echo 'NEWSAPI_KEY=abc123' >> ~/.opc-ir/config/secrets.env
   ```

3. **Enable the source** in `~/.opc-ir/config/local.yaml`:
   ```yaml
   sources:
     newsapi:
       enabled: true
   ```

4. **Verify**: `/opc-ir-evolve --dry-run`

## Supported Premium Sources

| Source | Env Variable | Dimensions | Rate Limit |
|---|---|---|---|
| Bloomberg API | `BLOOMBERG_API_KEY` | econ, corp, energy | 100/hr |
| Refinitiv/LSEG | `REFINITIV_APP_KEY` | econ, corp | 500/hr |
| NewsAPI | `NEWSAPI_KEY` | politics, econ, tech | 1000/day |
| TradingView | `TRADINGVIEW_SESSION_ID` | econ, corp | best effort |

## Security

- `secrets.env` is in `~/.opc-ir/config/` — outside the plugin repo
- Never committed to git
- File permissions should be `600` (owner read/write only)
- Keys loaded at fetch time only, never logged or persisted in events.jsonl

## Adding Custom API Sources

Add to `~/.opc-ir/config/local.yaml`:

```yaml
sources:
  my-custom-api:
    type: api
    endpoint: "https://api.example.com/v1/news"
    auth_env: MY_CUSTOM_API_KEY
    auth_header: "Authorization: Bearer"
    dimensions: [econ-finance, tech-ai]
    enabled: true
```

Then add `MY_CUSTOM_API_KEY=...` to `secrets.env`.
