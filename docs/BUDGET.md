# Budget

The monthly cost budget of the Organization, managed by `live/management` through `modules/budget`.

## What it is

| | |
|---|---|
| Name | `Workforce Budget` (`budget_name`) |
| Limit | 20 USD per month (`budget_limit_usd`) |
| Covers | `UnblendedCost` billed to the management account, which includes the member accounts of the Organization (consolidated billing), with the AWS default cost types: credits and refunds are netted, taxes and support are counted, nothing is amortized. No filters. While credits exist, the alerts fire later than the invoice would suggest. |
| Alerts | Actual spend above 50%, 80% and 100% of the limit |
| Sent to | The address in the secret `BUDGET_ALERT_EMAIL` of the `management` and `management-plan` GitHub Environments, passed as `TF_VAR_budget_alert_email`. It is never committed. |

The limit is a plain variable with a default so that raising it is a reviewed change. The alerts are a notification only: nothing stops spending when the limit is reached.

## Rule

Billable resources (the CloudTrail bucket, later ECR and ECS) are created only after this budget is in Terraform.

## How it was brought under Terraform

The budget was created by hand. `live/management/budget.tf` has an `import` block (`<account id>:<budget name>`, the account ID read from the caller identity, so nothing identifying is committed), so the first apply adopts it instead of recreating it. The plan before that apply showed one in-place update: the stack's default tags are added to the budget. Everything else (name, limit, period, the three notifications and their address) matched.

`metrics` is ignored in `modules/budget`: AWS sets `UnblendedCost` itself and the provider only accepts the attribute together with a filter expression, so leaving it unmanaged avoids a diff on every plan. Once the first apply has run, the `import` block does nothing and is removed in a later PR.

## Changing it

- Limit: change `budget_limit_usd` (and the literal in `live/management/tests/budget.tftest.hcl`).
- Address: update the secret with `BUDGET_ALERT_EMAIL=... scripts/set-environment-secrets.sh`.
- Thresholds: `modules/budget` (`thresholds_percent`) and its test, which asserts 50/80/100 literally.

## Limits of the plan output

- The alert addresses are sensitive, so Terraform masks every whole `notification` block in a plan: a change to a threshold or a comparison operator does **not** show in the PR comment. The thresholds are guarded by the literal assertions in `modules/budget/tests/budget.tftest.hcl`, so such a change must edit that test, which does show in the diff. The first plan after the import cannot show the notifications either: the match was checked with a local plan against the account, from the plan JSON, before the first apply.
- `BUDGET_ALERT_EMAIL` is a secret of `management-plan` like the other secrets, so a same-repository branch job can read it (forks are skipped). It is a personal mailbox: the environment's branch policy is the guard.
- The import itself is only proven by a real plan: with a mock provider the resource is overridden, so `live/management/tests/budget.tftest.hcl` proves the wiring (name, limit, address), not the import.
- `budget_name` has a default in `bootstrap/` (the IAM ARN) and in `live/management/`. If they differ the plan fails closed with AccessDenied.
