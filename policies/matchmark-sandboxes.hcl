# The sandboxes run code a coding agent writes, so their namespace is granted
# two paths by name and holds none of its own.

# Belongs to Matchmark (apps/matchmark) and is not written twice.
path "apps/data/matchmark/claude-subscription" {
  capabilities = ["read"]
}

# A sandbox's init container copies the factory's runner from a private image
# of ghcr.io/0xc0-labs. It can only read packages, as for the apps role.
path "apps/data/shared/ghcr-pull" {
  capabilities = ["read"]
}
