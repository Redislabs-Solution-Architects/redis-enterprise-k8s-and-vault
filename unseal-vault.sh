#!/bin/sh

kubectl exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json >${TMPDIR}/cluster-keys.json

VAULT_UNSEAL_KEY=$(cat ${TMPDIR}/cluster-keys.json | jq -r ".unseal_keys_b64[]")
kubectl exec -n vault vault-0 -- vault operator unseal ${VAULT_UNSEAL_KEY}

ROOT_TOKEN=$(cat ${TMPDIR}/cluster-keys.json | jq -r ".root_token")
kubectl exec -n vault vault-0 -- vault login ${ROOT_TOKEN}