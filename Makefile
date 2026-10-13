# Every gate that loops over stacks lives in scripts/each.sh. Recipes stay one-liners
# because macOS ships Make 3.81, which cannot make recipes fail fast on its own.
.PHONY: fmt validate lint versions dependabot sec test workflows lifecycle accounts docs codeowners matrix selftest check
check: fmt validate lint versions dependabot sec test workflows lifecycle accounts docs codeowners matrix selftest

fmt:
	terraform fmt -check -recursive -diff

validate:
	scripts/each.sh validate

lint:
	scripts/each.sh lint

versions:
	scripts/each.sh versions

dependabot:
	scripts/each.sh dependabot

sec:
	trivy config --exit-code 1 --severity HIGH,CRITICAL --skip-dirs '**/.terraform' .

test:
	scripts/each.sh test

workflows:
	actionlint
	scripts/check-workflow.sh

# What must not disappear carries prevent_destroy (terraform test cannot plan a destroy).
lifecycle:
	scripts/check-prevent-destroy.sh

# Every account of the Organization stack has a row, in the same OU, in the table of names and keys.
accounts:
	scripts/check-accounts.sh

# The repo is public: no account IDs, ARNs with IDs or emails in docs.
docs:
	scripts/check-docs-public.sh

# The paths that decide what CI may do are listed in CODEOWNERS and exist.
codeowners:
	scripts/check-codeowners.sh

# The allowed/denied matrix agrees with the narrowing rule and with the Allow statements of the role modules.
matrix:
	scripts/check-permission-matrix.sh

# Proves the gates above pass on valid code and fail on broken code.
selftest:
	scripts/test-tooling.sh
