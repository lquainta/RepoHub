# Sequences

## Scanning and refreshing

Adding a folder, then refreshing statuses when files change (#17, #19, #70).

```mermaid
sequenceDiagram
    actor User
    participant LibraryViewModel
    participant RepositoryScanner
    participant LibraryStore
    participant StatusMonitor
    participant GitService
    participant AutoRefreshController
    participant FSEventsWatcher

    User->>LibraryViewModel: addFolders([url])
    LibraryViewModel->>RepositoryScanner: scan(root, maxDepth)
    RepositoryScanner-->>LibraryViewModel: repository URLs (skips ignored folders)
    LibraryViewModel->>LibraryStore: replaceRepositories(in: folder, with:)
    LibraryViewModel->>StatusMonitor: refresh(paths)
    par at most 8 at a time
        StatusMonitor->>GitService: status(of:)
        GitService->>GitService: git status --porcelain=v2, git log -1
        StatusMonitor->>GitService: remotes(of:), staleBranches(of:)
    end
    StatusMonitor-->>LibraryViewModel: states and facts → dashboard rows
    FSEventsWatcher-->>AutoRefreshController: file changed in a repository
    AutoRefreshController->>AutoRefreshController: debounce
    AutoRefreshController->>LibraryViewModel: repositoriesChanged(paths)
    LibraryViewModel->>StatusMonitor: refresh(changed paths)
```

## GitHub sign-in (OAuth device flow)

The GitHub token stays on the backend; the app only holds a session (#49, #75).

```mermaid
sequenceDiagram
    actor User
    participant AccountModel
    participant RepoHubAPI
    participant APIHandler
    participant AuthService
    participant GitHub
    participant KeychainCredentialStore

    User->>AccountModel: signIn()
    AccountModel->>RepoHubAPI: startDeviceSignIn()
    RepoHubAPI->>APIHandler: POST /auth/device
    APIHandler->>AuthService: startDeviceSignIn()
    AuthService->>GitHub: POST /login/device/code
    GitHub-->>AccountModel: user code + verification URL
    AccountModel->>User: show code, copy it, open github.com/login/device
    User->>GitHub: enter code, approve
    loop every interval seconds
        AccountModel->>APIHandler: POST /auth/device/token
        APIHandler->>AuthService: pollDeviceSignIn()
        AuthService->>GitHub: POST /login/oauth/access_token
        alt not approved yet
            APIHandler-->>AccountModel: 202 pending (or slowDown)
        else approved
            AuthService->>AuthService: encrypt GitHub token (TokenCipher), store User and Device
            APIHandler-->>AccountModel: 200 Session (15-min access token, refresh token)
        end
    end
    AccountModel->>KeychainCredentialStore: save(refresh token)
```

## A cached GitHub request, and live updates

Pull request and CI badges, then a webhook pushing a change (#35, #76, #77).

```mermaid
sequenceDiagram
    participant GitHubStatusModel
    participant APIHandler
    participant RepositoryStatusService
    participant GitHubCache
    participant Redis
    participant GitHub
    participant EventHub

    GitHubStatusModel->>APIHandler: POST /github/status (≤100 repositories)
    APIHandler->>RepositoryStatusService: statuses(for:userID:login:token:)
    RepositoryStatusService->>GitHubCache: fetch(.pullRequests), fetch(.checkRuns(ref:))
    GitHubCache->>Redis: GET gh:v1:<user>:<repo>:pulls
    alt fresh (within the TTL)
        Redis-->>GitHubCache: hit
    else stale or missing
        GitHubCache->>GitHub: GET with If-None-Match: <etag>
        alt 304 Not Modified (free for the rate limit)
            GitHub-->>GitHubCache: revalidated
        else 200
            GitHub-->>GitHubCache: body (+ Link: next pages)
        end
        GitHubCache->>Redis: SET with TTL, add to the repository's index
    end
    APIHandler-->>GitHubStatusModel: pull requests, review requests, combined checks
    Note over GitHub,EventHub: later: a check run finishes
    GitHub->>APIHandler: POST /webhooks/github (HMAC verified)
    APIHandler->>GitHubCache: invalidate(owner:name:) → users with it cached
    APIHandler->>EventHub: publish(RepositoryChange, to: users)
    EventHub-->>GitHubStatusModel: GET /events → "repository" event
    GitHubStatusModel->>APIHandler: POST /github/status (that repository only)
```

## Continuous deployment

A merged pull request reaching production (#38, #43, #62).

```mermaid
sequenceDiagram
    actor Developer
    participant GitHub as GitHub (main)
    participant CI as CI workflow
    participant Deploy as Deploy workflow
    participant Fly as Fly.io
    participant Release as Release workflow

    Developer->>GitHub: squash-merge PR (checks green, linked issue)
    GitHub->>CI: push to main
    GitHub->>Release: push to main
    Release->>GitHub: update the "chore: release X.Y.Z" PR
    CI->>CI: lint, tests (macOS + Linux), UI tests, Docker image, CodeQL
    alt CI failed
        CI--xDeploy: no deploy
    else CI succeeded
        CI->>Deploy: workflow_run (success, push)
        Deploy->>Fly: flyctl deploy --build-arg BUILD_COMMIT=<sha>
        Fly->>Fly: release_command: migrate --yes
        Deploy->>Fly: smoke test /health (this commit) and /ready
        alt smoke test failed
            Deploy->>Fly: redeploy the previous image
        end
    end
```
