# RepoHub developer tasks. Run `make help` for a list.

CORE_DIR    := Packages/RepoHubCore
BACKEND_DIR := Backend
APP_DIR     := App
PROJECT     := $(APP_DIR)/RepoHub.xcodeproj
SCHEME      := RepoHub
DESTINATION := platform=macOS,arch=$(shell uname -m)
FORMAT_PATHS := App/Sources App/Tests $(CORE_DIR)/Package.swift $(CORE_DIR)/Sources $(CORE_DIR)/Tests \
                $(BACKEND_DIR)/Package.swift $(BACKEND_DIR)/Sources $(BACKEND_DIR)/Tests
XCODEBUILD  := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: bootstrap
bootstrap: ## Check required tools, resolve dependencies, and generate the Xcode project
	@command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen"; exit 1; }
	@command -v swiftlint >/dev/null || { echo "swiftlint not found: brew install swiftlint"; exit 1; }
	@command -v xcodebuild >/dev/null || { echo "Xcode not found: install it from the App Store"; exit 1; }
	swift package resolve --package-path $(CORE_DIR)
	swift package resolve --package-path $(BACKEND_DIR)
	$(MAKE) generate

.PHONY: generate
generate: ## Generate App/RepoHub.xcodeproj from App/project.yml
	cd $(APP_DIR) && xcodegen generate --quiet

.PHONY: build build-core build-backend build-app
build: build-core build-backend build-app ## Build every component

build-core: ## Build the RepoHubCore package
	swift build --package-path $(CORE_DIR)

build-backend: ## Build the Vapor backend
	swift build --package-path $(BACKEND_DIR)

build-app: generate ## Build the macOS app
	$(XCODEBUILD) build

.PHONY: test test-core test-backend test-app
test: test-core test-backend test-app ## Run every test suite

test-core: ## Test the RepoHubCore package
	swift test --package-path $(CORE_DIR)

test-backend: ## Test the Vapor backend
	swift test --package-path $(BACKEND_DIR)

test-app: generate ## Test the macOS app
	$(XCODEBUILD) test

.PHONY: lint lint-fix
lint: ## Run SwiftLint in strict mode
	swiftlint lint --strict --quiet

lint-fix: ## Auto-correct SwiftLint violations where possible
	swiftlint lint --fix --quiet

.PHONY: format format-check
format: ## Format all Swift sources in place with swift-format
	swift format --in-place --recursive --parallel $(FORMAT_PATHS)

format-check: ## Fail if any Swift source is not formatted
	swift format lint --strict --recursive --parallel $(FORMAT_PATHS)

.PHONY: run-backend open
run-backend: ## Run the backend on http://localhost:8080
	swift run --package-path $(BACKEND_DIR) App serve --hostname 0.0.0.0 --port 8080

open: generate ## Open the app in Xcode
	open $(PROJECT)

.PHONY: clean
clean: ## Remove build artifacts and the generated Xcode project
	rm -rf $(CORE_DIR)/.build $(BACKEND_DIR)/.build $(PROJECT)
