path "platform/data/mariadb/*" {
  capabilities = ["read"]
}

# Each application's database password, by name: the databases Job creates
# the user with it.
path "apps/data/mautic-artistlabco-com/database" {
  capabilities = ["read"]
}
