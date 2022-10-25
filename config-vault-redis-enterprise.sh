#!/bin/sh

## From https://github.com/RedisLabs/redis-enterprise-k8s-docs/tree/master/vault#deploying-the-operator
vault policy write redisenterprise - <<EOF
path "secret/data/redisenterprise/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/redisenterprise/*" {
  capabilities = ["list"]
}
EOF

vault write auth/kubernetes/role/"redis-enterprise-operator" \
        bound_service_account_names="redis-enterprise-operator"  \
        bound_service_account_namespaces=redis-enterprise \
        policies=redisenterprise \
        ttl=24h

## https://stackoverflow.com/questions/54312213/hashicorp-vault-cli-return-403-when-trying-to-use-kv
vault secrets enable -path=secret/ kv-v2