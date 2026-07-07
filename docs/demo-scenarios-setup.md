# Demo scenarios — setup guide

This guide explains how to orchestrate **incident and recovery scenarios** on your lab VM from **Elastic Serverless Workflows** (or manually from GitHub), without exposing the VM to inbound traffic from Elastic Cloud.

It covers repository setup, the self-hosted GitHub Actions runner, workflow testing, and optional Kibana Workflows deployment.

---

## Why you need your own GitHub repository

The upstream repo ([JulGor-elastic/otel-demo-elastic-lab](https://github.com/JulGor-elastic/otel-demo-elastic-lab)) is a **reference implementation**. You **cannot** register a self-hosted runner or trigger workflows against someone else's repository unless you have admin access to that repo.

Each lab operator needs **their own copy** of the code on GitHub:

| Approach | When to use |
|----------|-------------|
| **Fork** | Quick start; keeps link to upstream; good for contributions |
| **New repository** | Corporate policy, rename, or clean history without fork badge |

In both cases you will:

1. Point `vars.yml` → `github_repo_owner` / `github_repo_name` at **your** repo.
2. Install the runner on **your** VM, registered to **your** repo.
3. Deploy Elastic Workflows that call **your** repo's `demo-scenarios.yml` workflow.

You do **not** need to modify application code unless you add custom scenarios.

---

## Architecture

```
┌──────────────────────────┐
│ Elastic Serverless       │
│ Kibana Workflows         │──┐
└──────────────────────────┘  │ HTTPS (outbound)
                              ▼
                    ┌─────────────────────┐
                    │ GitHub API          │
                    │ workflow_dispatch   │
                    └──────────┬──────────┘
                               │ poll (outbound)
                               ▼
                    ┌─────────────────────┐
                    │ Self-hosted runner  │
                    │ on your GCP VM      │
                    │ scripts/scenarios/* │
                    └──────────┬──────────┘
                               │ kubectl (sudo)
                               ▼
                    ┌─────────────────────┐
                    │ Minikube / otel-demo│
                    └─────────────────────┘
```

**Security constraint:** Elastic Cloud cannot reach your VM inbound. All control paths are **outbound** from the VM or from Kibana to public APIs (GitHub).

---

## Prerequisites

- A working OTel Demo deployment on a GCP VM (see [README](../README.md) — `make deploy`).
- SSH access to the VM as a non-root user (e.g. `julio`) with `sudo` for `kubectl` (Minikube kubeconfig is under `/root/.kube/config`).
- A **GitHub account** and a repository you control (fork or new repo).
- (Optional, for Kibana orchestration) Elastic Cloud Serverless **9.4+** with **Workflows** enabled and an API key with `workflowsManagement:create`.

---

## Step 1 — Get your own GitHub repository

### Option A: Fork

1. Open https://github.com/JulGor-elastic/otel-demo-elastic-lab
2. Click **Fork** → choose your account or org.
3. Clone your fork on the VM:

```bash
sudo mkdir -p /opt/otel-demo-lab
sudo git clone https://github.com/YOUR_USER/otel-demo-elastic-lab.git /opt/otel-demo-lab
sudo chown -R $USER:$USER /opt/otel-demo-lab
```

### Option B: New repository

1. Create an empty repo on GitHub (public or private).
2. Push this project's contents to it (from your workstation):

```bash
git remote add origin https://github.com/YOUR_USER/YOUR_REPO.git
git push -u origin main
```

3. Clone on the VM as above, using your repo URL.

### Configure `vars.yml` (workstation)

Add or update the Phase 4 block in your local `vars.yml` (gitignored):

```yaml
kibana_url: "https://YOUR_PROJECT_ID.kb.REGION.aws.elastic.cloud"
github_http_connector_id: "otel-demo-github"
github_repo_owner: "YOUR_GITHUB_USER_OR_ORG"
github_repo_name: "YOUR_REPO_NAME"
github_ref: "main"
```

---

## Step 2 — Available scenarios

| Scenario | Script | Effect |
|----------|--------|--------|
| `incident-payment` | `scripts/scenarios/incident-payment.sh` | Scales `payment` to 0 — checkout fails |
| `incident-postgresql` | `scripts/scenarios/incident-postgresql.sh` | Scales `postgresql` to 0 — shared DB outage |
| `incident-valkey-cart` | `scripts/scenarios/incident-valkey-cart.sh` | Scales `valkey-cart` to 0 — cart cache down |
| `incident-kafka` | `scripts/scenarios/incident-kafka.sh` | Scales `kafka` to 0 — async messaging outage |
| `recover-payment` | `scripts/scenarios/recover-payment.sh` | Restores `payment` to 1 replica |
| `oom-pressure` | `scripts/scenarios/oom-pressure.sh` | Lowers `fraud-detection` memory → OOMKill |
| `reset-lab` | `scripts/scenarios/reset-lab.sh` | Restores postgresql, kafka, valkey-cart, payment, memory |

GitHub Actions workflow: [`.github/workflows/demo-scenarios.yml`](../.github/workflows/demo-scenarios.yml)  
Runner labels required: `self-hosted`, `otel-demo`

---

## Step 3 — Create a GitHub Personal Access Token (PAT)

Used **once** to register the self-hosted runner (and optionally stored in Kibana for Workflows).

### Classic token (recommended)

1. https://github.com/settings/tokens → **Generate new token (classic)**
2. Note: e.g. `otel-demo-runner-install`
3. Scope: **`repo`** (full control of private repositories; sufficient for public repos too)
4. Copy the token (`ghp_...`) — shown only once.

### Fine-grained token (alternative)

- Repository access: **only your lab repo**
- Permissions: **Administration** Read and write, **Actions** Read and write, **Contents** Read

Revoke the install token after the runner is registered if you prefer; the runner keeps working without it.

---

## Step 4 — Install the self-hosted runner on the VM

### Important: do not run `config.sh` as root

GitHub's runner installer prints **`Must not run with sudo`** if `./config.sh` runs as root. The provided script registers the runner as your SSH user and only uses `sudo` for packages and the systemd service.

### Install

On the VM, as your **SSH user** (not `root`):

```bash
cd /opt/otel-demo-lab   # or your clone path

./scripts/github/install-runner.sh \
  --repo YOUR_USER/YOUR_REPO \
  --token ghp_YOUR_TOKEN \
  --user YOUR_SSH_USER \
  --dir /opt/actions-runner
```

| Flag | Description |
|------|-------------|
| `--repo` | Your `owner/repo` on GitHub |
| `--token` | PAT from Step 3 |
| `--user` | Unix user running the runner service (must match SSH user) |
| `--dir` | Install directory (default: `/home/<user>/actions-runner`) |

**Do not** use:

- `sudo ./scripts/github/install-runner.sh` as the primary invocation
- `sudo su` then run the script without `--user`

If your image ignores `sudo -E`, pass credentials via **`--repo` and `--token` flags** (not only `export`).

### Verify runner registration

1. GitHub → **your repo** → **Settings** → **Actions** → **Runners**
2. Expect: name `otel-demo-vm`, status **Idle**, labels `self-hosted`, `otel-demo`

### kubectl access

The workflow runs scenario scripts with:

```bash
sudo env KUBECONFIG=/root/.kube/config ...
```

Your SSH user must be able to run `sudo kubectl` without a password (default on GCP images with `google-sudoers`). Test:

```bash
sudo kubectl get pods -n otel-demo
```

---

## Step 5 — Test from GitHub Actions (manual)

1. GitHub → **your repo** → **Actions** → **Demo scenarios**
2. **Run workflow** → branch `main` → choose a scenario:
   - First run: **`reset-lab`** (safe baseline)
   - Incident demo: **`incident-payment`**
   - Recovery: **`recover-payment`** or **`reset-lab`**
3. Open the run → job **run-scenario** → confirm all steps are green.

### Verify on the VM

```bash
# After incident-payment
sudo kubectl get deployment payment -n otel-demo
# READY 0/0 or no payment pods

# After reset-lab
sudo kubectl get pods -n otel-demo | grep payment
# payment-* Running 1/1
```

---

## Step 6 — Run scenarios from your workstation (optional)

Without GitHub or Kibana — useful for debugging:

```bash
make demo-scenario-incident-payment
make demo-scenario-reset-lab
```

These sync `scripts/scenarios/` to the VM via Ansible and execute the script as root's kubeconfig.

---

## Step 7 — Connect Elastic Serverless Workflows (optional)

Trigger the same scenarios from **Kibana → Workflows** so demos don't require opening GitHub.

### 7.1 Create GitHub HTTP connector in Kibana

Store a GitHub PAT (needs **`repo`** + **`workflow`** for `workflow_dispatch`) in Kibana connectors — not in workflow YAML.

Use the **HTTP** connector type (`.http`, for Workflows). Do **not** use the generic **Webhook** connector (`.webhook`) — it uses a different schema and returns HTTP 400 with the install script's old payload.

**From your workstation:**

```bash
export KIBANA_URL="https://YOUR_PROJECT_ID.kb.REGION.aws.elastic.cloud"
export ELASTIC_API_KEY="YOUR_KIBANA_API_KEY"
export GITHUB_PAT="ghp_..."

./scripts/workflows/create-github-connector.sh
```

Note the connector ID (default: `otel-demo-github`) and set `github_http_connector_id` in `vars.yml`.

**Or via UI:** Kibana → **Stack Management** → **Connectors** → **Create connector** → **HTTP**

| Field | Value |
|-------|--------|
| Connector ID | `otel-demo-github` |
| URL | `https://api.github.com` |
| Authentication | Basic |
| Username | `github` (any string works) |
| Password | your `ghp_...` PAT |
| Headers | `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28` |

GitHub accepts a PAT as the basic-auth password ([REST API auth](https://docs.github.com/en/rest/authentication/authenticating-to-the-rest-api)).

### 7.2 Deploy workflow definitions

Workflow YAML files live in `scripts/workflows/`:

- `otel-demo-incident-payment.yaml`
- `otel-demo-incident-postgresql.yaml`
- `otel-demo-incident-valkey-cart.yaml`
- `otel-demo-incident-kafka.yaml`
- `otel-demo-recover-payment.yaml`
- `otel-demo-reset-lab.yaml`
- `otel-demo-oom-pressure.yaml`

They call your repo's workflow:

```
POST /repos/{owner}/{repo}/actions/workflows/demo-scenarios.yml/dispatches
```

Deploy:

```bash
export KIBANA_URL="https://..."
export ELASTIC_API_KEY="..."
export GITHUB_HTTP_CONNECTOR_ID="otel-demo-github"
export GITHUB_REPO_OWNER="YOUR_USER"
export GITHUB_REPO_NAME="YOUR_REPO"
export GITHUB_REF="main"

./scripts/workflows/deploy-workflows.sh
```

### 7.3 Run from Kibana

1. Kibana → **Workflows**
2. Open e.g. **OTel Demo — incident payment**
3. **Run** (manual trigger)
4. Confirm in GitHub **Actions** that a new **Demo scenarios** run started
5. Observe telemetry in Elastic (failed checkouts, flat order rate, etc.)

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|----------------|-----|
| `Must not run with sudo` | `config.sh` executed as root | Run install script as SSH user; use `--user` |
| `GITHUB_REPO: Set GITHUB_REPO` | `sudo` stripped environment | Use `--repo` / `--token` flags |
| Workflow queued, never starts | Runner offline | `sudo systemctl status actions.runner.*` on VM |
| `No runner matching...` | Missing label | Runner must have label `otel-demo` |
| Job fails at kubectl | No sudo / wrong kubeconfig | `sudo kubectl get pods -n otel-demo` on VM |
| Workflow dispatch 404 from Kibana | Wrong owner/repo in workflow consts | Re-run `deploy-workflows.sh` with correct env |
| Connector create HTTP 400 | Wrong connector type (`.webhook` vs `.http`) | Use updated `create-github-connector.sh` or HTTP connector in UI |

### Runner service logs (VM)

```bash
sudo journalctl -u 'actions.runner.*' -f
```

### Re-install runner

```bash
cd /opt/actions-runner   # or your --dir
sudo ./svc.sh stop
./config.sh remove --token <removal-token-from-github-ui>
```

Then repeat Step 4. Removal tokens: repo **Settings → Actions → Runners** → runner → **Remove**.

---

## Security notes

- Never commit `vars.yml`, `hosts.ini`, or API keys (see `.gitignore`).
- Revoke one-time install PATs after runner registration.
- Store the GitHub PAT used by Kibana in **connector secrets**, not in workflow YAML committed to git.
- The VM stays **without inbound** exposure; only outbound HTTPS to GitHub and Elastic.
- Use a dedicated PAT or fine-grained token scoped to your lab repo only.

---

## Related files

| Path | Purpose |
|------|---------|
| `.github/workflows/demo-scenarios.yml` | GitHub Actions entry point |
| `scripts/github/install-runner.sh` | Runner installer |
| `scripts/scenarios/` | kubectl scenario scripts |
| `scripts/workflows/*.yaml` | Elastic Workflows definitions |
| `scripts/workflows/deploy-workflows.sh` | Push workflows to Kibana API |
| `vars.yml.example` | Configuration template including `github_*` keys |

---

## Demo narrative (talk track)

1. **Happy path** — storefront checkout; orders and traces in Elastic.
2. **Incident** — run **incident-payment** from Kibana or GitHub; checkout fails; order KPI flatlines.
3. **Investigate** — APM errors, logs, metrics in Serverless.
4. **Recover** — **reset-lab** or **recover-payment**; KPI recovers.

See the main [README](../README.md) for lab deployment and observability ingest setup.
