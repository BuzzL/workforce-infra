# Organization inputs: region, SCP exceptions and account emails

Decision record. It fixes the inputs the rest of milestone M2 (Organization stack, accounts, SCPs) reads, so no later change guesses them.

## 1. Region

**Decision:** `eu-south-1` (Milan) is the single allowed region. It is the region of the state bucket and of the Identity Center instance, and it is the value of the `AWS_REGION` variable of the `management` and `management-plan` GitHub Environments. The bootstrap stack already uses it, so nothing moves.

**Why:**
- It is where the Organization, the state and Identity Center already live. Identity Center cannot change its home region without being deleted, and a region-deny SCP must always allow it, so any other region would mean a second region to allow.
- Bedrock offers Claude there. Checked read-only on the management account: the Anthropic foundation models and the `eu.` and `global.` inference profiles are listed in this region, including the current Sonnet, Opus and Haiku models.
- It keeps data in the EU.

**Open risk, to be proven when the SCPs are attached:** Bedrock cross-region inference profiles send the request to other regions. A region-deny SCP evaluates the region where the request runs, so a `eu.` profile needs the EU regions it routes to, and a `global.` profile needs all of them. The workforce account must therefore be tested with the SCP in place, and one of these must be chosen, each with a cost to the single-region goal:
- call the model in `eu-south-1` only, if the models accept on-demand calls there;
- allow the destination regions of one `eu.` profile for Bedrock actions only, through a `Deny` narrowed by `Condition`.

Attach the SCP in stages and run a Bedrock call from the workforce account after each stage. The SCP itself needs the maintainer's explicit approval first.

## 2. Global-service exceptions for the region-deny SCP

The SCP denies every action outside the allowed region, except the actions of services that are global or served from `us-east-1` only. The exceptions are an explicit list of service prefixes, asserted literally in a test. The SCP expresses them with `NotAction` in a `Deny`, narrowed by `StringNotEquals` on `aws:RequestedRegion` (module `modules/scp-baseline`, IAT-35). A `NotAction` is only used in a Deny, never in an Allow, and the PR that defines it needs the maintainer's approval like any SCP. The module defines the four baseline SCPs and attaches none: attaching is staged in IAT-36.

| Area | Service prefixes |
|---|---|
| Identity and access | `iam`, `sts`, `organizations`, `account`, `identitystore`, `sso`, `sso-directory` |
| Billing and cost | `budgets`, `ce`, `cur`, `billing`, `payments`, `tax`, `pricing`, `freetier`, `consolidatedbilling`, `aws-portal` |
| Support and health | `support`, `trustedadvisor`, `health` |
| Global edge and DNS | `route53`, `route53domains`, `cloudfront`, `globalaccelerator`, `waf`, `shield` |

Notes:
- Only prefixes that the stacks use are needed at first (`iam`, `sts`, `organizations`, `account`, `sso`, `identitystore`, `budgets`, `ce`, `support`). Everything else is added when a stack needs it, in the PR that needs it, with its test.
- Identity Center is regional (home region), so its prefixes are listed for the calls that are served from `us-east-1`.

## 3. Account email scheme

**Decision:** one base mailbox with plus-addressing, `<local>+<account>@<domain>`, one address per account: `management`, `security`, `workforce` and later `test`, `qa`, `demo`. The account name is the same lowercase name used everywhere else (see the workspace `CLAUDE.md`).

**Why:** AWS requires a unique email per account, and a plus-address delivers to the same mailbox, so there is nothing to administer per account. Root recovery and alerts all land in one place that the maintainer controls.

**Storage and use:**
- The base address is the **secret** `ACCOUNT_EMAIL_BASE` of the `management` GitHub Environment. It is never a variable, never committed, and never put in a log, a PR comment or Linear.
- Terraform receives it as a sensitive variable through `TF_VAR_account_email_base`, set from the secret in the job `env:` (no `${{ }}` in a `run:` block), and builds each address with `format("%s+%s@%s", local_part, account, domain)`. The variable is `sensitive = true` and has a validation for the `local@domain` shape and for the absence of a `+`.
- Emails are redacted from logs and plan comments by `scripts/redact.sh`.
- The Organization stack sets `email` on each account and ignores later changes to it in `lifecycle`, since the Organizations API cannot change the email of a member account.

## 4. Where each value lives

| Value | Kind | Location | Read by |
|---|---|---|---|
| Region | variable | `AWS_REGION` in `management` and `management-plan` | workflow, as `TF_VAR_region` |
| Global-service exceptions | code | SCP module, with a literal test | Terraform |
| Account email base | secret | `ACCOUNT_EMAIL_BASE` in `management` | apply job, as `TF_VAR_account_email_base` |
| Role ARNs, state bucket | secret | `AWS_ROLE_ARN`, `AWS_ROLE_ID`, `STATE_BUCKET` | workflow (see `BOOTSTRAP.md`) |
