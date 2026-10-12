path "ci/data/infrastructure/*" {
  capabilities = ["read"]
}

path "ci/data/shared/rustfs" {
  capabilities = ["read"]
}

path "ci/data/shared/cloudflare" {
  capabilities = ["read"]
}

# Across a boundary: ArgoCD's admin bcrypt, which Ansible writes into the
# cluster (the argocd role).
path "platform/data/argocd/admin" {
  capabilities = ["read"]
}
