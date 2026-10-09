path "platform/data/postgres/*" {
  capabilities = ["read"]
}

# Each application's database password, by name: the databases Job creates
# the role with it.
path "apps/data/payload/database" {
  capabilities = ["read"]
}
