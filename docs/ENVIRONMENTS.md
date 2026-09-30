# Decision record: environment and branch model

Status: accepted (IAT-26). Unblocks the rename in IAT-20.

## Context

The project defines the environments `test`, `qa` and `demo`, replacing `development` and `production`. The real production release is out of scope. Renaming needs a decided branch model, promotion trigger and protection rules first.

## Decisions

### 1. Branch model: trunk-based GitLab flow

There is only `main`. No environment branches and no release branches. Environments are promoted by workflows, so the same immutable build moves from one to the next.

Rejected:
- **Environment branches** (`main` to `test`, `qa` and `demo` branches): promotion by merge causes drift between branches and needs a ruleset per branch.
- **Release branches** (`release/x.y` with cherry-picks): worthwhile for several supported versions, overkill for one deployable.

### 2. Promotion

| Event | Deploys to | Approval |
|---|---|---|
| Merge to `main` | `test` | none |
| release-please release published (SemVer tag) | `qa` | none |
| `qa` deploy succeeded | `demo` | GitHub Environment reviewer (maintainer) |

`demo` uses a canary rollout with automatic rollback (mechanics are defined in milestone M6). Rolling back means redeploying an earlier tag.

### 3. GitHub Environments

Per deployable repo (today: `workforce-testbed`). Names match the AWS account, the `live/environments/<env>` stack and `APP_ENV`.

| Environment | Deploys from | Protection |
|---|---|---|
| `test` | `main` | none |
| `qa` | release tags | none beyond the tag restriction |
| `demo` | release tags | required reviewer: the maintainer |

Each environment holds its own OIDC role reference, with no long-lived AWS keys. `agent-app` is unrelated and unchanged.

### 4. AWS side and stub period

The `qa` and `demo` accounts are created in M3. Until each account and its OIDC role exist, its deploy job stays an `echo` stub. The jobs exist for all three environments from the start, so the triggers and protection rules can be tested. A real deploy is enabled per environment as its account lands.

### 5. Rename (IAT-20)

`development` becomes `test`, `production` becomes `demo`, and `qa` is added. The testbed PR also wires the triggers above.
