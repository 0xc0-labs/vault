# The API signs agent tokens and publishes the key's public half as a JWKS
# (README, Transit).
path "transit/sign/matchmark-agent-tokens" {
  capabilities = ["update"]
}
path "transit/keys/matchmark-agent-tokens" {
  capabilities = ["read"]
}
