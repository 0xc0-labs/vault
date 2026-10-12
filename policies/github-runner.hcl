# The CI VMs' JIT step signs the runner App's JWT (README, Transit).
path "transit/sign/github-runner-app/sha2-256" {
  capabilities = ["update"]
}
