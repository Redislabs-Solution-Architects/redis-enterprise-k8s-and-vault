# Redis Enterprise and Vault

https://cogarius.medium.com/a-vault-for-all-your-secrets-full-tls-on-kubernetes-with-kv-v2-c0ecd42853e1

https://developer.hashicorp.com/vault/docs/platform/k8s/helm/examples/standalone-tls

## Prerequisets

* Kubernetes cluster with at least 3 nodes, 8GB RAM
* kubectl
* jq
* openssl
* base64

## Set up Environment

```sh
source ./env-setup.sh
```

## Create Vault Private Key

```sh
openssl genrsa -out ${TMPDIR}/${V_TLSKEY} 2048
```

## Sign Certificate Signing Request

```sh
envsubst <./csr.template >${TMPDIR}/csr.conf

openssl req -new -key ${TMPDIR}/${V_TLSKEY} \
    -subj "/O=system:nodes/CN=system:node:${V_SERVICE}.${V_NAMESPACE}.svc" \
    -out ${TMPDIR}/server.csr \
    -config ${TMPDIR}/csr.conf
```

## Request and Approve Certificate

```sh
export SERVER_CSR="$(cat ${TMPDIR}/server.csr | base64 | tr -d '\r\n')"
envsubst <./csr-resource.template >${TMPDIR}/csr-resource.yaml

kubectl create -f ${TMPDIR}/csr-resource.yaml
## Wait for request to be created
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
envsubst <./vault-config.template >${TMPDIR}/vault-config.yaml

helm install -n ${V_NAMESPACE} --values ${TMPDIR}/vault-config.yaml vault hashicorp/vault
```

## Unseal the Vault

```sh
kubectl exec -n ${V_NAMESPACE} vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json >"${TMPDIR}"/cluster-keys.json

kubectl exec -n ${V_NAMESPACE} vault-0 -- vault operator unseal "$(jq -r ".unseal_keys_b64[]" <"${TMPDIR}"/cluster-keys.json)"

kubectl exec -n ${V_NAMESPACE} vault-0 -- vault login "$(jq -r ".root_token" <"${TMPDIR}"/cluster-keys.json)"
```

## Configure Vault for Kubernetes Authentication

```sh
kubectl exec -n ${V_NAMESPACE} -i vault-0 -- sh <./config-vault-kubernetes.sh
```

## Configure Vault for Redis Enterprise

```sh
envsubst <./config-vault-redis-enterprise.template >${TMPDIR}/config-vault-redis-enterprise.sh

kubectl exec -n ${V_NAMESPACE} -i vault-0 -- sh <"${TMPDIR}"/config-vault-redis-enterprise.sh
```

## Configure Operator for Vault via a ConfigMap

```sh
envsubst <./operator-environment-config.template >"${TMPDIR}"/operator-environment-config.yaml

kubectl create namespace ${RE_NAMESPACE}

kubectl create -n ${RE_NAMESPACE} -f "${TMPDIR}"/operator-environment-config.yaml
```

## Install the Redis Enterprise Operator

```sh

version=$(curl -s "https://api.github.com/repos/RedisLabs/redis-enterprise-k8s-docs/releases/latest" | jq -r '.name')
kubectl apply -n ${RE_NAMESPACE} -f https://raw.githubusercontent.com/RedisLabs/redis-enterprise-k8s-docs/v${version}/bundle.yaml
```

<!-- ## Add the Admission Controller TLS Identity to Vault      SKIPPING THIS STEP RIGHT NOW

```sh
kubectl exec -n ${RE_NAMESPACE} -it $(kubectl get pod -l name=redis-enterprise-operator -o jsonpath='{.items[0].metadata.name}') -c redis-enterprise-operator -- /usr/local/bin/generate-tls -infer | tail -4 >${TMPDIR}/admission-identity.json

kubectl cp ${TMPDIR}/admission-identity.json vault-0:/tmp -n ${V_NAMESPACE}

kubectl exec -n ${V_NAMESPACE} -it vault-0 -- vault kv put secret/${V_SECRET_PREFIX}/admission-tls /tmp/admission-identity.json 
```

-->


kubectl create secret generic vault-ca-cert --namespace $RE_NAMESPACE --from-file=vault.ca=${TMPDIR}/${CA_CERT}

kubectl exec -n ${V_NAMESPACE} vault-0 -- vault kv put secret/$V_SECRET_PREFIX/$REC_NAME username=demo@demo.com password=$(openssl rand -hex 8)

kubectl exec -n ${V_NAMESPACE} vault-0 -- vault  write auth/kubernetes/role/redis-enterprise-rec-${RE_NAMESPACE} \
       bound_service_account_names=${REC_NAME}  \
       bound_service_account_namespaces=${RE_NAMESPACE} \
       policies=${V_SECRET_PREFIX}

