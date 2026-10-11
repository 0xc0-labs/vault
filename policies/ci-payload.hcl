path "ci/data/payload/*" {
  capabilities = ["read"]
}

# The promoter App's IDs: its JWT's issuer, and the installation on gitops
# that a token is asked for.
path "ci/data/shared/github-promoter-app" {
  capabilities = ["read"]
}

# The rc and release jobs sign the promoter App's JWT with its key, which
# never leaves Transit. Signing only, with that key and that hash: no read,
# no export, no other key.
path "transit/sign/github-promoter-app/sha2-256" {
  capabilities = ["update"]
}
