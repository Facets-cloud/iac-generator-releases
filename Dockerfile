# syntax=docker/dockerfile:1
# Start from a lightweight official base
FROM debian:bookworm-slim

# Build arguments
ARG IAC_GENERATOR_VERSION
ARG TARGETARCH

# Versions
ENV TERRAFORM_VERSION=1.5.7-facets.0.1
ENV OPENTOFU_VERSION=1.12.3
ENV IAC_GENERATOR_VERSION=${IAC_GENERATOR_VERSION}

# Install utilities and Terraform
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    zip \
    unzip \
    git \
    vim \
    jq \
    less \
    iputils-ping \
    dnsutils \
    net-tools \
    ca-certificates \
    bash-completion \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --no-cache-dir --break-system-packages boto3 google-cloud-secret-manager awscli pyyaml

# Install Terraform (Facets fork — private repo, fetched via GitHub API with a
# BuildKit-mounted PAT). Token must have `Contents: Read` on
# Facets-cloud/terraform. Pass at build time:
#   docker build --secret id=gh_token,env=FACETS_TERRAFORM_TOKEN ...
RUN --mount=type=secret,id=gh_token \
    set -eux; \
    GH_TOKEN=$(cat /run/secrets/gh_token); \
    ARCH=${TARGETARCH:-amd64}; \
    ASSET_NAME="terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip"; \
    ASSET_ID=$(curl -fsSL \
        -H "Authorization: Bearer ${GH_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/Facets-cloud/terraform/releases/tags/v${TERRAFORM_VERSION}" \
        | jq -r --arg name "${ASSET_NAME}" '.assets[] | select(.name==$name) | .id'); \
    test -n "${ASSET_ID}" || { echo "asset ${ASSET_NAME} not found in release v${TERRAFORM_VERSION}" >&2; exit 1; }; \
    curl -fsSL \
        -H "Authorization: Bearer ${GH_TOKEN}" \
        -H "Accept: application/octet-stream" \
        "https://api.github.com/repos/Facets-cloud/terraform/releases/assets/${ASSET_ID}" \
        -o terraform.zip; \
    unzip terraform.zip; \
    mv terraform /usr/local/bin/; \
    rm terraform.zip

# Install OpenTofu (public release — no token required). Selected per project-type
# iacTool=OPENTOFU; the generator shells out to `tofu` when an OpenTofu project
# type is referenced.
RUN set -eux; \
    ARCH=${TARGETARCH:-amd64}; \
    curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${OPENTOFU_VERSION}/tofu_${OPENTOFU_VERSION}_linux_${ARCH}.zip" \
        -o tofu.zip; \
    unzip tofu.zip tofu; \
    mv tofu /usr/local/bin/; \
    chmod +x /usr/local/bin/tofu; \
    rm tofu.zip

# Install iac-generator
RUN set -eux; \
    ARCH=${TARGETARCH:-amd64}; \
    echo "Downloading iac-generator ${IAC_GENERATOR_VERSION} for linux_${ARCH}"; \
    curl -fsSL "https://github.com/Facets-cloud/iac-generator-releases/releases/download/${IAC_GENERATOR_VERSION}/iac-generator_${IAC_GENERATOR_VERSION#v}_linux_${ARCH}.tar.gz" \
        -o iac-generator.tar.gz; \
    tar -xzf iac-generator.tar.gz; \
    mv iac-generator /usr/local/bin/; \
    chmod +x /usr/local/bin/iac-generator; \
    rm iac-generator.tar.gz

# Spoofed aws3tooling provider for legacy capillary-cloud-tf envs.
# State in those envs has resources bound to registry.terraform.io/hashicorp/aws3tooling
# (the old Python IaC generator emitted `provider "aws3tooling" {}` without
# required_providers, synthesizing that source path). The public registry has no
# such provider, so we place the real hashicorp/aws binary under the aws3tooling
# path and serve it via a filesystem mirror.
ARG TOOLING_AWS_VERSION=3.74.0

# Install the binary under both registry hosts. Terraform expands a bare
# `aws3tooling` provider to registry.terraform.io (matching the legacy state),
# while OpenTofu expands a bare provider to its own registry.opentofu.org. Place
# the spoof under both so it resolves regardless of which host the effective
# provider source carries.
RUN set -eux; \
    ARCH=${TARGETARCH:-amd64}; \
    curl -fsSL "https://releases.hashicorp.com/terraform-provider-aws/${TOOLING_AWS_VERSION}/terraform-provider-aws_${TOOLING_AWS_VERSION}_linux_${ARCH}.zip" -o /tmp/aws.zip; \
    for host in registry.terraform.io registry.opentofu.org; do \
        DIR="/usr/local/share/terraform/plugins/${host}/hashicorp/aws3tooling/${TOOLING_AWS_VERSION}/linux_${ARCH}"; \
        mkdir -p "$DIR"; \
        unzip -p /tmp/aws.zip "terraform-provider-aws*" > "${DIR}/terraform-provider-aws3tooling_v${TOOLING_AWS_VERSION}"; \
        chmod 0755 "${DIR}/terraform-provider-aws3tooling_v${TOOLING_AWS_VERSION}"; \
    done; \
    rm /tmp/aws.zip

# Make both engines resolve the spoofed provider from the local mirror.
# Terraform would discover /usr/local/share/terraform/plugins implicitly, but
# OpenTofu does not search that path (its implied dirs are user-scoped). Pin an
# explicit CLI config via TF_CLI_CONFIG_FILE — honored by BOTH terraform and
# tofu — that serves aws3tooling from the mirror and everything else from the
# registry. Both registry hosts are included so a bare provider resolves under
# either engine. The mirror auto-selects the matching linux_<arch> subdir.
ENV TF_CLI_CONFIG_FILE=/etc/iac/cli.tfrc
RUN set -eux; mkdir -p /etc/iac; \
    printf '%s\n' \
      'provider_installation {' \
      '  filesystem_mirror {' \
      '    path    = "/usr/local/share/terraform/plugins"' \
      '    include = [' \
      '      "registry.terraform.io/hashicorp/aws3tooling",' \
      '      "registry.opentofu.org/hashicorp/aws3tooling",' \
      '    ]' \
      '  }' \
      '  direct {' \
      '    exclude = [' \
      '      "registry.terraform.io/hashicorp/aws3tooling",' \
      '      "registry.opentofu.org/hashicorp/aws3tooling",' \
      '    ]' \
      '  }' \
      '}' > /etc/iac/cli.tfrc

# Default shell
SHELL ["/bin/bash", "-c"]

# Verify installation
RUN terraform --version && tofu --version && curl --version && git --version && aws --version && iac-generator --version

CMD [ "bash" ]

