# No ci/data/offby1-cc/* (README, How CI gets in).

path "ci/data/shared/github-promoter-app" {
  capabilities = ["read"]
}

# The release job signs the promoter App's JWT (README, Transit).
path "transit/sign/github-promoter-app/sha2-256" {
  capabilities = ["update"]
}
