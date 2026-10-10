# syntax=docker/dockerfile:1
# Production image for the RepoHub backend.
#
# Build from the repository root, because the backend depends on
# Packages/RepoHubCore by path:
#   docker build -f Backend/Dockerfile -t repohub-backend .

# ---- Build -----------------------------------------------------------------
FROM swift:6.4-noble AS build

# jemalloc is linked into the binary (see the build step).
RUN apt-get update \
    && apt-get install -y --no-install-recommends libjemalloc-dev \
    && rm -rf /var/lib/apt/lists/*

# Resolve dependencies first so this layer is cached until Package.* changes.
WORKDIR /build
COPY Packages/RepoHubCore/Package.swift Packages/RepoHubCore/
COPY Backend/Package.swift Backend/Package.resolved Backend/
RUN mkdir -p Packages/RepoHubCore/Sources/RepoHubCore \
    && touch Packages/RepoHubCore/Sources/RepoHubCore/Placeholder.swift \
    && swift package --package-path Backend resolve \
    && rm -rf Packages/RepoHubCore/Sources

COPY Packages/RepoHubCore Packages/RepoHubCore
COPY Backend/Sources Backend/Sources
COPY Backend/Tests Backend/Tests

# Linked dynamically against the Swift runtime from the slim image below.
# (--static-swift-stdlib fails to link Foundation with Swift 6.4.)
RUN swift build --package-path Backend -c release --product App -Xlinker -ljemalloc \
    && mkdir /staging \
    && cp "$(swift build --package-path Backend -c release --show-bin-path)/App" /staging/ \
    && cp /usr/libexec/swift/linux/swift-backtrace-static /staging/ \
    && find -L "$(swift build --package-path Backend -c release --show-bin-path)" \
        -regex '.*\.resources$' -exec cp -Ra {} /staging/ \;

# ---- Run -------------------------------------------------------------------
# The Swift runtime libraries without the compiler.
FROM swift:6.4-noble-slim

# ca-certificates: TLS to GitHub and the database. tzdata: time zones.
# libjemalloc2: faster allocator for the server. curl: the HEALTHCHECK below.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata libjemalloc2 curl \
    && rm -rf /var/lib/apt/lists/*

# Run as an unprivileged user that owns nothing but the app directory.
RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor
WORKDIR /app
COPY --from=build --chown=vapor:vapor /staging /app

# Recorded in the image and reported by GET /health.
ARG BUILD_COMMIT=unknown
ENV BUILD_COMMIT=${BUILD_COMMIT} \
    SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no,swift-backtrace=./swift-backtrace-static

USER vapor:vapor
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl --fail --silent --show-error http://localhost:8080/health || exit 1

ENTRYPOINT ["./App"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
