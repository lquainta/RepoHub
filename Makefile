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
	@command -v gitleaks >/dev/null || { echo "gitleaks not found: brew install gitleaks"; exit 1; }
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

.PHONY: test test-core test-backend test-app test-ui
test: test-core test-backend test-app ## Run all unit and integration tests (UI tests: make test-ui)

test-core: ## Test the RepoHubCore package
	swift test --package-path $(CORE_DIR)

test-backend: ## Test the Vapor backend
	swift test --package-path $(BACKEND_DIR)

# Set RESULT_BUNDLE=path/to/Result.xcresult to keep Xcode's test results, and
# DERIVED_DATA=dir to choose where Xcode builds (needed for app coverage).
RESULT_BUNDLE_FLAG = $(if $(RESULT_BUNDLE),-resultBundlePath $(RESULT_BUNDLE)) \
                     $(if $(DERIVED_DATA),-derivedDataPath $(DERIVED_DATA))

test-app: generate ## Run the macOS app's unit tests
	$(XCODEBUILD) test -skip-testing:RepoHubUITests $(RESULT_BUNDLE_FLAG)

test-ui: generate ## Run the macOS app's UI tests (launches the app and drives it)
	$(XCODEBUILD) test -only-testing:RepoHubUITests $(RESULT_BUNDLE_FLAG)

.PHONY: coverage
coverage: ## Run tests with coverage and write LCOV reports to coverage/
	scripts/package-coverage.sh $(CORE_DIR) coverage/core.lcov
	scripts/package-coverage.sh $(BACKEND_DIR) coverage/backend.lcov
	$(MAKE) test-app DERIVED_DATA=build/DerivedData
	scripts/app-coverage.sh build/DerivedData coverage/app.lcov

.PHONY: lint lint-fix
lint: ## Run SwiftLint in strict mode
	swiftlint lint --strict --quiet

lint-fix: ## Auto-correct SwiftLint violations where possible
	swiftlint lint --fix --quiet

.PHONY: secrets-scan
secrets-scan: ## Scan git history and the working tree for secrets with Gitleaks
	gitleaks git --config .gitleaks.toml --redact --no-banner
	gitleaks dir . --config .gitleaks.toml --redact --no-banner

.PHONY: check-env
check-env: ## Verify every backend environment variable is documented in .env.sample
	scripts/check-env-sample.sh

.PHONY: format format-check
format: ## Format all Swift sources in place with swift-format
	swift format --in-place --recursive --parallel $(FORMAT_PATHS)

format-check: ## Fail if any Swift source is not formatted
	swift format lint --strict --recursive --parallel $(FORMAT_PATHS)

.PHONY: migrate migrate-revert check-migrations
migrate: ## Apply database migrations to $$DATABASE_URL
	swift run --package-path $(BACKEND_DIR) App migrate --yes

migrate-revert: ## Revert the last batch of migrations on $$DATABASE_URL
	swift run --package-path $(BACKEND_DIR) App migrate --revert --yes

check-migrations: ## Migrate, revert, and migrate again on a clean $$DATABASE_URL
	scripts/check-migrations.sh

.PHONY: docker-build docker-run
docker-build: ## Build the backend image (repohub-backend:dev)
	docker build -f $(BACKEND_DIR)/Dockerfile --build-arg BUILD_COMMIT=$$(git rev-parse --short HEAD) -t repohub-backend:dev .

docker-run: ## Run the backend image on http://localhost:8080 with .env
	docker run --rm -p 8080:8080 --env-file .env repohub-backend:dev

.PHONY: up down
up: ## Start PostgreSQL, Redis, migrations, and the API with docker compose
	docker compose up --build -d --wait
	@echo "API: http://localhost:8080/health"

down: ## Stop the docker compose stack (keeps data; add -v to docker compose down to wipe it)
	docker compose down

.PHONY: run-backend open
run-backend: ## Run the backend on http://localhost:8080
	swift run --package-path $(BACKEND_DIR) App serve --hostname 0.0.0.0 --port 8080

open: generate ## Open the app in Xcode
	open $(PROJECT)

.PHONY: clean
clean: ## Remove build artifacts and the generated Xcode project
	rm -rf $(CORE_DIR)/.build $(BACKEND_DIR)/.build $(PROJECT)
