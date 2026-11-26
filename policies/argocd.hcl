path "platform/data/argocd/github-oauth" {
  capabilities = ["read"]
}

# Argo CD's sign-in through Cloudflare Access (OIDC).
path "platform/data/argocd/oidc" {
  capabilities = ["read"]
}
