# Start from a lightweight official base
FROM debian:bullseye-slim

# Build arguments
ARG IAC_GENERATOR_VERSION
ARG TARGETARCH

# Versions
ENV TERRAFORM_VERSION=1.5.7
ENV IAC_GENERATOR_VERSION=${IAC_GENERATOR_VERSION}

# Install utilities and Terraform
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
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
    && pip3 install --no-cache-dir boto3 google-cloud-secret-manager awscli pyyaml \
    \
    # Install Terraform
    && curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    -o terraform.zip \
    && unzip terraform.zip \
    && mv terraform /usr/local/bin/ \
    && rm terraform.zip \
    \
    # Install iac-generator
    && ARCH=${TARGETARCH:-amd64} \
    && echo "Downloading iac-generator ${IAC_GENERATOR_VERSION} for linux_${ARCH}" \
    && curl -fsSL https://github.com/Facets-cloud/iac-generator-releases/releases/download/${IAC_GENERATOR_VERSION}/iac-generator_${IAC_GENERATOR_VERSION#v}_linux_${ARCH}.tar.gz \
    -o iac-generator.tar.gz \
    && tar -xzf iac-generator.tar.gz \
    && mv iac-generator /usr/local/bin/ \
    && chmod +x /usr/local/bin/iac-generator \
    && rm iac-generator.tar.gz

# Spoofed aws3tooling provider for legacy capillary-cloud-tf envs.
# State in those envs has resources bound to registry.terraform.io/hashicorp/aws3tooling
# (the old Python IaC generator emitted `provider "aws3tooling" {}` without
# required_providers, synthesizing that source path). The public registry has no
# such provider, so we place the real hashicorp/aws 3.74.0 binary under the
# aws3tooling path and let terraform's implicit filesystem-mirror discovery
# resolve it. No .terraformrc or env vars required — terraform's default
# provider_installation checks /usr/local/share/terraform/plugins.
ARG TOOLING_AWS_VERSION=3.74.0

RUN set -eux; \
    DIR="/usr/local/share/terraform/plugins/registry.terraform.io/hashicorp/aws3tooling/${TOOLING_AWS_VERSION}/linux_amd64"; \
    mkdir -p "$DIR"; \
    curl -fsSL "https://releases.hashicorp.com/terraform-provider-aws/${TOOLING_AWS_VERSION}/terraform-provider-aws_${TOOLING_AWS_VERSION}_linux_amd64.zip" -o /tmp/aws.zip; \
    unzip -p /tmp/aws.zip "terraform-provider-aws*" > "${DIR}/terraform-provider-aws3tooling_v${TOOLING_AWS_VERSION}"; \
    chmod 0755 "${DIR}/terraform-provider-aws3tooling_v${TOOLING_AWS_VERSION}"; \
    rm /tmp/aws.zip

# Default shell
SHELL ["/bin/bash", "-c"]

# Verify installation
RUN terraform --version && curl --version && git --version && aws --version && iac-generator --version

CMD [ "bash" ]

