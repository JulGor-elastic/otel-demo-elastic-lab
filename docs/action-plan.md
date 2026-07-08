# Action plan — Elastic Observability + OTel Demo lab

> Project scope, current status, and remaining work.  
> **Last updated:** 2026-07-08

For VM and configuration details see **[environment-setup.md](environment-setup.md)**.

---

## 1. Goals

Reproducible **customer demo lab**: [OpenTelemetry Demo](https://github.com/open-telemetry/opentelemetry-demo) on a user-provided Linux VM (Minikube), telemetry to **Elastic Cloud Serverless** via **EDOT**, with optional **RUM**, **Synthetics**, **business orders**, and **remote incident scenarios**.

### Principles

| Principle | Implication |
|-----------|-------------|
| **User-provided VM** | No automated cloud provisioning in this repo; document requirements and example `gcloud` only |
| **Kibana largely pre-configured** | Dashboards/alerts in Serverless are manual; not rebuilt from code |
| **No inbound exposure** | Remote control via outbound paths (GitHub Actions runner, Workflows) |
| **English in public repo** | README, docs, Ansible; internal notes may stay gitignored |

---

## 2. Architecture (implemented)

```
OTel SDKs → OTel Collector → EDOT Gateway → mOTLP → Elastic Cloud
K8s logs  → EDOT Daemon   → mOTLP → Elastic Cloud
Prometheus (in-cluster)   → Remote Write → Elastic Cloud
Grafana (in-cluster)      → PromQL / ES datasource
RUM (frontend-web)        → OTLP → EDOT → Elastic
Synthetics agent (in-cluster) → Private Location → HTTP/TCP monitors
```

---

## 3. Status by phase

### Phase 0 — Stabilize base lab ✅ **Done**

| Item | Status |
|------|--------|
| Pinned Helm versions | ✅ |
| `deploy.yml` + smoke tests (`check.yml`) | ✅ |
| Ordered pod wait + remediation | ✅ |
| `Makefile`, example config files | ✅ |
| Public README | ✅ |

**Exit:** `make deploy` + `make demo-check` on a suitable VM.

---

### Phase 1 — Prometheus + Grafana ✅ **Done** (migration optional)

| Item | Status |
|------|--------|
| Prometheus in-cluster (short retention) | ✅ |
| Prometheus Remote Write to Elastic | ✅ |
| Grafana in-cluster + datasource variable | ✅ |
| Grafana → Kibana dashboard migration | ⏸ Optional / manual |

**Exit:** PRW metrics visible in Elastic; Grafana dashboards usable in-cluster.

---

### Phase 2 — E2E signals ⚠️ **Partial**

| Item | Status |
|------|--------|
| **RUM** — OTLP from browser via EDOT transforms | ✅ Data ingests |
| **RUM** — OTel RUM dashboards in Kibana | ⏸ Partial (schema/quality; deferred) |
| **Synthetics** — Private Location + 3 monitors | ✅ Operational |
| RUM ↔ APM demo script / talk track | 🔲 Pending |

**Docs:** [phase2-synthetics.md](phase2-synthetics.md)  
**Monitors:** `synthetics/monitors.json` → `make synthetics-push` (Kibana API, no npm)

**Note:** New Private Locations on Elastic 9.4.x may require reusing an existing location (Fleet `space_ids` bug) — documented in phase2 guide.

---

### Phase 3 — Business impact ✅ **Done for demos**

| Item | Status |
|------|--------|
| Orders transform → `orders-otel-demo` | ✅ |
| Kibana business dashboard | ✅ Validated in demos |
| Optional ES\|QL / drill-down panels | 🔲 Backlog |

---

### Phase 4 — Remote scenarios + Workflows ✅ **Done**

| Item | Status |
|------|--------|
| Scenario scripts (`incident-*`, `recover-*`, `reset-lab`, `oom-pressure`) | ✅ |
| GitHub Actions workflow + self-hosted runner | ✅ |
| Elastic Workflows YAML + deploy scripts | ✅ |
| End-to-end from Kibana → VM | ✅ Validated |

**Docs:** [demo-scenarios-setup.md](demo-scenarios-setup.md)

---

### Phase 5 — Publication & hardening 🔲 **Revised scope**

**Removed:** Terraform / automation to **create** the GCP VM (user brings existing environment).

| Item | Status |
|------|--------|
| Public repo (`otel-demo-elastic-lab`) | ✅ |
| Document VM requirements + `gcloud` example | ✅ [environment-setup.md](environment-setup.md) |
| Document all config files (`vars.yml`, etc.) | ✅ |
| Ansible Vault for secrets | 🔲 Optional |
| Terraform `elasticstack` for Kibana objects | ⏸ Deferred — Kibana configured manually |
| Scheduled VM shutdown (cost) | 🔲 Optional ops note |

---

## 4. Initiative tracker (summary)

### Infrastructure

| ID | Initiative | Status |
|----|------------|--------|
| A1 | ~~Automate GCP VM creation~~ → **Document VM requirements** | ✅ Docs only |
| A2 | Pin Helm versions | ✅ |
| A3 | Post-deploy health checks | ✅ (Elastic ingest UI: manual) |
| A4 | Makefile targets | ✅ |
| A6 | Ansible Vault | 🔲 |
| A8 | Ordered pod wait | ✅ |

### Telemetry

| ID | Initiative | Status |
|----|------------|--------|
| B1–B2 | Prometheus + PRW | ✅ |
| B3–B4 | Pipeline / attribute review | 🔲 |

### Visualization

| ID | Initiative | Status |
|----|------------|--------|
| C1–C2 | Grafana enabled + inventory | ✅ |
| C4 | Grafana → Kibana migration | ⏸ Manual |

### Complementary signals

| ID | Initiative | Status |
|----|------------|--------|
| D1 | RUM ingest | ✅ |
| D1b | RUM dashboards | ⏸ Deferred |
| D2 | Synthetics Private Location | ✅ |
| D3 | RUM correlation demo | 🔲 |

### Business + operations

| ID | Initiative | Status |
|----|------------|--------|
| E1–E3 | Orders + dashboard | ✅ |
| F1–F4 | Scenarios + Workflows | ✅ |

### Documentation

| ID | Initiative | Status |
|----|------------|--------|
| G1 | Example config files | ✅ |
| G3 | Public README | ✅ |
| G6 | Environment + config guide | ✅ |
| G5 | Terraform elasticstack export | ⏸ Deferred |

---

## 5. What remains (prioritized)

### High value / demo polish

1. **RUM dashboards** — tune or replace OTel RUM pack for Serverless schema.
2. **Grafana → Kibana** — migrate key PromQL dashboards when needed for narrative.

### Nice to have

3. **Ansible Vault** — replace plain-text `vars.yml` secrets.
4. **B3/B4** — telemetry attribute audit for correlation demos.
5. **D3** — short RUM → trace → logs walkthrough doc.

### Out of scope (by design)

- Automated VM provisioning (any cloud).
- Full Terraform for Elastic/Kibana objects (manual Serverless project remains source of truth).

---

## 6. Demo storylines

| Story | Signals | Ready? |
|-------|---------|--------|
| Happy path — checkout trace | APM, logs, metrics | ✅ |
| Incident — payment down | Workflows, scenarios, Synthetics TCP, orders KPI | ✅ |
| Business impact — orders drop | Transform + dashboard | ✅ |
| User perspective — RUM | Traces ingest; dashboards partial | ⚠️ |
| Synthetic availability | Private Location monitors | ✅ |

---

## 7. Dependency map

```
User-provided VM + vars.yml
        │
        ▼
Phase 0 (deploy) ──┬── Phase 1 (PRW/Grafana) ✅
                   ├── Phase 2 (RUM + Synthetics) ⚠️ partial
                   ├── Phase 3 (orders) ✅
                   └── Phase 4 (scenarios) ✅
```

---

## 8. Quick commands

```bash
# Core
make deploy && make demo-check

# Optional
make synthetics-setup          # Fleet agent + monitors
make demo-scenario-reset-lab   # Local scenario test
make synthetics-push           # After editing monitors.json
```

See [environment-setup.md](environment-setup.md) for first-time configuration.
