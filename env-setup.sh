#!/bin/sh

## Source this file to set these environment variables

## See also https://developer.hashicorp.com/vault/docs/platform/k8s/helm/examples/standalone-tls

# TMPDIR for working files.
export TMPDIR=/tmp

# V_NAMESPACE is the Kubernetes namespace where the Vault service is running.
# This is referenced by the Vault config.
export V_NAMESPACE=hashicorp

# V_SERVICE is the name of the Vault service in Kubernetes. This is needed for
# the Vault FQDN along with the namespace.
export V_SERVICE=vault

# V_SECRET_NAME is the secret to create in the Kubernetes secrets store. This is
# referenced by the Vault config.
export V_SECRET_NAME=vault-server-tls

# V_CSR_NAME is the name of our Vault certificate signing request as seen by
# Kubernetes.
export V_CSR_NAME=vault-csr

# REC_CSR_NAME is the name of our Redis Enterprise Cluster (REC) certificate
# signing request as seen by Kubernetes.
export REC_CSR_NAME=rec-csr

# Filenames of Vault private key, Vault certificate, REC Proxy private key, REC
# Proxy certificate, and CA certificate (in this case the Kubernetes root CA), respectively.
export V_TLSKEY=vault-key.pem
export V_TLSCERT=vault-cert.pem

export PROXY_TLSKEY=rec-key.pem
export PROXY_TLSCERT=rec-cert.pem

export CA_CERT=ca-cert.pem

# REC_NAMESPACE is the Kubernetes namespace where the REC is running
export REC_NAMESPACE=redis

# REC_NAME is the name of the Redis Enterprise Cluster (REC)
export REC_NAME=rec-simple

# REDB_NAME is the name fo the Redis Enterprise Database (REDB)
export REDB_NAME=redb-simple

# REC_VAULT_ROLE is the name of the Kubernetes Vault role used by the REC
export REC_VAULT_ROLE=redis-enterprise-rec-${REC_NAMESPACE}

# V_SECRET_PREFIX is used as the Vault policy name as well as a path component
# for secrets stored in Vault. The REC_NAMESPACE is added to create a unique
# string when there are multiple RE clusters created. Each RE operator and
# cluster must be in its own namespace
export V_SECRET_PREFIX=redisenterprise-${REC_NAMESPACE}
