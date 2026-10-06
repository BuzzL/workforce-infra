#!/usr/bin/env bash
# Structural checks of .github/workflows/terraform.yml that actionlint does not make: what
# keeps credentials away from pull-request code and identifiers out of public logs. The
# workflow is parsed, and each job is compared with an exact allowlist, so a plausible
# edit (a wider permission, a second action, a case change) fails instead of slipping by.
# Usage: check-workflow.sh [workflow-file]
set -euo pipefail
cd "$(dirname "$0")/.."
exec ruby -ryaml -e '
path = ARGV[0]
text = File.read(path)
doc = YAML.safe_load(text, aliases: false)
errors = []
need = ->(cond, msg) { errors << msg unless cond }
norm = ->(s) { s.to_s.gsub(/\s+/, " ").strip }

jobs = doc["jobs"] || {}
need.(jobs.keys.sort == %w[apply changes comment discover plan], "the workflow must have exactly the jobs apply, changes, comment, discover, plan")
abort(errors.join("\n")) unless errors.empty?

# Triggers: no pull_request_target, workflow_run or manual runs.
on = doc["on"] || doc[true] || {}
need.(on.keys.sort == %w[pull_request push], "only the pull_request and push triggers are allowed")
need.(on.dig("push", "branches") == ["main"], "push must be limited to main")
need.(doc["permissions"] == {}, "workflow-level permissions must be {}")

# Permissions are compared exactly: only the comment job may write to pull requests.
{
  "discover" => { "contents" => "read" },
  "plan" => { "id-token" => "write", "contents" => "read" },
  "comment" => { "pull-requests" => "write", "contents" => "read" },
  "changes" => { "contents" => "read" },
  "apply" => { "id-token" => "write", "contents" => "read" },
}.each { |j, p| need.(jobs[j]["permissions"] == p, "#{j}: permissions must be exactly #{p}") }

# Conditions and environments, compared as whole strings.
need.(norm.(jobs["plan"]["if"]) == "(github.event_name == \x27push\x27 || (github.event_name == \x27pull_request\x27 && github.event.pull_request.head.repo.full_name == github.repository)) && needs.discover.outputs.plan_stacks != \x27[]\x27", "plan: the condition must skip forks and other events")
need.(norm.(jobs["comment"]["if"]) == "always() && github.event_name == \x27pull_request\x27 && (needs.plan.result == \x27success\x27 || needs.plan.result == \x27failure\x27)", "comment: it must only post a finished plan, on a pull request")
need.(jobs["changes"]["if"] == "github.event_name == \x27push\x27", "changes: it must only run on push")
need.(jobs["changes"]["needs"] == "plan", "changes: it must wait for the plans, and only run when they succeeded")
need.(norm.(jobs["apply"]["if"]) == "github.event_name == \x27push\x27 && needs.changes.outputs.apply_stacks != \x27[]\x27", "apply: it must only run on push, for the stacks with changes")
need.(jobs["apply"]["needs"] == "changes", "apply: it must wait for changes, which keeps the stacks without changes away from the approval")
need.(jobs["apply"].dig("strategy", "matrix", "include") == "${{ fromJSON(needs.changes.outputs.apply_stacks) }}", "apply: the matrix must be the stacks that changes passed")
%w[plan apply].each { |j| need.(jobs[j]["environment"] == "${{ matrix.environment }}", "#{j}: it must run in the environment of its stack") }
%w[discover changes comment].each { |j| need.(!jobs[j].key?("environment"), "#{j}: it must have no environment") }
need.(jobs["plan"].dig("concurrency", "cancel-in-progress") == true, "plan: an older plan must be cancelled by a newer push")
need.(jobs["apply"].dig("concurrency", "cancel-in-progress") == false, "apply: an apply must never be cancelled")

# Job env: the secrets that must be masked are referenced, and are secrets.
%w[plan apply].each do |j|
  e = jobs[j]["env"] || {}
  need.(e["STATE_BUCKET"] == "${{ secrets.STATE_BUCKET }}", "#{j}: STATE_BUCKET must be a secret")
  need.(e["AWS_ROLE_ID"] == "${{ secrets.AWS_ROLE_ID }}", "#{j}: AWS_ROLE_ID must be referenced so that it is masked")
  need.(e["TF_VAR_root_id"] == "${{ secrets.ORGANIZATION_ROOT_ID }}", "#{j}: the Organization root ID must be a secret")
  need.(e["TF_VAR_account_email_base"] == "${{ secrets.ACCOUNT_EMAIL_BASE }}", "#{j}: the account email base must be a secret")
  need.(e["TF_VAR_member_account_ids"] == "${{ secrets.MEMBER_ACCOUNT_IDS || \x27{}\x27 }}", "#{j}: the member account IDs must be a secret")
  need.(e["TF_VAR_budget_alert_email"] == "${{ secrets.BUDGET_ALERT_EMAIL }}", "#{j}: the budget alert address must be a secret")
  need.(e["TF_VAR_maintainer_username"] == "${{ secrets.MAINTAINER_USERNAME }}", "#{j}: the maintainer user name must be a secret")
  need.(e["TF_VAR_assignment_account_ids"] == "${{ secrets.ASSIGNMENT_ACCOUNT_IDS || \x27{}\x27 }}", "#{j}: the assignment account IDs must be a secret")
  need.(e["TF_VAR_audit_log_bucket_name"] == "${{ secrets.AUDIT_LOG_BUCKET }}", "#{j}: the audit log bucket name must be a secret")
  need.(e["AUDIT_LOG_BUCKET"] == "${{ secrets.AUDIT_LOG_BUCKET }}", "#{j}: AUDIT_LOG_BUCKET must be referenced so that it is masked and redacted")
  need.(e["TF_VAR_organization_id"] == "${{ secrets.ORGANIZATION_ID }}", "#{j}: the Organization ID must be a secret")
  need.(e["TF_VAR_management_account_id"] == "${{ secrets.MANAGEMENT_ACCOUNT_ID }}", "#{j}: the management account ID must be a secret")
end

# The agent role variable (IAT-92) reaches the Plan step of the plan job only: the apply job never plans
# a baseline, and no other step needs the ExternalId.
plan_step = jobs["plan"]["steps"].find { |s| s["id"] == "plan" } || {}
need.((plan_step["env"] || {})["TF_VAR_agent"] == "${{ secrets.AGENT || \x27null\x27 }}", "plan: the agent role must come from the secret AGENT, null when unset")
need.(text.scan(/secrets\s*\.\s*AGENT\b/i).size == 1, "the secret AGENT must be used once, as TF_VAR_agent of the Plan step of the plan job")
# Same for the matrix runner roles of the workforce account (IAT-46).
need.((plan_step["env"] || {})["TF_VAR_matrix"] == "${{ secrets.MATRIX || \x27null\x27 }}", "plan: the matrix runner roles must come from the secret MATRIX, null when unset")
need.(text.scan(/secrets\s*\.\s*MATRIX\b/i).size == 1, "the secret MATRIX must be used once, as TF_VAR_matrix of the Plan step of the plan job")

# Actions: an allowlist, pinned by commit SHA (case-sensitive), checkout without credentials.
allowed = %r{\A(actions/checkout|hashicorp/setup-terraform|aws-actions/configure-aws-credentials|actions/upload-artifact|actions/download-artifact)@[0-9a-f]{40}\z}
jobs.each do |j, job|
  (job["steps"] || []).each do |s|
    next unless s["uses"]
    need.(s["uses"] =~ allowed, "#{j}: action not allowed or not pinned by commit SHA: #{s["uses"]}")
    if s["uses"].start_with?("actions/checkout")
      need.((s["with"] || {})["persist-credentials"] == false, "#{j}: checkout must not persist credentials")
    end
  end
end

# Credentials: exactly one step in plan and apply, none elsewhere; secret role, masked account ID.
jobs.each do |j, job|
  creds = (job["steps"] || []).select { |s| s["uses"].to_s.start_with?("aws-actions/configure-aws-credentials") }
  if %w[plan apply].include?(j)
    need.(creds.size == 1, "#{j}: exactly one credentials step is expected")
    w = (creds.first || {})["with"] || {}
    need.(w["role-to-assume"] == "${{ secrets.AWS_ROLE_ARN }}", "#{j}: the role must come from the secret AWS_ROLE_ARN")
    need.(w["mask-aws-account-id"] == true, "#{j}: the credentials step must mask the account ID")
    need.(w["aws-region"] == "${{ vars.AWS_REGION }}", "#{j}: the region must come from the variable AWS_REGION")
  else
    need.(creds.empty?, "#{j}: no credentials step is allowed")
  end
end

# Contexts: the only variable is AWS_REGION, the only secrets are the thirteen below, no bracket syntax.
text.scan(/\$\{\{(.*?)\}\}/m).flatten.each do |expr|
  expr.scan(/\bvars\s*\.\s*(\w+)/i).flatten.each { |n| need.(n == "AWS_REGION", "variable not allowed: #{n}") }
  expr.scan(/\bsecrets\s*\.\s*(\w+)/i).flatten.each { |n| need.(%w[AWS_ROLE_ARN AWS_ROLE_ID STATE_BUCKET ORGANIZATION_ROOT_ID ACCOUNT_EMAIL_BASE BUDGET_ALERT_EMAIL MEMBER_ACCOUNT_IDS MAINTAINER_USERNAME ASSIGNMENT_ACCOUNT_IDS AUDIT_LOG_BUCKET ORGANIZATION_ID MANAGEMENT_ACCOUNT_ID AGENT MATRIX].include?(n), "secret not allowed: #{n}") }
  need.(expr !~ /\b(vars|secrets)\s*\[/i, "vars and secrets must not use bracket syntax: #{expr.strip}")
  need.(expr !~ /\bsecrets\s*(\}|$)/i, "the whole secrets context must not be used")
end
need.(jobs.reject { |k, _| k == "comment" }.values.none? { |job| job.to_s.include?("github.token") }, "only the comment job may use github.token")

# Scripts: no expression in a script, no debugging or encoding of values, and every terraform
# call in the credential jobs goes through the redaction.
jobs.each do |j, job|
  (job["steps"] || []).each do |s|
    run = s["run"].to_s
    next if run.empty?
    need.(!run.include?("${{"), "#{j}: expression inside a run script: #{run.lines.grep(/\$\{\{/).first.to_s.strip[0, 70]}")
    if %w[plan apply].include?(j)
      need.(run !~ /set\s+-\w*x|printenv|\bbase64\b|\bxxd\b|\bod\s+-|\bcurl\b|\bwget\b/, "#{j}: a script that could print or send values: #{s["name"] || run.lines.first.to_s.strip}")
      if run =~ /terraform\s+(init|plan|apply)/
        need.(run.include?("scripts/redact.sh"), "#{j}: terraform output must go through scripts/redact.sh: #{s["name"]}")
      end
    end
  end
end
plan_run = (jobs["plan"]["steps"].find { |s| s["id"] == "plan" } || {})["run"].to_s.lines.reject { |l| l.strip.start_with?("#") }.map { |l| l.sub(/\s#.*$/, "") }.join
need.(plan_run =~ /terraform plan[^\n]*-lock=false/, "plan: terraform plan must run with -lock=false")
apply_step = (jobs["apply"]["steps"].find { |s| s["name"] == "Apply" } || {})
need.(norm.(apply_step["if"]) == "matrix.apply == true && steps.plan.outputs.exitcode == \x272\x27", "apply: Apply must be guarded by matrix.apply == true")

# The changes job: the gate runs the plan results through ci-stacks.sh, nothing else.
g = jobs["changes"]["steps"]
need.(g.map { |s| s["uses"].to_s.split("@").first.to_s }.reject(&:empty?).sort == %w[actions/checkout actions/download-artifact], "changes: only checkout and download-artifact are allowed")
need.(g.map { |s| s["run"].to_s }.join.include?("scripts/ci-stacks.sh gate"), "changes: the plan results must go through scripts/ci-stacks.sh gate")
need.(g.map { |s| s["run"].to_s }.join.include?("set -euo pipefail"), "changes: the gate step must fail on a failed gate")
need.(((g.find { |s| s["uses"].to_s.start_with?("actions/download-artifact") } || {})["with"] || {}).values_at("pattern", "merge-multiple") == ["plan-*", true], "changes: it must download every plan artifact")
need.(jobs["changes"].dig("outputs", "apply_stacks") == "${{ steps.gate.outputs.apply }}", "changes: apply_stacks must be the output of the gate")
need.(jobs["plan"]["steps"].any? { |s| s["uses"].to_s.start_with?("actions/upload-artifact") && s.dig("with", "path").to_s.include?("result-") }, "plan: the result file must be uploaded")

# The comment job: one script checked out, an artifact downloaded, the comment updated in place.
c = jobs["comment"]["steps"]
need.(c.map { |s| s["uses"].to_s.split("@").first.to_s }.reject(&:empty?).sort == %w[actions/checkout actions/download-artifact], "comment: only checkout and download-artifact are allowed")
need.((c.find { |s| s["uses"].to_s.start_with?("actions/checkout") }["with"] || {})["sparse-checkout"] == "scripts/redact.sh", "comment: it may check out scripts/redact.sh only")
need.(c.map { |s| s["run"].to_s }.join.include?("--edit-last"), "comment: the comment must be updated in place")
need.(c.map { |s| s["run"].to_s }.join.include?("scripts/redact.sh"), "comment: it must redact again")

abort(errors.join("\n")) unless errors.empty?
puts "workflow structure OK"
' "${1:-.github/workflows/terraform.yml}"
