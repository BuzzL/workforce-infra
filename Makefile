# Every gate that loops over stacks lives in scripts/each.sh. Recipes stay one-liners
# because macOS ships Make 3.81, which cannot make recipes fail fast on its own.
.PHONY: fmt validate lint versions dependabot sec test workflows selftest check
check: fmt validate lint versions dependabot sec test workflows selftest

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

# Proves the gates above pass on valid code and fail on broken code.
selftest:
	scripts/test-tooling.sh
