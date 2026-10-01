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
need.(jobs.keys.sort == %w[apply comment discover plan], "the workflow must have exactly the jobs apply, comment, discover, plan")
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
  "apply" => { "id-token" => "write", "contents" => "read" },
}.each { |j, p| need.(jobs[j]["permissions"] == p, "#{j}: permissions must be exactly #{p}") }

# Conditions and environments, compared as whole strings.
need.(norm.(jobs["plan"]["if"]) == "github.event_name == \x27pull_request\x27 && github.event.pull_request.head.repo.full_name == github.repository && needs.discover.outputs.plan_stacks != \x27[]\x27", "plan: the condition must skip forks and other events")
need.(norm.(jobs["comment"]["if"]) == "always() && (needs.plan.result == \x27success\x27 || needs.plan.result == \x27failure\x27)", "comment: it must only post a finished plan")
need.(norm.(jobs["apply"]["if"]) == "github.event_name == \x27push\x27 && needs.discover.outputs.apply_stacks != \x27[]\x27", "apply: it must only run on push")
%w[plan apply].each { |j| need.(jobs[j]["environment"] == "${{ matrix.environment }}", "#{j}: it must run in the environment of its stack") }
%w[discover comment].each { |j| need.(!jobs[j].key?("environment"), "#{j}: it must have no environment") }
need.(jobs["plan"].dig("concurrency", "cancel-in-progress") == true, "plan: an older plan must be cancelled by a newer push")
need.(jobs["apply"].dig("concurrency", "cancel-in-progress") == false, "apply: an apply must never be cancelled")

# Job env: the secrets that must be masked are referenced, and are secrets.
%w[plan apply].each do |j|
  e = jobs[j]["env"] || {}
  need.(e["STATE_BUCKET"] == "${{ secrets.STATE_BUCKET }}", "#{j}: STATE_BUCKET must be a secret")
  need.(e["AWS_ROLE_ID"] == "${{ secrets.AWS_ROLE_ID }}", "#{j}: AWS_ROLE_ID must be referenced so that it is masked")
  need.(e["TF_VAR_root_id"] == "${{ secrets.ORGANIZATION_ROOT_ID }}", "#{j}: the Organization root ID must be a secret")
  need.(e["TF_VAR_account_email_base"] == "${{ secrets.ACCOUNT_EMAIL_BASE }}", "#{j}: the account email base must be a secret")
  need.(e["TF_VAR_budget_alert_email"] == "${{ secrets.BUDGET_ALERT_EMAIL }}", "#{j}: the budget alert address must be a secret")
end

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

# Contexts: the only variable is AWS_REGION, the only secrets are the five below, no bracket syntax.
text.scan(/\$\{\{(.*?)\}\}/m).flatten.each do |expr|
  expr.scan(/\bvars\s*\.\s*(\w+)/i).flatten.each { |n| need.(n == "AWS_REGION", "variable not allowed: #{n}") }
  expr.scan(/\bsecrets\s*\.\s*(\w+)/i).flatten.each { |n| need.(%w[AWS_ROLE_ARN AWS_ROLE_ID STATE_BUCKET ORGANIZATION_ROOT_ID ACCOUNT_EMAIL_BASE BUDGET_ALERT_EMAIL].include?(n), "secret not allowed: #{n}") }
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

# The comment job: one script checked out, an artifact downloaded, the comment updated in place.
c = jobs["comment"]["steps"]
need.(c.map { |s| s["uses"].to_s.split("@").first.to_s }.reject(&:empty?).sort == %w[actions/checkout actions/download-artifact], "comment: only checkout and download-artifact are allowed")
need.((c.find { |s| s["uses"].to_s.start_with?("actions/checkout") }["with"] || {})["sparse-checkout"] == "scripts/redact.sh", "comment: it may check out scripts/redact.sh only")
need.(c.map { |s| s["run"].to_s }.join.include?("--edit-last"), "comment: the comment must be updated in place")
need.(c.map { |s| s["run"].to_s }.join.include?("scripts/redact.sh"), "comment: it must redact again")

abort(errors.join("\n")) unless errors.empty?
puts "workflow structure OK"
' "${1:-.github/workflows/terraform.yml}"
