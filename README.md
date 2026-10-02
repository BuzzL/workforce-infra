# workforce-infra

[![CI](https://github.com/BuzzL/workforce-infra/actions/workflows/ci.yml/badge.svg)](https://github.com/BuzzL/workforce-infra/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Terraform monorepo for the AI Workforce on AWS:

- the **AWS Organization** (OUs, SCPs, member accounts)
- the **workforce** account, which runs the pipeline: Linear webhook → API Gateway → Lambda → SQS → ECS developer agents
- the **environment** accounts, `test`, `quality` and `demo`, which the agents deploy into through least-privilege cross-account roles

> **Status:** early skeleton. Nothing is applied yet. See the [commit history](https://github.com/BuzzL/workforce-infra/commits/main) for what exists so far.

## The AI Workforce repositories

| Repository | Purpose |
|---|---|
| **workforce-infra** | This repo: AWS Organization, accounts and roles |
| [workforce-images](https://github.com/BuzzL/workforce-images) | Developer container images (base, Python) for agents and devcontainers |
| [workforce-testbed](https://github.com/BuzzL/workforce-testbed) | The TypeScript codebase the agents iterate on |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Every commit is short, testable and leaves CI green. This repository is public: real account IDs, emails and ARNs never go in the code.

## License

[Apache-2.0](LICENSE)
