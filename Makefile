##@ Options

KUBE_VERSION ?= 1.24.6
WASMTIME_VERSION ?= 4.0.0
CRUN_VERSION ?= 1.7.2
SHIMS_VERSION ?= 0.3.3


##@ Commands

.PHONY: help
help: ## Display this help text
	@awk -F '(:.*##|?=)' \
		'BEGIN                  { printf "\n\033[1mUsage:\033[0m\n  make \033[36m[ COMMAND ]\033[0m \33[35m[ OPTION=VALUE ]...\33[0m\n" } \
		/^[A-Z_]+\s\?=\s+.+/    { printf "  \033[35m%-17s\033[0m (default:%s)\n", $$1, $$2 } \
		/^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 } \
		/^##@/                  { printf "\n\033[1m%s:\033[0m\n", substr($$0, 5) }' \
		$(MAKEFILE_LIST)

.PHONY: teardown
clean: ## Delete the kind cluster
	kind delete cluster -n wasmtime

.PHONY: all
all: node-image cluster crun-workload crun-test ## Build cluster and run the example workloads

.PHONY: cluster
cluster: ## Create the cluster
	kind create cluster --config kind-wasmtime/kind.yaml
	kubectl apply -f kind-wasmtime/runtime-classes.yaml

.PHONY: kind
node-image: ## Build the custom kind node image
	docker build \
		--build-arg "kubernetes_version=$(KUBE_VERSION)" \
		--build-arg "wasmtime_version=$(WASMTIME_VERSION)" \
		--build-arg "crun_version=$(CRUN_VERSION)" \
		--build-arg "shims_version=$(SHIMS_VERSION)" \
		--tag kind-crun-wasmtime \
		kind-wasmtime/node-image/

.PHONY: crun-workload
crun-workload: ## Build a wasm workload image and load it into kind
	docker buildx build --platform wasi/wasm32 -t wasm-workload:v0.1.0 examples/crun/wasm-workload/
	kind load docker-image wasm-workload:v0.1.0 -n wasmtime

.PHONY: test-crun
crun-test: ## Deploy a test job with mixed workloads and print their logs
	kubectl apply -f examples/crun/crun.yaml
	kubectl wait job/mixed-workload --for=condition=complete --timeout=1m
	kubectl logs job/mixed-workload -c wasm
	kubectl logs job/mixed-workload -c regular

.PHONY: spin-workload
spin-workload: ## Build a wasm app with spin and load it into kind
	docker buildx build --platform wasi/wasm32 -t spin-app:v0.1.0 examples/spin/app/
	kind load docker-image spin-app:v0.1.0 -n wasmtime

.PHONY: spin-test
spin-test: ## Deploy the spin app and curl its output
	kubectl apply -f examples/spin/spin.yaml
	kubectl wait deploy/wasm-spin --for=condition=Available=True --timeout=1m
	kubectl port-forward service/wasm-spin --address 127.0.0.1 8080:80 &
	sleep 5
	curl localhost:8080
	pkill kubectl
