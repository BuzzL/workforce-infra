# The workforce-images base image (git, gh, AWS CLI, Terraform, Node, Claude Code: the
# environment the agents run in), plus what `make check` needs beyond it: tflint, trivy,
# actionlint and ruby (scripts/check-workflow.sh). Every download is pinned by version and
# by per-arch SHA256, so this reviewed file is the trust anchor, as in the base image. The
# one exception is ruby from the distribution's apt repository (unpinned: the build is not
# reproducible for it; check-workflow.sh needs Ruby >= 3.1).
# The base is pinned by digest; the tag next to it is what Dependabot tracks, so it
# proposes the bump when a new image is published. The Terraform version must match .terraform-version: the devcontainer
# workflow checks it.
FROM ghcr.io/buzzl/workforce-images/base:0.1.1@sha256:911a2b9afaf8e76818991ca2c1ad918d7a0d01038e707931854c17532fce520d

# Same versions as .github/workflows/ci.yml; the Devcontainer workflow fails when they differ.
ARG TFLINT_VERSION=0.64.0
ARG TFLINT_SHA256_AMD64=cca9d13e2e1d7a2c627af60ff899a3c9b74212899416aeb96ec764d2ef954537
ARG TFLINT_SHA256_ARM64=560da89aacf59389d4eb029730dd5b109b7288096c32f2726a0d9e783a5ea8eb
ARG TRIVY_VERSION=0.74.0
ARG TRIVY_SHA256_AMD64=2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a
ARG TRIVY_SHA256_ARM64=b94ce1976bbf3c15b514b605ee88be7c6d94a29be2302847ff01cb794d47aad5
ARG ACTIONLINT_VERSION=1.7.12
ARG ACTIONLINT_SHA256_AMD64=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
ARG ACTIONLINT_SHA256_ARM64=325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /tmp/install
# TARGETARCH is empty without BuildKit, so the architecture is read from the system.
RUN arch=$(dpkg --print-architecture) \
    && case "${arch}" in \
        amd64) tflint_sha="${TFLINT_SHA256_AMD64}"; trivy_sha="${TRIVY_SHA256_AMD64}"; trivy_arch=64bit; actionlint_sha="${ACTIONLINT_SHA256_AMD64}" ;; \
        arm64) tflint_sha="${TFLINT_SHA256_ARM64}"; trivy_sha="${TRIVY_SHA256_ARM64}"; trivy_arch=ARM64; actionlint_sha="${ACTIONLINT_SHA256_ARM64}" ;; \
        *) echo "unsupported architecture: ${arch}" >&2; exit 1 ;; \
    esac \
    && apt-get update \
    && apt-get install -y --no-install-recommends ruby \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSLO "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_${arch}.zip" \
    && echo "${tflint_sha}  tflint_linux_${arch}.zip" | sha256sum -c - \
    && unzip -q "tflint_linux_${arch}.zip" tflint -d /usr/local/bin \
    && curl -fsSLO "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${trivy_arch}.tar.gz" \
    && echo "${trivy_sha}  trivy_${TRIVY_VERSION}_Linux-${trivy_arch}.tar.gz" | sha256sum -c - \
    && tar --no-same-owner -xzf "trivy_${TRIVY_VERSION}_Linux-${trivy_arch}.tar.gz" -C /usr/local/bin trivy \
    && curl -fsSLO "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${arch}.tar.gz" \
    && echo "${actionlint_sha}  actionlint_${ACTIONLINT_VERSION}_linux_${arch}.tar.gz" | sha256sum -c - \
    && tar --no-same-owner -xzf "actionlint_${ACTIONLINT_VERSION}_linux_${arch}.tar.gz" -C /usr/local/bin actionlint \
    && rm -rf /tmp/install

WORKDIR /home/dev
USER dev
