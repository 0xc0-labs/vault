# The CI VMs' JIT step (infrastructure, the github_runner role), logged in
# through AppRole: Vault signs the runner App's JWT with the App's key, which
# never leaves Transit. Signing only, with that key and that hash: no read,
# no export, no other key.
path "transit/sign/github-runner-app/sha2-256" {
  capabilities = ["update"]
}
