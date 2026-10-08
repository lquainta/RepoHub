## Summary
<!-- What does this PR change and why? -->

Closes #<!-- issue number (required) -->

## How to test
<!-- Steps a reviewer can follow to verify the change. -->

## Screenshots
<!-- Required for UI changes. Delete if not applicable. -->

## Self-review checklist
<!-- Check every box or explain why it does not apply. -->

### Correctness
- [ ] I read my own diff top to bottom before requesting review
- [ ] The change does what the linked issue's acceptance criteria require
- [ ] Error and edge cases are handled (missing `git`, no network, empty states)

### Quality
- [ ] Tests added or updated for new behavior, and they fail without the change
- [ ] `make lint` and `make format-check` pass locally
- [ ] No force unwraps, `try!`, or debug `print` left behind

### Security
- [ ] No secrets, tokens, or credentials in code, logs, or fixtures
- [ ] New configuration is read from environment variables and added to `.env.sample`

### Data
- [ ] Database migrations are reversible (`revert` implemented)
- [ ] Not applicable

### UX
- [ ] No hard-coded user-facing strings (all in the String Catalog)
- [ ] Controls have accessibility labels; status is not conveyed by color alone
- [ ] Not applicable

### Documentation
- [ ] README, architecture diagrams, ADRs, or OpenAPI spec updated if affected
- [ ] Public APIs have doc comments

### Review
- [ ] All Copilot / reviewer comments addressed or resolved with a reply explaining why
