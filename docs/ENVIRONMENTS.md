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

Rules that make the chain enforceable:
- **Build once, promote.** The release workflow builds one artifact and passes its digest along. `qa` and `demo` deploy that artifact and never rebuild from source. (The current stub `deploy.yml` still rebuilds per job; the testbed PR that wires the triggers replaces that.)
- **No skipping.** `qa` and `demo` are jobs in the release-triggered workflow with a `needs:` chain, and `qa` verifies that CI is green and that `test` deployed the same commit. A tag ruleset restricts tag creation to the release-please App, so a hand-made tag or release cannot start the chain.
- **Release trigger.** release-please must create the release with the agent App token. Events created by `GITHUB_TOKEN` do not trigger workflows, so swapping the token would silently stop `qa` and `demo` deploys. A workflow lint should enforce it, like the App-key check in the testbed.

Rollback has two forms. Inside a `demo` deploy, the canary aborts and rolls back automatically on failed health checks (mechanics: milestone M6). After a deploy, a manual `workflow_dispatch` takes an earlier release tag and redeploys that artifact to one environment. `demo` still needs the reviewer's approval, `test` and `qa` do not.

### 3. GitHub Environments

Per deployable repo (today: `workforce-testbed`). Names match the AWS account, the `live/environments/<env>` stack and `APP_ENV`.

| Environment | Deploys from | Protection |
|---|---|---|
| `test` | `main` | none |
| `qa` | release tags | none beyond the tag restriction |
| `demo` | release tags | required reviewer: the maintainer |

- Deployment policies for `qa` and `demo` are **tag patterns** (for example `v*`), not branch patterns, because a `release` run has its ref at the tag.
- "Prevent self-review" is off for `demo`: the maintainer is the only reviewer and also the author, so it would deadlock. The gate is a deliberate pause, not a separation of duties.
- Each environment holds its own OIDC role reference, with no long-lived AWS keys. The roles narrow in privilege: `demo` is narrower than `qa`, which is narrower than `test`.
- `agent-app`, `management` and `management-plan` are outside the `test`/`qa`/`demo` scheme and keep their names.

### 4. AWS side and stub period

The `test` account and its OIDC role come first. The `qa` and `demo` accounts are created in M3. Until each account and its OIDC role exist, its deploy job stays an `echo` stub. The jobs exist for all three environments from the start, so the triggers and protection rules can be tested. A real deploy is enabled per environment as its account lands.

### 5. Rename (IAT-20)

`development` becomes `test`, `production` becomes `demo`, and `qa` is added. The testbed PR also wires the triggers above.

`production` changes meaning when it becomes `demo` (a reviewer gate on release deploys). The old `development` and `production` GitHub Environments are deleted after their variables and secrets are recreated under the new names, with the maintainer's approval. Terraform stacks follow `live/environments/<env>` and are renamed in the same IAT-20 change.
