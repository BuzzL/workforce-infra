# Contributing

Thanks for your interest in workforce-infra. It is part of the [AI Workforce](https://github.com/BuzzL?tab=repositories&q=workforce-) project: an AI developer workforce on AWS, built to explore how to take code review out of the critical path.

## Commit rule

Every commit must be:

1. **Short**: one logical change.
2. **Testable**: it comes with the check that proves it works (a test, a validation, a CI job).
3. **Not breakable**: CI is green at that commit on its own. Gate unfinished work behind a disabled or manual trigger instead of committing failing code.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org): `feat:`, `fix:`, `docs:`, `test:`, `build:`, `ci:`, `chore:`, `refactor:`. Releases and changelogs are generated from them by release-please, so the type matters.

## Pull requests

- `main` is protected: every change lands through a PR with green CI.
- PRs are squash-merged, so the PR title becomes the commit subject and must follow Conventional Commits too.
- Keep PRs small. A reviewer should be able to verify one in minutes.

## Secrets

This repository is public. Never commit credentials, AWS account IDs, account emails or ARNs. CI runs gitleaks on every push.
