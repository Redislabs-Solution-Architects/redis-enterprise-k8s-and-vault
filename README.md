# Redis Enterprise and Vault

This is the companion repo for my [technical blog](https://redis.com/blog/kubernetes-secret/) about Kubernetes Secrets and
why you really want to be using Vault to manage your secrets. What follows is
intended to be a recipe for a basic setup.

A complete guide to setting up Vault is outside the scope of this article. I found the [Vault tutorials](https://developer.hashicorp.com/vault/tutorials/kubernetes) to be excellent and recommend them for your followup homework. For our current purpose we only need a simple instance of Vault running in our Kubernetes cluster. I also relied on examples from HashiCorp for setting up [Vault with TLS](https://developer.hashicorp.com/vault/docs/platform/k8s/helm/examples/standalone-tls) to create my sandbox environment.

## Prerequists and Tools

* Kubernetes cluster with at least 3 nodes, 8GB RAM
* kubectl
* jq
* openssl
* base64

## Set up Environment

```sh
source ./env-setup.sh
```

## Create Private Keys for Vault and the Redis Enterprise (REC) Proxy

```sh
openssl genrsa -out ${TMPDIR}/${V_TLSKEY} 2048
openssl genrsa -out ${TMPDIR}/${PROXY_TLSKEY} 2048
```

## Sign Certificate Signing Requests for Vault and the REC Proxy

```sh
export SERVICE=${V_SERVICE}
export NAMESPACE=${V_NAMESPACE}
envsubst <./csr.template >${TMPDIR}/vault-csr.conf
openssl req -new -key ${TMPDIR}/${V_TLSKEY} \
    -subj "/CN=Vault" \
    -out ${TMPDIR}/vault-server.csr \
    -config ${TMPDIR}/vault-csr.conf
```

```sh
export SERVICE=${REC_NAME}
export NAMESPACE=${REC_NAMESPACE}
envsubst <./csr.template >${TMPDIR}/proxy-csr.conf
openssl req -new -key ${TMPDIR}/${PROXY_TLSKEY} \
    -subj "/CN=Redis Enterprise" \
    -out ${TMPDIR}/rec-server.csr \
    -config ${TMPDIR}/proxy-csr.conf
```

## Request and Approve the Certificates

```sh
export SERVER_CSR="$(cat ${TMPDIR}/vault-server.csr | base64 | tr -d '\r\n')"
export CSR_NAME=${V_CSR_NAME}
envsubst <./csr-resource.template >${TMPDIR}/vault-csr-resource.yaml
kubectl -n default create -f ${TMPDIR}/vault-csr-resource.yaml
kubectl -n default certificate approve ${CSR_NAME}
```

```sh
export SERVER_CSR="$(cat ${TMPDIR}/rec-server.csr | base64 | tr -d '\r\n')"
export CSR_NAME=${REC_CSR_NAME}
envsubst <./csr-resource.template >${TMPDIR}/rec-csr-resource.yaml
kubectl -n default create -f ${TMPDIR}/rec-csr-resource.yaml
kubectl -n default certificate approve ${CSR_NAME}
```

👉 Kubernetes will garbage collect a CSR after an hour.

```sh
kubectl get csr ${V_CSR_NAME} -o jsonpath='{.status.certificate}' | base64 -d >${TMPDIR}/${V_TLSCERT}
kubectl get csr ${REC_CSR_NAME} -o jsonpath='{.status.certificate}' | base64 -d >${TMPDIR}/${PROXY_TLSCERT}
```

## Store the Vault private key, the Vault certificate, and Kubernetes CA certificate in Secrets

```sh

kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d >${TMPDIR}/${CA_CERT}
kubectl create namespace ${V_NAMESPACE}
kubectl create secret generic ${V_SECRET_NAME} \
    --namespace ${V_NAMESPACE} \
    --from-file=${V_TLSKEY}=${TMPDIR}/${V_TLSKEY} \
    --from-file=${V_TLSCERT}=${TMPDIR}/${V_TLSCERT} \
    --from-file=${CA_CERT}=${TMPDIR}/${CA_CERT}
```

## Download the REC certificate

```sh
kubectl get csr ${REC_CSR_NAME} -o jsonpath='{.status.certificate}' | base64 -d >${TMPDIR}/${PROXY_TLSCERT}
```

## Create the Vault Service in our Kubernetes Cluster

```sh
envsubst <./vault-config.template >${TMPDIR}/vault-config.yaml
helm install -n ${V_NAMESPACE} --values ${TMPDIR}/vault-config.yaml vault hashicorp/vault
```

## Unseal the Vault

👉 You will want to wait for the Vault deployment to be ready

```sh
kubectl exec -n ${V_NAMESPACE} vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json >"${TMPDIR}"/vault-cluster-keys.json
kubectl exec -n ${V_NAMESPACE} vault-0 -- vault operator unseal "$(jq -r ".unseal_keys_b64[]" <"${TMPDIR}"/vault-cluster-keys.json)"
kubectl exec -n ${V_NAMESPACE} vault-0 -- vault login "$(jq -r ".root_token" <"${TMPDIR}"/vault-cluster-keys.json)"
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

## Create the Redis Enterprise Operator configuration for Vault via a ConfigMap

```sh
envsubst <./operator-environment-config.template >"${TMPDIR}"/operator-environment-config.yaml
kubectl create namespace ${REC_NAMESPACE}
kubectl create -n ${REC_NAMESPACE} -f "${TMPDIR}"/operator-environment-config.yaml
```

## Install the Redis Enterprise Operator

```sh
version=$(curl -s "https://api.github.com/repos/RedisLabs/redis-enterprise-k8s-docs/releases/latest" | jq -r '.name')
kubectl apply -n ${REC_NAMESPACE} -f https://raw.githubusercontent.com/RedisLabs/redis-enterprise-k8s-docs/v${version}/bundle.yaml
```

👉 Don't panic. The deployment will not complete until the Admission Controller
TLS identity has been added to Vault and the Admission Controller has read that
TLS identity. Of course for the Admission Controller to connect to Vault, it
must trust the TLS identity presented by Vault. The CA cert for Vault must
therefore also be shared with the Redis Enterprise Operator. By default, the
operator looks for a certificate in a secret named `vault-ca-cert`.

```sh
kubectl create secret generic vault-ca-cert --namespace $REC_NAMESPACE --from-file=vault.ca=${TMPDIR}/${CA_CERT}
kubectl exec -n ${REC_NAMESPACE} -it $(kubectl get pod -l name=redis-enterprise-operator -o jsonpath='{.items[0].metadata.name}') -c redis-enterprise-operator -- /usr/local/bin/generate-tls -infer | tail -4 >${TMPDIR}/admission-identity.json
kubectl cp ${TMPDIR}/admission-identity.json vault-0:/tmp -n ${V_NAMESPACE}
kubectl exec -n ${V_NAMESPACE} -it vault-0 -- vault kv put secret/${V_SECRET_PREFIX}/admission-tls @/tmp/admission-identity.json 
```

👉 Most likely the Redis Enterprise Operator pod is in a CrashLookBackOff at
this point while it was waiting for you. If you are impatient like me for all the
changes you made to be observed, delete the operator Pod and let the Deployment
create it again.

## Create the REC Admin Password

```sh
echo $(openssl rand -hex 8) >${TMPDIR}/REC-password
kubectl exec -n ${V_NAMESPACE} vault-0 -- vault kv put secret/$V_SECRET_PREFIX/${REC_NAME} username=demo@demo.com password="$(cat ${TMPDIR}/REC-password)"
kubectl exec -n ${V_NAMESPACE} vault-0 -- vault  write auth/kubernetes/role/${REC_VAULT_ROLE} \
       bound_service_account_names=${REC_NAME}  \
       bound_service_account_namespaces=${REC_NAMESPACE} \
       policies=${V_SECRET_PREFIX}
```

👉 The admin username is `demo@demo.com` and the password is in `${TMPDIR}/REC-password`

## Create the REC

```sh
envsubst <./rec.template >"${TMPDIR}"/rec.yaml
kubectl create -n ${RE_NAMESPACE} -f ${TMPDIR}/rec.yaml
```

👉 It will take a couple of minutes for the REC pods to be created.

## Confirm the Admin UI is Up

Forward localhost:8443 to the REC UI

```sh
kubectl port-forward -n ${REC_NAMESPACE} services/${REC_NAME}-ui 8443:8443
```

and then point your browser to [https://localhost:8443] using the admin username/password above.

👉 The TLS identity is autogenerated by the REC. We will override the TLS
identity used to secure database connections in a moment. You can then follow the same pattern for the REST API identity, CM (aka Admin UI) identity, Metrics Export identity, Syncer identity, in addition to the Proxy (aka REC) identity.

## Create the Redis Enterprise Database (REDB) Password

```sh
echo $(openssl rand -hex 8) >${TMPDIR}/REDB-password
kubectl exec -n ${V_NAMESPACE} vault-0 -- vault kv put secret/$V_SECRET_PREFIX/redb-redb-demo password=$(cat ${TMPDIR}/REDB-password)
```

## Create a Redis Enterprise Database (REDB)

```sh
kubectl create -f https://raw.githubusercontent.com/andresrinivasan/redis-enterprise-k8s-custom-resources/master/getting-started/redb-tls.yaml
```

## Confirm TLS and a Password is Required to Connect to the REDB

```sh
REDB_PORT=$(kubectl -n ${REC_NAMESPACE} get redb -o jsonpath='{..port}')
kubectl port-forward -n ${REC_NAMESPACE} services/${REDB-NAME} $REDB_PORT:$REDB_PORT
```

Now try to set the key `foo`:

```sh
redis-cli -h localhost -p ${REDB_PORT} set foo bar
```

You should now be seeing the error `(error) ERR unencrypted connection is prohibited`.

```sh
redis-cli -h localhost -p ${REDB_PORT} --tls --cacert ${TMPDIR}/${CA_CERT} set foo bar
```

You should now be seeing the error `(error) NOAUTH Authentication required`

```sh
redis-cli -h localhost -p ${REDB_PORT} --tls --cacert ${TMPDIR}/${CA_CERT} --pass $(cat /tmp/REDB-password) set foo bar
redis-cli -h localhost -p ${REDB_PORT} --tls --cacert ${TMPDIR}/${CA_CERT} --pass $(cat /tmp/REDB-password) get foo
```

And success!

## Configure the REC to use a Vault Managed TLS Identity

The REC will use a self generated TLS identity unless a Vault hosted identity is
configured. We already have the certificate and private key which needs to be added to Vault. 

```sh
jq --null-input --rawfile certificate ${TMPDIR}/${PROXY_TLSCERT} --rawfile key ${TMPDIR}/${PROXY_TLSKEY} '{"name": "proxy", "certificate": $certificate, "key": $key}' >${TMPDIR}/rec-identity.json
kubectl cp ${TMPDIR}/rec-identity.json vault-0:/tmp -n ${V_NAMESPACE}
kubectl exec -n ${V_NAMESPACE} -it vault-0 -- vault kv put secret/${V_SECRET_PREFIX}/proxy-tls @/tmp/rec-identity.json 
```

Then we patch the REC to use this identity.

```sh
kubectl patch -n ${RE_NAMESPACE} rec ${REC_NAME}  --type=merge --patch-file ./rec-patch.yaml
```

If you need to, set up the port forwarding again as above. Now verify the new identity is being used for the proxy identity.

```sh
openssl s_client -connect localhost:${REDB_PORT} 2>/dev/null | fgrep subject=CN
```

You should see `subject=CN = Redis Enterprise` which is what is specified in the
certficate we just uploaded. Now verify you can still connect to the database securely.

```sh
redis-cli -h localhost -p ${REDB_PORT} --tls --cacert ${TMPDIR}/${CA_CERT} --pass $(cat /tmp/REDB-password) get foo
```

## What Next?

You're just getting started...

* Replace the other TLS identities used by Redis Enterprise
* Configure ingress
* Upgrade Vault to a full HA configuration or HCP Vault

## Further Reading
[Get started with Redis Enterprise Software](https://docs.redis.com/latest/rs/installing-upgrading/get-started-redis-enterprise-software/)
[Deploy Redis Enterprise Software on Kubernetes](https://docs.redis.com/latest/kubernetes/deployment/quick-start/)
[Integrating the Redis Enterprise Operator with Hashicorp Vault](https://github.com/RedisLabs/redis-enterprise-k8s-docs/tree/master/vault)
[Redis Launchpad](https://launchpad.redis.com/)
