#!/bin/sh

## Source this file to set these environment variables

## From https://developer.hashicorp.com/vault/docs/platform/k8s/helm/examples/standalone-tls

# TMPDIR for working files.
export TMPDIR=/tmp

# V_NAMESPACE where the Vault service is running. This is referenced by the Vault config.
export V_NAMESPACE=hashicorp

# V_SERVICE is the name of the Vault service in Kubernetes. This is needed for the Vault FQDN along with the namespace.
export V_SERVICE=vault

# V_SECRET_NAME is the secret to create in the Kubernetes secrets store. This is referenced by the Vault config.
export V_SECRET_NAME=vault-server-tls

# V_CSR_NAME will be the name of our certificate signing request as seen by Kubernetes.
export V_CSR_NAME=vault-csr

# Filenames of Vault private key, Vault certificate, and CA certificate, respectively.
export V_TLSKEY=vault-key.pem
export V_TLSCERT=vault-cert.pem
export CA_CERT=ca-cert.pem

export RE_NAMESPACE=redis
export REC_NAME=redis-enterise
