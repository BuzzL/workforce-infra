# workforce-infra

[![CI](https://github.com/BuzzL/workforce-infra/actions/workflows/ci.yml/badge.svg)](https://github.com/BuzzL/workforce-infra/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Terraform monorepo for the AI Workforce on AWS:

- the **AWS Organization** (OUs, SCPs, member accounts)
- the **workforce** account, which runs the pipeline: Linear webhook → API Gateway → Lambda → SQS → ECS developer agents
- the **environment** accounts, `test`, `quality` and `demo`, which the agents deploy into through least-privilege cross-account roles

> **Status:** in progress. The Organization, its OUs, the `security` and `workforce` accounts, the budget exist, and the audit trail is ready (off until its log bucket is configured); the `test`, `quality` and `demo` accounts and their roles are being added. See `docs/` for the decisions and the [commit history](https://github.com/BuzzL/workforce-infra/commits/main) for what has landed.

## The AI Workforce repositories

| Repository | Purpose |
|---|---|
| **workforce-infra** | This repo: AWS Organization, accounts and roles |
| [workforce-images](https://github.com/BuzzL/workforce-images) | Developer container images (base, Python) for agents and devcontainers |
| [workforce-testbed](https://github.com/BuzzL/workforce-testbed) | The TypeScript codebase the agents iterate on |
| [workforce-github](https://github.com/BuzzL/workforce-github) | GitHub as code: repositories, rulesets, environments |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Every commit is short, testable and leaves CI green. This repository is public: real account IDs, emails and ARNs never go in the code.

## License

[Apache-2.0](LICENSE)
