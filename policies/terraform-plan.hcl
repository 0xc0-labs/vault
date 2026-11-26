path "sys/auth" {
  capabilities = ["read"]
}
path "sys/auth/*" {
  capabilities = ["read"]
}
path "auth/jwt/*" {
  capabilities = ["read", "list"]
}
path "auth/kubernetes/*" {
  capabilities = ["read", "list"]
}
path "auth/github/*" {
  capabilities = ["read", "list"]
}
# Vault does not return the client secret from the method's configuration.
path "auth/oidc/*" {
  capabilities = ["read", "list"]
}
# A role ID is not secret. Its secret IDs stay out of reach: no list of their
# accessors, and generating or looking one up takes update.
path "auth/approle/role/+" {
  capabilities = ["read"]
}
path "auth/approle/role/+/role-id" {
  capabilities = ["read"]
}

path "sys/mounts" {
  capabilities = ["read"]
}
path "sys/mounts/*" {
  capabilities = ["read"]
}

path "sys/policies/acl" {
  capabilities = ["list"]
}
path "sys/policies/acl/*" {
  capabilities = ["read", "list"]
}

# The provider reads a policy through the older sys/policy endpoint.
path "sys/policy" {
  capabilities = ["read", "list"]
}
path "sys/policy/*" {
  capabilities = ["read", "list"]
}

# This repo's OpenTofu state: the only secret it reads.
path "ci/data/shared/rustfs" {
  capabilities = ["read"]
}

# The plan reads the oidc auth method's client ID and secret, as the apply does
# (terraform.hcl).
path "platform/data/vault/oidc" {
  capabilities = ["read"]
}
