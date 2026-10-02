# Environment and branch model

## Context

The workforce delivers through three environments, `test`, `quality` and `demo`, each in its own AWS account. The production release happens outside this system, from releases.

**Names and keys.** Every account has two identifiers, kept in one table, `scripts/environment-keys.tsv`:

- the **name** is explanatory. It is the AWS account name; for the accounts of the Environments OU it is also the `live/environments/<name>` stack, the GitHub Environment and the `APP_ENV` value. It is used in docs.
- the **key** is exactly four lowercase letters (`^[a-z]{4}$`) and unique. It is used in the naming conventions of AWS resources (role names, policy and resource name patterns), so that they can be checked with strict regexps. A key is never accepted where a name is expected.

| Name | OU | Key | Description |
|---|---|---|---|
| `management` | Management | `root` | Organization management account: billing, Organizations, SSO home |
| `security` | Management | `scrt` | Identity and access administration, audit log archive |
| `workforce` | Development | `wrkf` | Runs the developer agents: webhook, queue, ECS tasks |
| `test` | Environments | `test` | First environment: every pull request deploys here |
| `quality` | Environments | `qual` | Quality checks of main after every merge |
| `demo` | Environments | `demo` | Release demo, needs the maintainer's approval |

`scripts/ci-stacks.sh` reads the table on every run: it maps `live/environments/<name>` for the accounts of the Environments OU and refuses a table with a key that is not four lowercase letters, a duplicate key, an unknown OU, an empty description or no account in the Environments OU. The selftest covers each refusal and that neither `qa` nor the key `qual` maps to a stack. Existing resources keep their names (`github-infra-security`, `github-infra-workforce`); moving them to keyed names is a separate decision.

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
| `quality` | `main`, after merge | none |
| `demo` | a release tag | GitHub Environment reviewer (maintainer) |

The production account is released from releases, outside this system.

Rules that make the chain enforceable:
- **Build once, promote.** CI builds one artifact per commit and records its digest. Each environment deploys that artifact and never rebuilds from source. `demo` deploys the artifact that `quality` ran for the tagged commit.
- **No skipping.** `quality` runs only for a commit whose CI is green. `demo` runs only for a tag whose commit was deployed to `quality`. A tag ruleset restricts tag creation to the release-please App, so a hand-made tag or release cannot start a `demo` deploy.
- **Release trigger.** release-please must create the release with the agent App token. Events created by `GITHUB_TOKEN` do not trigger workflows, so swapping the token would silently stop `demo` deploys. A workflow lint should enforce it, like the App-key check in the testbed.

Rollback has two forms. Inside a `demo` deploy, the canary aborts and rolls back automatically on failed health checks. After a deploy, a manual `workflow_dispatch` takes an earlier commit or release tag and redeploys its artifact to one environment. `demo` still needs the reviewer's approval, `test` and `quality` do not.

### 3. GitHub Environments

Per deployable repo (today: `workforce-testbed`). Names match the AWS account, the `live/environments/<env>` stack and `APP_ENV`.

| Environment | Deployment policy | Protection |
|---|---|---|
| `test` | feature branch patterns (`feature/*`, `bugfix/*`) | none |
| `quality` | `main` | none beyond the branch restriction |
| `demo` | tag pattern (`v*`) | required reviewer: the maintainer |

- The `demo` policy is a **tag pattern**, not a branch pattern, because a `release` run has its ref at the tag.
- "Prevent self-review" is off for `demo`: the maintainer is the only reviewer and also the author, so it would deadlock. The gate is a deliberate pause, not a separation of duties.
- Each environment holds its own OIDC role reference, with no long-lived AWS keys. The roles narrow in privilege: `demo` is narrower than `quality`, which is narrower than `test`.
- `agent-app`, `management` and `management-plan` are outside the `test`/`quality`/`demo` scheme and keep their names.

### 4. Stub period

Until an environment's AWS account and OIDC role exist, its deploy job stays an `echo` stub. The jobs exist for all three environments, so the triggers and protection rules can be tested. A real deploy is enabled per environment as its account lands.
