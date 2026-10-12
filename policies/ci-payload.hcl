path "ci/data/payload/*" {
  capabilities = ["read"]
}

path "ci/data/shared/github-promoter-app" {
  capabilities = ["read"]
}

# The rc and release jobs sign the promoter App's JWT (README, Transit).
path "transit/sign/github-promoter-app/sha2-256" {
  capabilities = ["update"]
}
