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
    awscli \
    ca-certificates \
    bash-completion \
    && rm -rf /var/lib/apt/lists/* \
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

# Default shell
SHELL ["/bin/bash", "-c"]

# Verify installation
RUN terraform --version && curl --version && git --version && aws --version && iac-generator --version

CMD [ "bash" ]

