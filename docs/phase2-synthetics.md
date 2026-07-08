# Phase 2 — Synthetics (Private Location)

Lightweight **HTTP/TCP monitors** for the OTel Demo, executed from inside Minikube via a **Fleet-managed Elastic Agent** and a **Synthetics Private Location**.

Monitors are defined in `synthetics/monitors.json` and pushed with **`curl` + Kibana API** — no Node.js, no npm, no Playwright.

RUM (browser traces) is a separate track; see `otel-values.yaml.j2`. This document covers **Synthetics only**.

---

## Quick reference

| Goal | Command |
|------|---------|
| First-time setup (agent + location + monitors) | `make synthetics-setup` |
| Deploy / refresh Fleet agent on VM | `make synthetics-deploy` |
| Wait Fleet, location, push monitors | `make synthetics-configure` |
| Push monitor changes only | `make synthetics-push` |
| Agent on wrong Fleet policy | `./scripts/synthetics/reassign-fleet-agent.sh` |
| Diagnose Private Location API errors | `./scripts/synthetics/diagnose-private-location.sh` |

**Workstation prerequisites:** `curl`, `jq`, Ansible (for deploy). API key in `vars.yml` with **Synthetics** + **Fleet** privileges.

---

## Architecture

```
vars.yml (Fleet URL, token, policy, location name)
        │
        ▼
┌─────────────────── VM (Minikube) ───────────────────┐
│  elastic-synthetics-agent pod  →  Fleet (online)   │
│  reaches cluster DNS: frontend-proxy, payment, …   │
└────────────────────────────────────────────────────┘
        │
        ▼
Kibana: Private Location  +  Monitors (HTTP/TCP)
        ▲
        │
  push-monitors.sh (Kibana API, from your laptop)
```

---

## Setup flow (three phases)

Elastic Private Locations have a dependency chain. Only **Phase A** is manual in Kibana; the rest is scripted.

| Phase | Who | What | When |
|-------|-----|------|------|
| **A — Fleet bootstrap** | You (Kibana UI) | Agent policy + enrollment token → `vars.yml` | **Once** per Elastic project |
| **B — Agent on VM** | `make synthetics-deploy` | `elastic-synthetics-agent` pod enrolls in Fleet | Token rotation / VM rebuild |
| **C — Location + monitors** | `make synthetics-configure` | Private Location (API) + push `monitors.json` | Idempotent |

### Phase A — One-time (manual, Kibana)

1. **Fleet** → **Agent policies** → **Create agent policy**
   - Add **Elastic Synthetics** integration (HTTP/TCP/ICMP).
   - One policy = one Private Location agent (do not share across agents).

2. **Enrollment tokens** → create token. Copy to `vars.yml`:
   - Fleet Server URL → `fleet_url`
   - Token → `fleet_enrollment_token`

3. Add to `vars.yml` (see `vars.yml.example`):

```yaml
fleet_url: "https://YOUR_PROJECT.fleet.REGION.aws.elastic.cloud:443"
fleet_enrollment_token: "YOUR_TOKEN"
fleet_agent_policy_name: "Your Synthetics Policy"
synthetics_private_location_name: "Your Private Location Label"
kibana_url: "https://YOUR_PROJECT.kb.REGION.aws.elastic.cloud"
elastic_api_key: "YOUR_API_KEY"
```

> **Enrollment tokens are single-use.** After redeploying the agent pod, create a new token and run `make synthetics-deploy` again.

### Phase B — Deploy agent (Ansible)

```bash
make synthetics-deploy
```

Deploys `elastic-synthetics-agent` in namespace `otel-demo` using `synthetics-deploy.yml`.

If you **changed `fleet_agent_policy_name`** on an already-enrolled agent, also run:

```bash
./scripts/synthetics/reassign-fleet-agent.sh
```

Changing the enrollment token alone does **not** move an existing agent to another policy.

### Phase C — Private Location + monitors

```bash
make synthetics-configure
```

Runs, in order:

1. `wait-fleet-agent.sh` — agent online on the configured policy
2. `reassign-fleet-agent.sh` — no-op if already correct
3. `create-private-location.sh` — Kibana API (skip if label exists)
4. `push-monitors.sh` — upsert monitors from `synthetics/monitors.json`

**Or all-in-one from scratch:**

```bash
make synthetics-setup
```

---

## Monitors (optional to customize)

Default monitors in `synthetics/monitors.json`:

| Name | Type | Target | Demo tie-in |
|------|------|--------|-------------|
| OTel Demo Storefront | `http` | `http://frontend-proxy:8080/` | Storefront up |
| OTel Demo API Products | `http` | `http://frontend-proxy:8080/api/products` | Catalog API |
| OTel Demo Payment | `tcp` | `payment:8080` | Down on `incident-payment` |

**Edit monitors:** change `synthetics/monitors.json`, then:

```bash
make synthetics-push
```

**Remove a monitor from Kibana:** add its display name to `synthetics/retired-monitors.json` (array of strings), then `make synthetics-push`.

### `monitors.json` schema

```json
{
  "id": "unique-id",
  "name": "Display name in Kibana",
  "type": "http",
  "urls": "http://service:port/path",
  "schedule": 5,
  "tags": ["otel-demo"]
}
```

For TCP checks use `"type": "tcp"` and `"hosts": "service:port"` instead of `urls`.

---

## Optional: skip Private Location creation

If you **reuse an existing** Private Location (e.g. Elastic 9.4.x `space_ids` bug — see below):

```bash
SYNTHETICS_SKIP_PRIVATE_LOCATION=1 make synthetics-configure
```

Set `synthetics_private_location_name` in `vars.yml` to the **exact label** of the existing location.

---

## Verify

1. **Fleet** → **Agents**: one agent `Healthy` on your Synthetics policy.
2. **Observability** → **Synthetics** → **Settings** → **Private Locations**: your label listed.
3. **Synthetics** → **Monitors**: three monitors with recent green runs.

On the VM:

```bash
kubectl get pods -n otel-demo -l app=elastic-synthetics-agent
kubectl logs -n otel-demo -l app=elastic-synthetics-agent --tail=50
```

---

## Troubleshooting

| Symptom | Action |
|---------|--------|
| Agent `CrashLoopBackOff` | New enrollment token → `make synthetics-deploy` |
| Agent on wrong policy | `./scripts/synthetics/reassign-fleet-agent.sh` |
| Private Location **HTTP 500** | Known 9.4.x bug — reuse existing location (below) |
| Monitors not running | `synthetics_private_location_name` must match Kibana label exactly |
| Push fails 401/403 | API key needs Synthetics + Fleet privileges |
| Payment monitor down after scenario | Expected during `incident-payment`; recover with `reset-lab` |

### Known bug: cannot create new Private Locations (HTTP 500)

On Elastic **9.4.x** / Serverless, Fleet policies often have `space_ids: []`. Creating a new Private Location fails with HTTP 500 or 400. [Discuss thread](https://discuss.elastic.co/t/unable-to-create-private-location/386864).

**Workaround:** reuse a Private Location created earlier in the project:

1. Point `fleet_agent_policy_name` and `synthetics_private_location_name` at that policy/label.
2. New enrollment token → `make synthetics-deploy` → `reassign-fleet-agent.sh`.
3. `SYNTHETICS_SKIP_PRIVATE_LOCATION=1 make synthetics-configure`.

Diagnose: `./scripts/synthetics/diagnose-private-location.sh`

---

## Repo layout (Synthetics)

```
synthetics/
  monitors.json           # monitor definitions (source of truth)
  retired-monitors.json   # names to delete on next push (optional)

scripts/synthetics/
  load-vars.sh            # read vars.yml
  push-monitors.sh        # Kibana API upsert (no npm)
  wait-fleet-agent.sh
  reassign-fleet-agent.sh
  create-private-location.sh
  diagnose-private-location.sh
  configure.sh            # Phase C orchestrator
  setup-synthetics.sh     # full pipeline

synthetics-deploy.yml     # Ansible: agent pod on VM
templates/synthetics-agent.yaml.j2
tasks/synthetics_agent.yml
```

---

## Re-deploy / teardown

| Task | Command |
|------|---------|
| Push monitor changes | `make synthetics-push` |
| New enrollment token | Update `vars.yml` → `make synthetics-deploy` |
| Remove agent pod | `kubectl delete deployment elastic-synthetics-agent -n otel-demo` |

Monitors and Private Locations remain in Kibana until deleted in the UI.

---

## Optional: browser monitors

Default lab uses **standard** `elastic-agent` (HTTP/TCP only). Browser journeys need `elastic-agent-complete` in `vars.yml`:

```yaml
synthetics_agent_flavor: complete
synthetics_limit_browser: "2"
```

Then `make synthetics-deploy`. Browser checks are **not** managed by this repo's `monitors.json` push script.
