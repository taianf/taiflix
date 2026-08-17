# ==============================================================================
# Makefile - Taiflix Servarr GitOps Operations
# ==============================================================================
.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash

.PHONY: help
help: ## Display this help message
	@echo -e "\033[1mTaiflix Servarr Stack Management\033[0m"
	@echo -e "\033[36mUsage:\033[0m make [target]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[32m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: setup
setup: ## Run environment setup and check/install dependencies
	./setup.sh

.PHONY: cluster
cluster: ## Spin up a local k3d Kubernetes cluster with /media mount and port forwards
	./scripts/create-cluster.sh

.PHONY: cluster-down
cluster-down: ## Delete the local k3d Kubernetes cluster
	@if command -v k3d >/dev/null 2>&1; then \
		k3d cluster delete taiflix; \
	fi

.PHONY: hosts
hosts: ## Add *.taiflix.lan local DNS entries to /etc/hosts (idempotent)
	@HOSTS_LINE="127.0.0.1 sonarr.taiflix.lan radarr.taiflix.lan jellyfin.taiflix.lan prowlarr.taiflix.lan lidarr.taiflix.lan bazarr.taiflix.lan qbittorrent.taiflix.lan requests.taiflix.lan configarr.taiflix.lan"; \
	if grep -qF "$$HOSTS_LINE" /etc/hosts 2>/dev/null; then \
		echo "/etc/hosts already contains taiflix.lan entries — skipping."; \
	else \
		echo "Adding local DNS entries to /etc/hosts..."; \
		echo "$$HOSTS_LINE" | sudo tee -a /etc/hosts >/dev/null; \
	fi

.PHONY: start
start: hosts ## Start the entire Servarr stack (probe hardware, generate secrets, deploy)
	./scripts/start.sh

.PHONY: stop
stop: ## Stop and tear down the Servarr stack
	./scripts/stop.sh

.PHONY: status
status: ## Show status of all media stack pods, services, and ingress
	./scripts/status.sh

.PHONY: health
health: ## Check live HTTP and pod health for all services
	./scripts/health-check.sh

.PHONY: port-forward
port-forward: ## Forward all media stack Web UIs to localhost ports
	./scripts/port-forward.sh

.PHONY: logs
logs: ## Stream logs from the auto-wiring orchestrator
	@if command -v kubectl >/dev/null 2>&1; then \
		kubectl logs -n media -l app.kubernetes.io/name=servarr-wire --tail=100 -f 2>/dev/null || kubectl logs -n media -l job-name=servarr-wire-job --tail=100 -f; \
	fi

.PHONY: jellyfin-debug
jellyfin-debug: ## Diagnose Jellyfin deployment state (pods, svc, endpoints, env, logs)
	@echo "=== 1. Jellyfin pods ==="
	@kubectl get pods -n media -l app.kubernetes.io/name=jellyfin -o wide 2>&1 || true
	@echo ""
	@echo "=== 2. Jellyfin Service & Endpoints ==="
	@kubectl get svc -n media jellyfin 2>&1 || true
	@kubectl get endpoints -n media jellyfin 2>&1 || true
	@echo ""
	@echo "=== 3. Jellyfin env vars on the running deployment ==="
	@kubectl exec -n media deploy/jellyfin -- env 2>&1 | grep -iE 'jellyfin' || true
	@echo ""
	@echo "=== 4. Jellyfin pod logs (last 50 lines) ==="
	@kubectl logs -n media -l app.kubernetes.io/name=jellyfin --tail=50 2>&1 || true

.PHONY: detect-hw
detect-hw: ## Probe node/system hardware for Intel QuickSync and NVIDIA GPU
	./scripts/detect-hardware.sh

.PHONY: secrets
secrets: ## Generate Kubernetes secret (servarr-secrets) from values-secret.yaml
	./scripts/generate-secrets.sh

.PHONY: lint
lint: ## Run pre-commit checks on all repository files
	@if command -v pre-commit >/dev/null 2>&1; then \
		pre-commit run --all-files; \
	elif command -v prek >/dev/null 2>&1; then \
		prek run --all-files; \
	else \
		echo "pre-commit not found. Run 'make setup' first."; \
		exit 1; \
	fi

.PHONY: prek
prek: lint ## Alias for make lint

.PHONY: test
test: ## Validate Helm charts and Kubernetes manifests
	./scripts/test-manifests.sh

.PHONY: bootstrap
bootstrap: detect-hw secrets ## Prepare secrets and display ArgoCD bootstrap command
	@echo ""
	@echo "================================================================="
	@echo " Taiflix is ready to be applied to ArgoCD!"
	@echo "================================================================="
	@echo " 1. Ensure your secret is applied to the cluster:"
	@echo "    kubectl apply -f values/servarr-secrets.generated.yaml -n media"
	@echo ""
	@echo " 2. Apply the ArgoCD root application:"
	@echo "    kubectl apply -f argocd/root-app.yaml"
	@echo "================================================================="
