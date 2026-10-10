#!/usr/bin/env bash
# Runs once after the DevContainer is created.
set -euo pipefail

# Named volumes for .build are created root-owned.
sudo chown -R "$(id -u):$(id -g)" Backend/.build Packages/RepoHubCore/.build

swift package resolve --package-path Packages/RepoHubCore
swift package resolve --package-path Backend
swift build --package-path Backend

# Bring the development database up to date. Seed data (#33) will run here.
swift run --package-path Backend App migrate --yes

echo "DevContainer ready. Run 'make run-backend' to start the API on port 8080."
