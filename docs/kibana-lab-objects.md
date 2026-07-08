# Kibana lab objects (optional)

Deploy dashboards, alerting rules, RCA workflows, and Agent Builder skills/tools alongside the OTel Demo lab.

Deployment is **optional** and **non-destructive by default** — existing objects in the target project are not overwritten unless you set `KIBANA_DEPLOY_OVERWRITE=1`.

## What gets deployed (order)

| Step | Component | Source in repo |
|------|-----------|----------------|
| 1 | Transform `otel-demo-orders-latest` | `scripts/elasticsearch/` |
| 2 | OTel Demo scenario workflows | `scripts/workflows/otel-demo-*.yaml` |
| 3 | RCA workflow (AI, human in the loop) | `kibana/workflows/` |
| 4 | Agent Builder tools | `kibana/agent_builder/tools/` |
| 5 | Agent Builder skills | `kibana/agent_builder/skills/` |
| 6 | Assign skills to `elastic-ai-agent` | manifest in `kibana/manifest.yaml` |
| 7 | Business dashboard + checkout alert rule | `kibana/saved_objects/lab-objects.ndjson` |

## Configuration (`vars.yml`)

```yaml
kibana_url: "https://YOUR_PROJECT.kb.REGION.aws.elastic.cloud"
elastic_api_key: "YOUR_BASE64_API_KEY"

# RCA workflow email notifications (never commit your personal address)
rca_notification_email: "you@example.com"

# Required for scenario workflows (step 2)
github_http_connector_id: "otel-demo-github"
github_repo_owner: "YOUR_GITHUB_USER"
github_repo_name: "YOUR_REPO"
```

`elastic_es_endpoint` is derived from `elastic_motlp_endpoint` for the transform step.

### API key privileges

Minimum for full deploy:

- Ingest / transform management on Elasticsearch
- `workflowsManagement:create` (and read for skip checks)
- `agentBuilder:manageTools`, `manageSkills`, `manageAgents` (or read + create)
- Kibana saved object import

Use separate keys for production vs lab if your security policy requires it.

## Export from your reference project (maintainer)

When you change objects in Kibana, re-export into the repo:

```bash
./scripts/kibana/export-from-kibana.sh
```

This:

- Pulls dashboard `5c9b8fc2-…`, rule `ff3d48a2-…`, RCA workflow, tools, skills, and agent reference
- **Redacts email addresses** in the RCA workflow to `__RCA_NOTIFICATION_EMAIL__`

Review the diff before committing — no personal emails should appear.

## Deploy

```bash
make kibana-deploy
# or: ./scripts/kibana/deploy-kibana-lab.sh
```

Force overwrite of existing Kibana objects:

```bash
KIBANA_DEPLOY_OVERWRITE=1 make kibana-deploy
```

## Dependencies

```text
transform otel-demo-orders-latest
        │
        ├──► dashboard (orders business)
        └──► tool orders_incident_revenue_impact
                    └──► skill incident-business-impact

workflows otel-demo-* (reset-lab, incidents, …)
        │
        └──► tool recover_lab_environment
                    └──► skill deployment-remediation

workflow RCA ──► alert rule (failed transaction rate checkout)

skills (×3) ──► assigned to agent elastic-ai-agent
```

## Related docs

- [Demo scenarios setup](demo-scenarios-setup.md) — GitHub runner + connector (step 2)
- [Environment setup](environment-setup.md) — `vars.yml` reference
