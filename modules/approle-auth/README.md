# approle-auth

Vault's AppRole auth method, for a machine outside the cluster and outside CI
that has neither a service account nor an OIDC token to log in with: today,
the CI VMs' JIT step (infrastructure, the `github_runner` role).

- The role ID is the role's name, fixed: not a secret, so it goes in the
  machine's configuration.
- The secret ID is the secret. The operator writes it by hand into `ci/` and
  Ansible puts it on the machine, root-only (the repo README, AppRole). It
  never expires on its own; it is revoked in Vault.
- A login gets a batch token for `token_ttl` seconds, never renewed.

The secret ID is not bound to the machine's address: Vault sees the
connection from Traefik, not from the machine. Binding it needs PROXY protocol
through HAProxy and Traefik first.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.12 |
| <a name="requirement_vault"></a> [vault](#requirement\_vault) | 5.12.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_vault"></a> [vault](#provider\_vault) | 5.12.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [vault_approle_auth_backend_role.main](https://registry.terraform.io/providers/hashicorp/vault/5.12.0/docs/resources/approle_auth_backend_role) | resource |
| [vault_auth_backend.main](https://registry.terraform.io/providers/hashicorp/vault/5.12.0/docs/resources/auth_backend) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_path"></a> [path](#input\_path) | Mount path of the auth method. | `string` | `"approle"` | no |
| <a name="input_roles"></a> [roles](#input\_roles) | Roles by name, which is also their role ID: the policies a login gets, and its token's TTL in seconds. | <pre>map(object({<br/>    policies  = list(string)<br/>    token_ttl = optional(number, 60)<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_path"></a> [path](#output\_path) | Mount path of the auth method. |
<!-- END_TF_DOCS -->
