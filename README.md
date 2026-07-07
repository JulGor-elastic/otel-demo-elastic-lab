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

- A GCP VM with outbound internet access (Ubuntu recommended, `e2-standard-8` or similar)
- SSH access from your workstation (`gcloud compute ssh` or standard SSH)
- [Ansible](https://docs.ansible.com/) on your local machine
- An Elastic Cloud Serverless project with:
  - mOTLP ingest endpoint and API key (OTLP via EDOT)
  - Prometheus Remote Write ingest URL (Ingest endpoint + `/api/v1/write`)
  - EDOT Kubernetes onboarding ID (Kibana → **Add data** → **Kubernetes** → **OpenTelemetry**)

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
| `vars.yml` | Elastic mOTLP endpoint, **ES query endpoint** (`elastic_es_endpoint`), API key, onboarding ID, Prometheus Remote Write URL, Helm versions |
| `config.mk` | GCP VM name, zone, SSH user (for `make demo-tunnel`) |

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

Grafana dashboards include a **Data Source** variable (`DS_PROMETHEUS`). After deploy, switch between **Prometheus** (in-cluster) and **Elasticsearch** (PRW via PromQL API) to compare the same metrics. Requires `elastic_es_endpoint` in `vars.yml`. See `llm-context/grafana_dashboards.md`.

## Demo scenarios (Phase 4)

Trigger incident / recovery scripts on the lab VM from **Elastic Workflows** in Serverless, without exposing inbound ports:

```
Kibana Workflows  →  GitHub API (workflow_dispatch)  →  self-hosted runner on VM  →  kubectl
```

| Scenario | Effect |
|----------|--------|
| `incident-payment` | Scale `payment` to 0 — checkout fails, orders KPI flatlines |
| `recover-payment` | Restore `payment` |
| `oom-pressure` | Lower `fraud-detection` memory → OOMKill |
| `reset-lab` | Full stable-state restore |

### Local run (Ansible → VM)

```bash
make demo-scenario-incident-payment
make demo-scenario-reset-lab
```

### Elastic Workflows setup

1. Push this repo to GitHub.
2. On the VM: install self-hosted runner (`scripts/github/install-runner.sh`).
3. Create GitHub HTTP connector in Kibana; set `github_http_connector_id` in `vars.yml`.
4. Deploy workflows: `./scripts/workflows/deploy-workflows.sh` (needs `kibana_url` + API key).

Details: `llm-context/phase4_remote_control.md`.

## Makefile targets

| Target | Description |
|--------|-------------|
| `make deploy` | Full deployment via Ansible |
| `make demo-upgrade` | Re-apply Helm values only (Grafana datasource, collector tweaks, etc.) |
| `make demo-check` | Smoke tests without redeploying |
| `make demo-tunnel` | SSH tunnel to the demo frontend |
| `make demo-scenario-<name>` | Run scenario on VM (`incident-payment`, `recover-payment`, `reset-lab`, `oom-pressure`) |
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
├── deploy.yml              # Main Ansible playbook
├── check.yml               # Standalone smoke tests
├── otel-values.yaml.j2     # Helm values for the OTel Demo
├── tasks/smoke_test.yml    # Shared smoke test tasks
├── scripts/
│   ├── wait-otel-demo-ready.sh   # Ordered pod readiness + remediation
│   ├── scenarios/                # Phase 4 demo scenarios (kubectl)
│   ├── workflows/                # Elastic Workflows YAML + deploy scripts
│   └── github/install-runner.sh  # Self-hosted Actions runner setup
├── vars.yml.example        # Elastic / Helm configuration template
├── hosts.ini.example       # Ansible inventory template
├── config.mk.example       # Local GCP / SSH overrides template
└── Makefile
```

## Known limitations

- **VM provisioning** is manual (GCP `gcloud`); Terraform automation is planned.
- **Pod startup order**: on resource-constrained Minikube, some services may start before their dependencies. The wait script restarts flagd-dependent deployments and applies rollout restarts; `ad` / `fraud-detection` memory is raised to 512Mi in Helm values (needed after enabling Prometheus/Grafana).
- **Smoke tests** fail on OOMKilled or non-Ready pods, not only HTTP checks.

## Roadmap

- ~~Prometheus Remote Write → Elastic~~ (implemented)
- ~~Grafana in-cluster~~ (implemented; dashboard migration to Kibana pending)
- ~~Demo scenarios + Elastic Workflows~~ (Phase 4 — scripts + workflow YAML; runner setup manual)
- Elastic RUM and Synthetics
- Business-order indexing for demo narratives
- Full IaC (Terraform) for GCP and Elastic stack objects

## License

See repository license file when published.
