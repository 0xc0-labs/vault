# The sandboxes run code a coding agent writes, so their namespace is granted
# one path by name and holds none of its own: the Claude subscription's token,
# which belongs to Matchmark (apps/matchmark) and is not written twice.
path "apps/data/matchmark/claude-subscription" {
  capabilities = ["read"]
}
