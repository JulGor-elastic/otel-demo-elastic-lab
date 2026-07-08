# OTel Demo + Elastic Observability Lab

[![GitHub](https://img.shields.io/github/stars/JulGor-elastic/otel-demo-elastic-lab?style=social)](https://github.com/JulGor-elastic/otel-demo-elastic-lab)

Ansible-based lab to deploy the [OpenTelemetry Demo](https://github.com/open-telemetry/opentelemetry-demo) on a GCP VM (Minikube) and ship logs, metrics, and traces to **Elastic Cloud** via the **EDOT Collector**.

> **Public repo:** [github.com/JulGor-elastic/otel-demo-elastic-lab](https://github.com/JulGor-elastic/otel-demo-elastic-lab) — used as the orchestration bridge between Elastic Serverless Workflows and the lab VM (GitHub Actions self-hosted runner).

## Architecture

```
OTel SDKs (microservices)
  → OTel Contrib Collector (demo)
    → EDOT Collector Gateway (in-cluster)
      → mOTLP endpoint (Elastic Cloud Serverless)
        → Elasticsearch

K8s node logs
  → EDOT Collector Daemon
    → mOTLP endpoint (Elastic Cloud Serverless)

Prometheus (in-cluster, short retention)
  → Remote Write → Elastic Cloud Serverless
    → metrics-{dataset}.prometheus-{namespace}
```

Jaeger and OpenSearch are disabled. **OTLP** (via EDOT) and **Prometheus Remote Write** are both active. Grafana runs in-cluster for PromQL dashboards and migration to Kibana.

## Prerequisites

You provide an existing Linux VM; this repo does not create cloud infrastructure.

- **VM:** Ubuntu 22.04/24.04, ≥ 4 vCPU, ≥ 12 GB RAM, ≥ 40 GB disk, outbound internet, SSH access  
- **Workstation:** [Ansible](https://docs.ansible.com/), `curl`, `jq` (for Synthetics monitor push)  
- **Elastic Cloud Serverless** project with mOTLP, Prometheus Remote Write, and Kibana access  

**Full requirements, example `gcloud` commands, and configuration reference:**  
→ **[docs/environment-setup.md](docs/environment-setup.md)**

**Project status and roadmap:**  
→ **[docs/action-plan.md](docs/action-plan.md)**

## Quick start

### 1. Configure

Copy the example files and fill in your values:

```bash
cp vars.yml.example vars.yml
cp hosts.ini.example hosts.ini
cp config.mk.example config.mk
```

| File | Purpose |
|------|---------|
| `hosts.ini` | VM IP address and SSH settings |
| `vars.yml` | Elastic credentials + Helm pins — see [environment-setup.md](docs/environment-setup.md) |
| `config.mk` | GCP VM name, zone, SSH user (for `make demo-tunnel`) |

**Optional keys in `vars.yml`** (add when you need those features):

| Variable | Used for |
|----------|----------|
| `rca_notification_email` | Email recipient in the RCA workflow (`make kibana-deploy`) |
| `github_*` | Demo scenario workflows — [demo-scenarios-setup.md](docs/demo-scenarios-setup.md) |
| `fleet_*`, `synthetics_*` | Synthetics — [phase2-synthetics.md](docs/phase2-synthetics.md) |

Copy from `vars.yml.example` (lines 38–55). If `rca_notification_email` is missing, `make kibana-deploy` falls back to `you@example.com`.

### 2. Deploy

```bash
make deploy
# or: ansible-playbook -i hosts.ini deploy.yml
```

The playbook:

- Installs Docker, Minikube, kubectl, and Helm on the VM
- Deploys the EDOT Kube Stack (Elastic Distro for OpenTelemetry)
- Deploys the OTel Demo with pinned Helm chart versions
- Waits for pods in dependency order (`scripts/wait-otel-demo-ready.sh`)
- Runs smoke tests against `frontend-proxy`

### 3. Verify

```bash
make demo-check
```

### 4. Access the demo storefront

On the VM, start port-forwarding (e.g. in `screen`):

```bash
sudo kubectl port-forward svc/frontend-proxy 8080:8080 \
  --address=127.0.0.1 -n otel-demo
```

From your workstation:

```bash
make demo-tunnel
# Storefront:  http://localhost:8080
# Grafana:     http://localhost:8080/grafana
```

### Prometheus Remote Write

Prometheus keeps metrics locally for **30 minutes** (configurable via `prometheus_retention` in `vars.yml`) and ships them to Elastic via Remote Write.

Default data stream: `metrics-otel_demo.prometheus-default` (set `prometheus_data_stream_dataset` to match ES; PRW maps hyphens to underscores). Override namespace with `prometheus_data_stream_namespace`.

Grafana dashboards include a **Data Source** variable (`DS_PROMETHEUS`). After deploy, switch between **Prometheus** (in-cluster) and **Elasticsearch** (PRW via PromQL API) to compare the same metrics. `elastic_es_endpoint` is derived from `elastic_motlp_endpoint` automatically (see `group_vars/all.yml`).

## Deploying a new lab

End-to-end checklist for a **fresh VM + Elastic Serverless project**. Only step 1 is required; the rest are optional and safe to run in any order (each step skips objects that already exist).

### 1. Core stack (required)

| Step | Action |
|------|--------|
| VM | Provision Ubuntu VM (≥ 4 vCPU, 12 GB RAM) — see [environment-setup.md](docs/environment-setup.md) |
| Config | `cp vars.yml.example vars.yml` (+ `hosts.ini`, `config.mk`) — fill `elastic_motlp_endpoint`, `elastic_api_key`, `edot_onboarding_id` |
| Deploy | `make deploy` |
| Verify | `make demo-check` |
| Access | Port-forward on VM + `make demo-tunnel` → http://localhost:8080 |

Telemetry (traces, logs, metrics, Grafana) is live after this step.

### 2. Kibana objects (optional)

Business orders transform, dashboards, alerting rule, RCA workflow, and Agent Builder skills/tools — bundled in one deploy:

```bash
# vars.yml — required for this step:
rca_notification_email: "your.name@company.com"

make kibana-deploy
```

Uses `rca_notification_email` from `vars.yml` to replace `__RCA_NOTIFICATION_EMAIL__` in the RCA workflow YAML before pushing to Kibana. Your personal address is **not** stored in git (export redacts emails to the placeholder).

If you already deployed with the wrong address, re-run with the correct email:

```bash
KIBANA_DEPLOY_OVERWRITE=1 make kibana-deploy
```

Deploy order inside the script: transform → scenario workflows (if `github_*` set) → RCA workflow → Agent Builder tools/skills → dashboard + alert rule.

Details: **[docs/kibana-lab-objects.md](docs/kibana-lab-objects.md)**

To refresh objects from a reference project (maintainers): `make kibana-export` → commit `kibana/`.

### 3. Demo scenarios (optional)

Remote incidents from Kibana Workflows or GitHub Actions (requires fork, self-hosted runner, GitHub connector):

1. Complete `github_*` in `vars.yml`
2. Install runner on VM — [demo-scenarios-setup.md](docs/demo-scenarios-setup.md)
3. `make kibana-deploy` (includes `scripts/workflows/deploy-workflows.sh`) or run that script alone
4. Test: `make demo-scenario-incident-payment` or trigger from Kibana **Workflows**

### 4. Synthetics (optional)

In-cluster HTTP/TCP monitors via Private Location:

```bash
# vars.yml — fleet_url, fleet_enrollment_token, synthetics_private_location_name
make synthetics-setup      # first time
make synthetics-push       # after editing synthetics/monitors.json
```

Guide: **[docs/phase2-synthetics.md](docs/phase2-synthetics.md)**

### Quick reference — optional components

| Component | Command / doc |
|-----------|-----------------|
| Kibana (orders, RCA, Agent Builder) | `make kibana-deploy` → [kibana-lab-objects.md](docs/kibana-lab-objects.md) |
| Demo scenarios + Workflows | [demo-scenarios-setup.md](docs/demo-scenarios-setup.md) |
| Synthetics | `make synthetics-setup` → [phase2-synthetics.md](docs/phase2-synthetics.md) |

Force-update existing Kibana objects: `KIBANA_DEPLOY_OVERWRITE=1 make kibana-deploy`

---

## Optional: Demo scenarios (remote automation)

Orchestrate incident and recovery scripts on the lab VM from **GitHub Actions** or **Elastic Serverless Workflows**, without inbound access to the VM.

| Scenario | Effect |
|----------|--------|
| `incident-payment` | Scale `payment` to 0 — checkout fails |
| `incident-postgresql` | Scale `postgresql` to 0 — shared DB outage |
| `incident-valkey-cart` | Scale `valkey-cart` to 0 — cart cache down |
| `incident-kafka` | Scale `kafka` to 0 — async messaging outage |
| `recover-payment` | Restore `payment` |
| `oom-pressure` | Lower `fraud-detection` memory → OOMKill |
| `reset-lab` | Restore infra + payment + memory; full wait script |

**Full setup guide (fork, runner, GitHub Actions, Kibana Workflows):**  
→ **[docs/demo-scenarios-setup.md](docs/demo-scenarios-setup.md)**

Quick local test (Ansible → VM):

```bash
make demo-scenario-incident-payment
make demo-scenario-reset-lab
```

## Optional: Synthetics

Private Location + HTTP/TCP monitors from inside the cluster. **No Node.js** — monitors are pushed via Kibana API (`curl` + `jq`).

**Full guide:** → **[docs/phase2-synthetics.md](docs/phase2-synthetics.md)**

```bash
make synthetics-setup      # first time: agent + location + monitors
make synthetics-push       # after editing synthetics/monitors.json
```

## Makefile targets

| Target | Description |
|--------|-------------|
| `make deploy` | Full deployment via Ansible |
| `make demo-upgrade` | Re-apply Helm values only (Grafana datasource, collector tweaks, etc.) |
| `make demo-check` | Smoke tests without redeploying |
| `make demo-tunnel` | SSH tunnel to the demo frontend |
| `make demo-scenario-<name>` | Run scenario on VM (`incident-payment`, `recover-payment`, `reset-lab`, `oom-pressure`) |
| `make synthetics-setup` | Deploy Fleet agent + Private Location + push monitors |
| `make synthetics-deploy` | Deploy `elastic-synthetics-agent` pod only |
| `make kibana-export` | Export Kibana lab objects from your reference project |
| `make kibana-deploy` | Deploy optional Kibana objects (dashboard, RCA, Agent Builder) |
| `make help` | List available targets |

## Pinned Helm versions

Configured in `vars.yml` (see `vars.yml.example`):

| Chart | Version |
|-------|---------|
| `opentelemetry-demo` | 0.40.9 |
| `opentelemetry-kube-stack` (EDOT) | 0.12.4 |
| `elastic-agent` ref (EDOT values) | v9.4.2 |

## Project layout

```
├── group_vars/all.yml      # Derived Elastic URLs from elastic_motlp_endpoint
├── deploy.yml              # Main Ansible playbook
├── check.yml               # Standalone smoke tests
├── otel-values.yaml.j2     # Helm values for the OTel Demo
├── tasks/smoke_test.yml    # Shared smoke test tasks
├── scripts/
│   ├── wait-otel-demo-ready.sh   # Ordered pod readiness + remediation
│   ├── scenarios/                # Demo scenario scripts (kubectl)
│   ├── workflows/                # Elastic Workflows YAML + deploy scripts
│   ├── synthetics/               # Fleet, Private Location, Kibana API push
│   ├── kibana/                   # Export + deploy Kibana lab objects
│   └── github/install-runner.sh  # Self-hosted Actions runner setup
├── synthetics/
│   ├── monitors.json             # Synthetics monitor definitions
│   └── retired-monitors.json     # Optional: names to remove on push
├── kibana/                 # Exported Kibana artifacts (optional deploy)
├── docs/
│   ├── action-plan.md            # Internal roadmap / status (maintainer)
│   ├── environment-setup.md      # VM requirements, vars.yml reference
│   ├── demo-scenarios-setup.md   # Fork, runner, Workflows (full guide)
│   ├── kibana-lab-objects.md     # Optional dashboard, RCA, Agent Builder
│   └── phase2-synthetics.md      # Synthetics Private Location setup
├── vars.yml.example        # Elastic / Helm configuration template
├── hosts.ini.example       # Ansible inventory template
├── config.mk.example       # Local GCP / SSH overrides template
└── Makefile
```

## Known limitations

- **VM provisioning** is the user's responsibility; see [docs/environment-setup.md](docs/environment-setup.md) for requirements and an example `gcloud` command.
- **Pod startup order**: on resource-constrained Minikube, some services may start before their dependencies. The wait script restarts flagd-dependent deployments and applies rollout restarts; `ad` / `fraud-detection` memory is raised to 512Mi in Helm values (needed after enabling Prometheus/Grafana).
- **Smoke tests** fail on OOMKilled or non-Ready pods, not only HTTP checks.
- **Synthetics Private Locations** on Elastic 9.4.x: creating new locations may fail; reuse an existing location (see [phase2-synthetics.md](docs/phase2-synthetics.md)).

Maintainer roadmap: [docs/action-plan.md](docs/action-plan.md).

## License

See repository license file when published.
