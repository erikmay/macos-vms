# macos-vms: macOS VMs for coding agents, driven from the T3 Code desktop app.
# Run from this Mac (the client). N is the VM number: 1 or 2.
SHELL := /bin/bash
S := ./scripts

.DEFAULT_GOAL := help
.PHONY: help host image up auth token auth-claude auth-codex status view pair tunnel \
        update start stop reset delete lint

help: ## Show this list
	@awk -F':.*## ' '/^##@/ {printf "\n%s\n", substr($$0, 5)} /^[a-z-]+:.*## / {printf "  make %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

##@ Setup, in this order
host: ## Prepare the host: Tart, Softnet, socat
	$(S)/host-setup.sh

image: ## Build the golden image (agent CLIs, settings, Chrome, browser and computer use)
	$(S)/image-build.sh

up: ## Create VM N, start T3 in it and pair the T3 Code app with it
	$(S)/vm-create.sh $(N)
	$(S)/vm-t3.sh $(N)
	$(S)/tunnel.sh
	$(S)/pair.sh $(N)
	@echo "Next: make auth N=$(N)"

token: ## Store the token from `claude setup-token` in the Keychain (once)
	$(S)/token.sh

auth: auth-claude auth-codex ## Log in Claude Code and Codex in VM N

auth-claude: ## Copy the Claude token from the Keychain into VM N
	$(S)/auth-claude.sh $(N)

auth-codex: ## Codex device login in VM N (you approve a code in the browser)
	$(S)/auth-codex.sh $(N)

##@ Daily use
status: ## Show VMs, T3 reachability, tool versions and logins
	$(S)/status.sh

view: ## Open Screen Sharing for VM N (watch the agent, take over)
	$(S)/view.sh $(N)

pair: ## Pair the T3 Code app with VM N again (sessions expire)
	$(S)/pair.sh $(N)

tunnel: ## Reinstall the SSH tunnel on this Mac
	$(S)/tunnel.sh

##@ Maintenance
update: ## Update tools and settings in VM N in place (keeps logins and data)
	$(S)/vm-update.sh $(N)

start: ## Start VM N
	$(S)/vm-power.sh start $(N)

stop: ## Stop VM N until `make start` (frees a VM slot)
	$(S)/vm-power.sh stop $(N)

reset: ## Delete VM N and create a clean one (logins are lost)
	$(S)/vm-delete.sh $(N)
	$(MAKE) --no-print-directory up N=$(N)

delete: ## Delete VM N
	$(S)/vm-delete.sh $(N)
	$(S)/tunnel.sh

lint: ## Check the scripts (shellcheck, zsh -n)
	shellcheck -x $(S)/*.sh
	@for f in guest/*.sh; do zsh -n "$$f" || exit 1; done
