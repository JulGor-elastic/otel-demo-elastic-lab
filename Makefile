# Operational targets for the OTel Demo + Elastic lab
#
# Generic defaults below. For your environment:
#   cp config.mk.example config.mk
# config.mk is gitignored and overrides local variables.

-include config.mk

ANSIBLE_INVENTORY ?= hosts.ini
GCP_VM_NAME       ?= YOUR_GCP_VM_NAME
GCP_ZONE          ?= YOUR_GCP_ZONE
GCP_SSH_USER      ?= YOUR_SSH_USER
LOCAL_PORT        ?= 8080

.PHONY: deploy demo-upgrade demo-check demo-tunnel demo-scenario-% help

help:
	@echo "Available targets:"
	@echo "  make deploy        - Full deployment (ansible-playbook deploy.yml)"
	@echo "  make demo-upgrade  - Re-apply otel-values.yaml.j2 + helm upgrade demo only"
	@echo "  make demo-check    - Smoke tests without redeploying (ansible-playbook check.yml)"
	@echo "  make demo-tunnel   - SSH tunnel to the demo frontend (localhost:$(LOCAL_PORT))"
	@echo "  make demo-scenario-<name> - Run scenario on VM (incident-*, recover-payment, oom-pressure, reset-lab)"
	@echo ""
	@echo "Local config: cp config.mk.example config.mk"

deploy:
	ansible-playbook -i $(ANSIBLE_INVENTORY) deploy.yml

# Use after editing otel-values.yaml.j2 (skips Docker, Minikube, EDOT).
demo-upgrade:
	ansible gcp_vm -i $(ANSIBLE_INVENTORY) -m template \
		-a "src=otel-values.yaml.j2 dest=/opt/otel-demo/values.yaml" \
		--become -e @vars.yml
	ansible-playbook -i $(ANSIBLE_INVENTORY) deploy.yml \
		--start-at-task "10. Deploy OTel Demo"

demo-check:
	ansible-playbook -i $(ANSIBLE_INVENTORY) check.yml

# Phase 4 — run a demo scenario on the VM via kubectl (syncs scripts first).
SCENARIO_SYNC_DEST := /opt/otel-demo/scenarios

demo-scenario-%:
	ansible gcp_vm -i $(ANSIBLE_INVENTORY) --become -e @vars.yml -m file \
		-a "path=$(SCENARIO_SYNC_DEST) state=directory"
	ansible gcp_vm -i $(ANSIBLE_INVENTORY) --become -e @vars.yml -m synchronize \
		-a "src=scripts/scenarios/ dest=$(SCENARIO_SYNC_DEST)/ mode=push"
	ansible gcp_vm -i $(ANSIBLE_INVENTORY) --become -e @vars.yml -m copy \
		-a "src=scripts/wait-otel-demo-ready.sh dest=/opt/otel-demo/wait-otel-demo-ready.sh mode=0755"
	ansible gcp_vm -i $(ANSIBLE_INVENTORY) --become -e @vars.yml -m shell \
		-a "KUBECONFIG=/root/.kube/config bash $(SCENARIO_SYNC_DEST)/$*.sh"

demo-tunnel:
	@echo "Opening tunnel http://localhost:$(LOCAL_PORT) → frontend-proxy on the VM..."
	gcloud compute ssh $(GCP_SSH_USER)@$(GCP_VM_NAME) \
		--zone=$(GCP_ZONE) \
		-- -L $(LOCAL_PORT):localhost:$(LOCAL_PORT)
