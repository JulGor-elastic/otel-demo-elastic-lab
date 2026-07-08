# Environment setup

This lab **does not provision cloud infrastructure**. You provide an existing Linux VM with SSH access; Ansible installs the stack on that machine.

This document covers:

1. [VM requirements](#vm-requirements)
2. [Example: create a GCP VM with gcloud](#example-create-a-gcp-vm-with-gcloud) (documentation only — not automated by this repo)
3. [Configuration files](#configuration-files)
4. [Elastic Cloud prerequisites](#elastic-cloud-prerequisites)
5. [Optional capabilities](#optional-capabilities)

---

## VM requirements

The Ansible playbooks install **Docker**, **Minikube**, **kubectl**, and **Helm**, then run the OTel Demo and EDOT stack inside Minikube.

| Requirement | Recommendation | Why |
|-------------|----------------|-----|
| OS | Ubuntu 22.04 or 24.04 LTS | Tested path; other Debian-based distros may work |
| vCPUs | **≥ 4** | Minikube is configured with 4 CPUs |
| RAM | **≥ 12 GB** | Minikube uses 12 GB; OTel Demo + Prometheus + Grafana is memory-heavy |
| Disk | **≥ 40 GB** free | Minikube image + container layers |
| Network | **Outbound internet** | Pull Helm charts, container images, Elastic Cloud ingest |
| Inbound | **SSH only** (from your workstation) | No public storefront required; access via SSH tunnel |
| User | sudo-capable account | Ansible runs `become: yes` for Docker/Minikube |

**Not required on the VM:** Node.js, npm, or Elastic Agent on the host (Synthetics agent runs in-cluster; monitor push uses Kibana API from your laptop).

### After Ansible deploy

On the VM you will also need a **persistent port-forward** for storefront access (e.g. in `screen`):

```bash
sudo kubectl port-forward svc/frontend-proxy 8080:8080 \
  --address=127.0.0.1 -n otel-demo
```

From your workstation: `make demo-tunnel` (see `config.mk`).

---

## Example: create a GCP VM with gcloud

**Reference only.** The repo does not run these commands. Adapt region, project, and names to your environment.

```bash
export PROJECT_ID="your-gcp-project"
export ZONE="europe-west1-b"
export VM_NAME="otel-demo-lab"
export MACHINE_TYPE="e2-standard-8"   # 8 vCPU, 32 GB — comfortable headroom

gcloud config set project "${PROJECT_ID}"

gcloud compute instances create "${VM_NAME}" \
  --zone="${ZONE}" \
  --machine-type="${MACHINE_TYPE}" \
  --image-family=ubuntu-2404-lts-amd64 \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=50GB \
  --tags=ssh-access

# SSH (generates ~/.ssh/google_compute_engine if needed)
gcloud compute ssh "${VM_NAME}" --zone="${ZONE}"
```

Note the **external IP** for `hosts.ini` and the values for `config.mk` (`GCP_VM_NAME`, `GCP_ZONE`, `GCP_SSH_USER`).

Equivalent VMs on AWS, Azure, or on-prem are fine if they meet the [requirements](#vm-requirements) above.

---

## Configuration files

Copy examples once per environment:

```bash
cp vars.yml.example vars.yml
cp hosts.ini.example hosts.ini
cp config.mk.example config.mk
```

All three are **gitignored** except the `.example` templates.

### `hosts.ini` — SSH / Ansible inventory

| Setting | Example | Where to get it |
|---------|---------|-----------------|
| VM IP | `34.x.x.x` | Cloud console or `gcloud compute instances describe` |
| `ansible_user` | `julio` | Your SSH username on the VM |
| `ansible_ssh_private_key_file` | `~/.ssh/google_compute_engine` | Your SSH key path |

### `config.mk` — local Makefile overrides

Used mainly for `make demo-tunnel` (SSH port forwarding via `gcloud`).

| Variable | Purpose |
|----------|---------|
| `GCP_VM_NAME` | Instance name (for `gcloud compute ssh`) |
| `GCP_ZONE` | GCP zone |
| `GCP_SSH_USER` | SSH username |
| `LOCAL_PORT` | Local port for tunnel (default `8080`) |

### `vars.yml` — Elastic + Helm + optional features

#### Required for core deploy (`make deploy`)

| Variable | Purpose | Where to get it |
|----------|---------|-----------------|
| `elastic_motlp_endpoint` | mOTLP ingest URL (`:443` optional) | Kibana → Add data → OpenTelemetry → Elastic Distributions |
| `elastic_api_key` | API key (base64) | Same flow; needs ingest permissions |
| `edot_onboarding_id` | EDOT K8s onboarding UUID | Kibana → Add data → Kubernetes → OpenTelemetry |
| `helm_chart_*` / `elastic_agent_ref` | Pinned versions | Defaults in `vars.yml.example` usually fine |
| `otel_demo_namespace` | K8s namespace | Default `otel-demo` unless you changed the release |

**Derived automatically** from `elastic_motlp_endpoint` (override in `vars.yml` only if your project uses non-standard hostnames):

| Derived variable | Rule |
|------------------|------|
| `elastic_es_endpoint` | Replace `.ingest.` → `.es.`, strip `:443` — Grafana PromQL datasource |
| `elastic_prometheus_remote_write_url` | Ingest host + `/api/v1/write` — Prometheus Remote Write |

Logic lives in [`group_vars/all.yml`](../group_vars/all.yml). Legacy names `elastic_endpoint` / `elastic_token` still work in older `vars.yml` copies.

#### Optional — Demo scenarios + Workflows

| Variable | Purpose |
|----------|---------|
| `kibana_url` | Kibana base URL |
| `github_http_connector_id` | Kibana HTTP connector ID (see `scripts/workflows/create-github-connector.sh`) |
| `github_repo_owner` / `github_repo_name` | Fork of this lab repo |
| `github_ref` | Branch to trigger (e.g. `main`) |

Also: install the **GitHub Actions self-hosted runner** on the VM (`scripts/github/install-runner.sh`). See [demo-scenarios-setup.md](demo-scenarios-setup.md).

#### Optional — Synthetics Private Location

| Variable | Purpose |
|----------|---------|
| `fleet_url` | Fleet Server URL (`:443`) |
| `fleet_enrollment_token` | One-time enrollment token from Fleet policy |
| `fleet_agent_policy_name` | Fleet policy backing the Private Location |
| `synthetics_private_location_name` | Exact label of the Private Location in Kibana |

See [phase2-synthetics.md](phase2-synthetics.md). Monitor definitions: `synthetics/monitors.json` → `make synthetics-push` (needs `curl` + `jq` on your laptop only).

#### RUM (optional, partial)

RUM is configured in `otel-values.yaml.j2` (collector transforms). No extra `vars.yml` keys beyond core Elastic credentials. Dashboard tuning in Kibana is manual.

---

## Elastic Cloud prerequisites

One **Elastic Cloud Serverless** Observability project with:

- mOTLP ingest (traces, metrics, logs via EDOT)
- Prometheus Remote Write on the ingest endpoint
- Kibana access for dashboards, Workflows, Synthetics
- API key with sufficient privileges for your use case (ingest; plus Fleet/Synthetics if using optional Synthetics)

The playbooks do **not** create or configure the Elastic project — only the in-VM Kubernetes workloads and outbound telemetry.

---

## Optional capabilities

| Capability | Extra setup | Doc |
|------------|-------------|-----|
| Demo scenarios from Kibana | Runner + Workflows + `vars.yml` github block | [demo-scenarios-setup.md](demo-scenarios-setup.md) |
| Synthetics Private Location | Fleet policy + `vars.yml` synthetics block | [phase2-synthetics.md](phase2-synthetics.md) |
| Business orders dashboard | ES transform (script in repo) + Kibana Lens | `scripts/elasticsearch/` + internal notes |
| Orders transform | Run `create-orders-transform.sh` once | `scripts/elasticsearch/` |

---

## Minimal path to a working lab

1. Provision a VM meeting [requirements](#vm-requirements) (manual — see [GCP example](#example-create-a-gcp-vm-with-gcloud) if needed).
2. Configure `hosts.ini`, `vars.yml` (core block only), `config.mk`.
3. From your workstation: `make deploy` → `make demo-check`.
4. On VM: start `kubectl port-forward` to `frontend-proxy`.
5. From workstation: `make demo-tunnel` → open `http://localhost:8080`.

Add optional Synthetics or demo scenarios when you need them.
