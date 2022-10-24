# redis-enterprise-and-vault

https://cogarius.medium.com/a-vault-for-all-your-secrets-full-tls-on-kubernetes-with-kv-v2-c0ecd42853e1

https://developer.hashicorp.com/vault/docs/platform/k8s/helm/examples/standalone-tls

Set up environment

Create Vault private key
``openssl genrsa -out ${TMPDIR}/vault-key.pem 2048``

## Sign Certificate Signing Request

XXX capture this and envsubst in gist

```sh
eval "echo \"$(<./csr-template.conf)\"" 2>/dev/null >${TMPDIR}/csr.conf

openssl req -new -key ${TMPDIR}/vault-key.pem \
    -subj "/O=system:nodes/CN=system:node:${VAULT_SERVICE}.${VAULT_NAMESPACE}.svc" \
    -out ${TMPDIR}/server.csr \
    -config ${TMPDIR}/csr.conf
```

## Request Certificate

```sh
eval "echo \"$(<./csr-resource-template.yaml)\"" 2>/dev/null >${TMPDIR}/csr.yaml

kubectl create -f ${TMPDIR}/csr.yaml
```

## Approve Certificate Request

`kubectl certificate approve ${CSR_NAME}`

## Store the Vault private key, the Vault certificate, and Kubernetes CA certificate in Secrets

XXX Is Vault hardcoded to look for vault.key, vault.crt, and vault.ca?

```sh
kubectl get csr ${CSR_NAME} -o jsonpath='{.status.certificate}' | base64 -d >${TMPDIR}/vault-cert.pem
kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d >${TMPDIR}/ca-cert.pem
kubectl create namespace ${VAULT_NAMESPACE}
kubectl create secret generic ${SECRET_NAME} \
    --namespace ${VAULT_NAMESPACE} \
    --from-file=vault.key=${TMPDIR}/vault-key.pem \
    --from-file=vault.crt=${TMPDIR}/vault-cert.pem \
    --from-file=vault.ca=${TMPDIR}/ca-cert.pem
```

## Add Vault to Kubernetes Cluster

`helm install -n vault --values ./vault-config.yaml vault hashicorp/vault`

## Unseal the Vault

`./unseal-vault.sh`

## Configure Vault for Redis Enterprise

cat ./config-vault.sh | kubectl exec -n vault -it vault-0 -- sh

##

```sh
eval "echo \"$(<./operator-config-template.yaml)\"" 2>/dev/null >${TMPDIR}/operator-config.yaml

kubectl create -f ${TMPDIR}/operator-config.yaml
```