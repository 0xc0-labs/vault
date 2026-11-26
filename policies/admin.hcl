# The people's policy. Boundary: no sys/seal, sys/unseal, sys/rekey*,
# sys/generate-root* or sys/raw, and nothing on the root token: those stay the
# operator's (README, Recovery credentials).

path "platform/data/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list"]
}
path "platform/metadata/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list"]
}
path "platform/delete/*" {
  capabilities = ["update"]
}
path "platform/undelete/*" {
  capabilities = ["update"]
}
path "platform/destroy/*" {
  capabilities = ["update"]
}

path "apps/data/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list"]
}
path "apps/metadata/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list"]
}
path "apps/delete/*" {
  capabilities = ["update"]
}
path "apps/undelete/*" {
  capabilities = ["update"]
}
path "apps/destroy/*" {
  capabilities = ["update"]
}

path "ci/data/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list"]
}
path "ci/metadata/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list"]
}
path "ci/delete/*" {
  capabilities = ["update"]
}
path "ci/undelete/*" {
  capabilities = ["update"]
}
path "ci/destroy/*" {
  capabilities = ["update"]
}

# Read the auth methods, the mounts and the policies.
path "sys/auth" {
  capabilities = ["read"]
}
path "sys/mounts" {
  capabilities = ["read"]
}
path "sys/policies/acl" {
  capabilities = ["list"]
}

# Manage policies.
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage roles and read each method's configuration, never its secrets.
path "auth/+/role" {
  capabilities = ["list"]
}
path "auth/+/role/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "auth/+/config" {
  capabilities = ["read"]
}
