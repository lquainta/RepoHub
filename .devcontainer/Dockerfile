# Development image for the backend and RepoHubCore. The macOS app needs Xcode
# and is built on the host.
FROM swift:6.4-noble

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID
ARG SWIFTLINT_VERSION=0.65.0
ARG GITLEAKS_VERSION=8.30.1
ARG TARGETARCH

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git make sudo unzip postgresql-client redis-tools \
    && rm -rf /var/lib/apt/lists/*

# SwiftLint and Gitleaks: pinned, checksum-verified, same versions as CI.
# TARGETARCH is only set by BuildKit; fall back to the image's own architecture.
RUN set -eux; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) lint_arch=amd64; lint_sha=79306a34e5c7cc55a220cd108cbb861dcad5f10138dcdf261e2624ae8b0a486b; \
               leaks_arch=x64;  leaks_sha=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb ;; \
        arm64) lint_arch=arm64; lint_sha=12d3b84bc5b69ae13a99a5a5c79904f9ce25867f099f6368d0037854f9ee6c26; \
               leaks_arch=arm64; leaks_sha=e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080 ;; \
        *) echo "unsupported architecture"; exit 1 ;; \
    esac; \
    cd /tmp; \
    curl -sSL -o swiftlint.zip "https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/swiftlint_linux_${lint_arch}.zip"; \
    echo "$lint_sha  swiftlint.zip" | sha256sum --check; \
    unzip -q swiftlint.zip swiftlint -d /usr/local/bin; \
    curl -sSL -o gitleaks.tar.gz "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${leaks_arch}.tar.gz"; \
    echo "$leaks_sha  gitleaks.tar.gz" | sha256sum --check; \
    tar -xzf gitleaks.tar.gz -C /usr/local/bin gitleaks; \
    rm swiftlint.zip gitleaks.tar.gz

# Non-root user matching the host UID so bind-mounted files keep sane ownership.
RUN set -eux; \
    if getent passwd "$USER_UID" >/dev/null; then userdel -r "$(getent passwd "$USER_UID" | cut -d: -f1)"; fi; \
    groupadd --gid "$USER_GID" "$USERNAME" 2>/dev/null || true; \
    useradd --uid "$USER_UID" --gid "$USER_GID" -m -s /bin/bash "$USERNAME"; \
    echo "$USERNAME ALL=(root) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"; \
    chmod 0440 "/etc/sudoers.d/$USERNAME"

RUN swift --version && swiftlint version && gitleaks version

USER $USERNAME
