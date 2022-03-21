# Golang is required for terratest
# 1.15 ensure that the latest patch is always used but avoiding breaking changes when Golang as a minor upgrade
# Alpine is used by default for fast and ligthweight customization
ARG GO_VERSION=1.17.8
ARG PACKER_VERSION=1.8.0
ARG UPDATECLI_VERSION=v0.22.1
ARG JENKINS_AGENT_VERSION=4.13-1-alpine-jdk11

FROM golang:"${GO_VERSION}-alpine" AS gosource
FROM hashicorp/packer:"${PACKER_VERSION}" AS packersource
FROM updatecli/updatecli:"${UPDATECLI_VERSION}" AS updatecli
FROM jenkins/inbound-agent:"${JENKINS_AGENT_VERSION}"
USER root

RUN apk add --no-cache \
  # To allow easier CLI completion + running shell scripts with array support
  bash=~5 \
  # Used to download binaries (implies the package "ca-certificates" as a dependency)
  curl=~7 \
  # Required to ensure GNU conventions for tools like "date"
  coreutils=~9 \
  # Dev. Tooling packages (e.g. tools provided by this image installable through Alpine Linux Packages)
  git=~2\
  # jq for the json in /cleanup/aws.sh
  jq=~1.6 \
  # Dev workflow
  make=~4 \
  # Required for aws-cli
  py-pip=~20 \
  # Used to unarchive Terraform downloads
  unzip=~6 \
  # jq for the yaml in /cleanup/*.sh
  yq=~4

## bash need to be installed for this instruction to work as expected
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Golang (for terratest)
COPY --from=gosource /usr/local/go/ /usr/local/go/
ENV PATH /usr/local/go/bin/:$PATH

# Packer
COPY --from=packersource /bin/packer /usr/local/bin/

## Repeating the ARG to add it into the scope of this image
ARG GO_VERSION=1.17.8
ARG PACKER_VERSION=1.8.0
ARG UPDATECLI_VERSION=v0.22.1

## Install AWS Cli
ARG AWS_CLI_VERSION=1.22.77
RUN python3 -m pip install --no-cache-dir awscli=="${AWS_CLI_VERSION}"

### Install Terraform CLI
# Retrieve SHA256sum from https://releases.hashicorp.com/terraform/<TERRAFORM_VERSION>/terraform_<TERRAFORM_VERSION>_SHA256SUMS
# For instance: "
# TERRAFORM_VERSION=X.YY.Z
# curl -sSL https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION/terraform_$TERRAFORM_VERSION_SHA256SUMS | grep linux_amd64
ARG TERRAFORM_VERSION=1.1.7
RUN curl --silent --show-error --location --output /tmp/terraform.zip \
    "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
  && unzip /tmp/terraform.zip -d /usr/local/bin \
  && rm -f /tmp/terraform.zip \
  && terraform --version | grep "${TERRAFORM_VERSION}"

### Install tfsec CLI
ARG TFSEC_VERSION=1.11.0
RUN curl --silent --show-error --location --output /tmp/tfsec \
    "https://github.com/tfsec/tfsec/releases/download/v${TFSEC_VERSION}/tfsec-linux-amd64" \
  && chmod a+x /tmp/tfsec \
  && mv /tmp/tfsec /usr/local/bin/tfsec \
  && tfsec --version | grep "${TFSEC_VERSION}"

### Install golangcilint CLI
ARG GOLANGCILINT_VERSION=1.45.0
RUN curl --silent --show-error --location --fail \
  https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \
  | sh -s -- -b "/usr/local/bin" "v${GOLANGCILINT_VERSION}"

### Install updatecli
COPY --from=updatecli /usr/local/bin/updatecli /usr/local/bin/updatecli

## Install Azure Cli
ARG AZ_CLI_VERSION=2.34.1
# hadolint ignore=DL3013,DL3018
RUN apk add --no-cache --virtual .az-build-deps gcc musl-dev python3-dev libffi-dev openssl-dev cargo make \
    && apk add --no-cache py3-pynacl py3-cryptography \
    && python3 -m pip install --no-cache-dir azure-cli=="${AZ_CLI_VERSION}" \
    && apk del .az-build-deps

USER jenkins

## As per https://docs.docker.com/engine/reference/builder/#scope, ARG need to be repeated for each scope
ARG JENKINS_AGENT_VERSION=4.13-1-alpine-jdk11

LABEL io.jenkins-infra.tools="golang,terraform,tfsec,packer,golangci-lint,aws-cli,yq,updatecli,jenkins-agent,az-cli"
LABEL io.jenkins-infra.tools.terraform.version="${TERRAFORM_VERSION}"
LABEL io.jenkins-infra.tools.golang.version="${GO_VERSION}"
LABEL io.jenkins-infra.tools.tfsec.version="${TFSEC_VERSION}"
LABEL io.jenkins-infra.tools.packer.version="${PACKER_VERSION}"
LABEL io.jenkins-infra.tools.golangci-lint.version="${GOLANGCILINT_VERSION}"
LABEL io.jenkins-infra.tools.aws-cli.version="${AWS_CLI_VERSION}"
LABEL io.jenkins-infra.tools.updatecli.version="${UPDATECLI_VERSION}"
LABEL io.jenkins-infra.tools.jenkins-agent.version="${JENKINS_AGENT_VERSION}"
LABEL io.jenkins-infra.tools.az-cli.version="${AZ_CLI_VERSION}"


ENTRYPOINT ["/usr/local/bin/jenkins-agent"]
