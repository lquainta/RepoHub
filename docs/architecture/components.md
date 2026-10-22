# Components and deployment

## Components

How the app, the shared package, and the backend fit together. Names are the
types in the code; `scripts/check-diagrams.sh` fails CI if one disappears.

```mermaid
flowchart LR
    subgraph Mac["macOS app (App/)"]
        Views["LibraryView · DashboardTable · RepositoryDetailView<br/>SettingsView · ActivityView · MenuBarContent"]
        LibraryViewModel
        StatusMonitor
        AccountModel
        GitHubStatusModel
        SyncModel
        ActivityModel
        AttentionNotifier
        LibraryStore[("LibraryStore<br/>SwiftData")]
        Keychain[("KeychainCredentialStore")]
        RepoHubAPI
    end
    subgraph Core["RepoHubCore (macOS + Linux)"]
        GitService
        RepositoryScanner
        ProcessGitRunner
        Parsers["PorcelainStatusParser · BranchListParser · CommitSummaryParser<br/>RemoteListParser · StashListParser"]
        StaleBranchDetector
    end
    subgraph Backend["Backend (Vapor, Linux)"]
        APIHandler
        AuthenticationMiddleware
        AuthService
        RepositoryStatusService
        GitHubCache
        WorkspaceSync
        ActivityService
        EventHub
        ErrorReportingMiddleware
    end
    Git[["git CLI"]]
    GitHub[["GitHub REST API"]]
    Postgres[("PostgreSQL")]
    Redis[("Redis")]

    Views --> LibraryViewModel
    LibraryViewModel --> StatusMonitor & LibraryStore & GitHubStatusModel & SyncModel & ActivityModel
    StatusMonitor --> GitService
    LibraryViewModel --> RepositoryScanner
    GitService --> ProcessGitRunner --> Git
    GitService --> Parsers & StaleBranchDetector
    GitHubStatusModel --> AttentionNotifier
    AccountModel --> Keychain
    AccountModel & GitHubStatusModel & SyncModel & ActivityModel --> RepoHubAPI
    RepoHubAPI -- "HTTPS, OpenAPI client" --> AuthenticationMiddleware --> APIHandler
    APIHandler --> AuthService & RepositoryStatusService & WorkspaceSync & ActivityService & EventHub
    RepositoryStatusService --> GitHubCache --> Redis
    GitHubCache --> GitHub
    AuthService --> GitHub
    AuthService & WorkspaceSync & ActivityService --> Postgres
    GitHub -- "webhooks" --> APIHandler
```

## Deployment

```mermaid
flowchart TB
    subgraph User["User's Mac"]
        App["RepoHub.app<br/>(ad-hoc signed, ADR 0009)"]
    end
    subgraph GH["GitHub"]
        Repo["lquainta/RepoHub"]
        Actions["GitHub Actions<br/>CI · Deploy · Backup · Release"]
        GHAPI["REST API + OAuth device flow"]
    end
    subgraph Fly["Fly.io, region dfw (ADR 0007, 0010)"]
        API["repohub-backend<br/>shared-cpu-1x, 512 MB<br/>release_command: migrate --yes"]
        DB[("repohub-db<br/>PostgreSQL, single node")]
        Cache[("repohub-redis<br/>Upstash")]
        Tigris[("Tigris bucket<br/>repohub-backups")]
    end
    Sentry["Sentry"]
    Resend["Resend (email)"]
    Uptime["UptimeRobot"]

    App -- "HTTPS" --> API
    App -- "crash reports (opt-in)" --> Sentry
    API --> DB & Cache
    API -- "GitHub token (encrypted at rest)" --> GHAPI
    GHAPI -- "webhooks (HMAC-signed)" --> API
    API --> Sentry & Resend
    Uptime -- "GET /ready every 5 min" --> API
    Repo --> Actions
    Actions -- "deploy after green CI" --> API
    Actions -- "nightly pg_dump (encrypted)" --> Tigris
```
