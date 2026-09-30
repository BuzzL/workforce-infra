# Environment and branch model

## Context

The workforce delivers through three environments, `test`, `qa` and `demo`, each in its own AWS account. The production release happens outside this system, from releases.

## Decisions

### 1. Branch model: trunk-based GitLab flow

There is only `main`. No environment branches and no release branches. Feature branches are short-lived and merge into `main`. Environments are promoted by workflows, so the same build moves from one to the next.

Rejected:
- **Environment branches**: promotion by merge causes drift between branches and needs a ruleset per branch.
- **Release branches** (`release/x.y` with cherry-picks): worthwhile for several supported versions, overkill for one deployable.

### 2. Promotion

| Environment | Deploys from | Approval |
|---|---|---|
| `test` | a feature branch, before merge | none |
| `qa` | `main`, after merge | none |
| `demo` | a release tag | GitHub Environment reviewer (maintainer) |

The production account is released from releases, outside this system.

Rules that make the chain enforceable:
- **Build once, promote.** CI builds one artifact per commit and records its digest. Each environment deploys that artifact and never rebuilds from source. `demo` deploys the artifact that `qa` ran for the tagged commit.
- **No skipping.** `qa` runs only for a commit whose CI is green. `demo` runs only for a tag whose commit was deployed to `qa`. A tag ruleset restricts tag creation to the release-please App, so a hand-made tag or release cannot start a `demo` deploy.
- **Release trigger.** release-please must create the release with the agent App token. Events created by `GITHUB_TOKEN` do not trigger workflows, so swapping the token would silently stop `demo` deploys. A workflow lint should enforce it, like the App-key check in the testbed.

Rollback has two forms. Inside a `demo` deploy, the canary aborts and rolls back automatically on failed health checks. After a deploy, a manual `workflow_dispatch` takes an earlier commit or release tag and redeploys its artifact to one environment. `demo` still needs the reviewer's approval, `test` and `qa` do not.

### 3. GitHub Environments

Per deployable repo (today: `workforce-testbed`). Names match the AWS account, the `live/environments/<env>` stack and `APP_ENV`.

| Environment | Deployment policy | Protection |
|---|---|---|
| `test` | feature branch patterns (`feature/*`, `bugfix/*`) | none |
| `qa` | `main` | none beyond the branch restriction |
| `demo` | tag pattern (`v*`) | required reviewer: the maintainer |

- The `demo` policy is a **tag pattern**, not a branch pattern, because a `release` run has its ref at the tag.
- "Prevent self-review" is off for `demo`: the maintainer is the only reviewer and also the author, so it would deadlock. The gate is a deliberate pause, not a separation of duties.
- Each environment holds its own OIDC role reference, with no long-lived AWS keys. The roles narrow in privilege: `demo` is narrower than `qa`, which is narrower than `test`.
- `agent-app`, `management` and `management-plan` are outside the `test`/`qa`/`demo` scheme and keep their names.

### 4. Stub period

Until an environment's AWS account and OIDC role exist, its deploy job stays an `echo` stub. The jobs exist for all three environments, so the triggers and protection rules can be tested. A real deploy is enabled per environment as its account lands.
