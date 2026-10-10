# 0009. Distribute the app as an ad-hoc signed DMG, without the App Store

- **Status:** Accepted
- **Date:** 2026-10-08
- **Issue:** #60, #44

## Context and problem statement

RepoHub runs `git` in any folder the user chooses and watches those folders for changes. That conflicts with the Mac App Store's sandbox. A Developer ID certificate (for notarization) needs a paid Apple Developer account.

## Decision drivers

- The app must run `git` against arbitrary folders without per-folder sandbox prompts.
- No paid Apple Developer membership for a course project.

## Considered options

1. Ad-hoc signed app (`CODE_SIGN_IDENTITY = "-"`), hardened runtime, App Sandbox off, DMG on GitHub Releases
2. Sandboxed Mac App Store app with security-scoped bookmarks
3. Developer ID signed and notarized DMG

## Decision outcome

Chosen option: **ad-hoc signed, unsandboxed, distributed as a DMG on GitHub Releases** (#44, currently deferred). Users open it once with right-click → Open.

### Consequences

- Good: full access to the user's repositories and git configuration; no account cost.
- Bad: Gatekeeper warns on first launch; no automatic updates.
- Neutral: the hardened runtime stays enabled. Notarization can be added later if an account becomes available.

## Pros and cons of the options

### Mac App Store

- Good: trusted distribution and updates.
- Bad: the sandbox blocks child processes from accessing user folders and git config without heavy workarounds.

### Developer ID and notarization

- Good: no Gatekeeper warning.
- Bad: requires a paid membership.
