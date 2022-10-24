#!/bin/sh

## Source this file to set these environment variables

## From https://developer.hashicorp.com/vault/docs/platform/k8s/helm/examples/standalone-tls

# SERVICE is the name of the Vault service in Kubernetes.
# It does not have to match the actual running service, though it may help for consistency.
export VAULT_SERVICE=vault

# NAMESPACE where the Vault service is running.
export VAULT_NAMESPACE=vault

# SECRET_NAME to create in the Kubernetes secrets store.
export SECRET_NAME=vault-server-tls

# TMPDIR is a temporary working directory.
export TMPDIR=/tmp

# CSR_NAME will be the name of our certificate signing request as seen by Kubernetes.
export CSR_NAME=vault-csr
