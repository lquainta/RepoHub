#!/usr/bin/env bash
# Runs once after the DevContainer is created.
set -euo pipefail

# Named volumes for .build are created root-owned.
sudo chown -R "$(id -u):$(id -g)" Backend/.build Packages/RepoHubCore/.build

swift package resolve --package-path Packages/RepoHubCore
swift package resolve --package-path Backend
swift build --package-path Backend

# Database migrations (#31) and seed data (#33) will run here.

echo "DevContainer ready. Run 'make run-backend' to start the API on port 8080."
