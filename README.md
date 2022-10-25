# Redis Enterprise and Vault

https://cogarius.medium.com/a-vault-for-all-your-secrets-full-tls-on-kubernetes-with-kv-v2-c0ecd42853e1

https://developer.hashicorp.com/vault/docs/platform/k8s/helm/examples/standalone-tls

## Set up Environment

```sh
source ./env-setup.sh
```

## Create Vault Private Key

```sh
openssl genrsa -out ${TMPDIR}/${V_TLSKEY} 2048
```

## Sign Certificate Signing Request

XXX capture this and envsubst in gist

```sh
envsubst <./csr-template.conf >${TMPDIR}/csr.conf

openssl req -new -key ${TMPDIR}/${V_TLSKEY} \
    -subj "/O=system:nodes/CN=system:node:${V_SERVICE}.${V_NAMESPACE}.svc" \
    -out ${TMPDIR}/server.csr \
    -config ${TMPDIR}/csr.conf
```

## Request Certificate

```sh
export SERVER_CSR="$(cat ${TMPDIR}/server.csr | base64 | tr -d '\r\n')"
envsubst <./csr-resource-template.yaml >${TMPDIR}/csr.yaml

kubectl create -f ${TMPDIR}/csr.yaml
```

## Approve Certificate Request

```sh
kubectl certificate approve ${V_CSR_NAME}
```

## Store the Vault private key, the Vault certificate, and Kubernetes CA certificate in Secrets

```sh
kubectl get csr ${V_CSR_NAME} -o jsonpath='{.status.certificate}' | base64 -d >${TMPDIR}/${V_TLSCERT}
kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d >${TMPDIR}/${CA_CERT}
kubectl create namespace ${V_NAMESPACE}
kubectl create secret generic ${V_SECRET_NAME} \
    --namespace ${V_NAMESPACE} \
    --from-file=${V_TLSKEY}=${TMPDIR}/${V_TLSKEY} \
    --from-file=${V_TLSCERT}=${TMPDIR}/${V_TLSCERT} \
    --from-file=${CA_CERT}=${TMPDIR}/${CA_CERT}
```

## Add Vault to Kubernetes Cluster

```sh
envsubst <./vault-config-template.yaml >${TMPDIR}/vault-config.yaml

helm install -n vault --values ${TMPDIR}/vault-config.yaml vault hashicorp/vault
```

## Unseal the Vault

```sh
kubectl exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json >"${TMPDIR}"/cluster-keys.json

kubectl exec -n vault vault-0 -- vault operator unseal "$(jq -r ".unseal_keys_b64[]" <"${TMPDIR}"/cluster-keys.json)"

kubectl exec -n vault vault-0 -- vault login "$(jq -r ".root_token" <"${TMPDIR}"/cluster-keys.json)"
```

## Configure Vault for Redis Enterprise

cat ./config-vault.sh | kubectl exec -n vault -it vault-0 -- sh

##

```sh
eval "echo \"$(<./operator-config-template.yaml)\"" 2>/dev/null >${TMPDIR}/operator-config.yaml

kubectl create -f ${TMPDIR}/operator-config.yaml
```