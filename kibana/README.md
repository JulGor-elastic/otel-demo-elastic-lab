# Kibana lab artifacts

Exported JSON/YAML/NDJSON for optional lab deployment.

## First-time setup (maintainer)

From a reference Elastic project where objects are configured:

```bash
./scripts/kibana/export-from-kibana.sh
git add kibana/
git commit -m "Export Kibana lab objects"
```

Source IDs are listed in `manifest.yaml` (from `llm-context/objects_from_kibana.md`).

## Deploy on a new lab

```bash
# vars.yml: kibana_url, elastic_api_key, rca_notification_email, github_* (for scenarios)
make kibana-deploy
```

Skips existing objects by default. To force update:

```bash
KIBANA_DEPLOY_OVERWRITE=1 make kibana-deploy
```

## Layout

| Path | Content |
|------|---------|
| `workflows/` | RCA workflow YAML (`__RCA_NOTIFICATION_EMAIL__` placeholder) |
| `saved_objects/` | Dashboard + alerting rule (NDJSON) |
| `agent_builder/tools/` | Agent Builder tool definitions |
| `agent_builder/skills/` | Agent Builder skill definitions |
| `agent_builder/agents/` | Reference export of `elastic-ai-agent` |

Transform `otel-demo-orders-latest` lives in `scripts/elasticsearch/` (not here).

OTel Demo scenario workflows live in `scripts/workflows/otel-demo-*.yaml`.
