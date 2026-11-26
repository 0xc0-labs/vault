# oidc-auth

Vault's OIDC auth method, for people, against Cloudflare Access's OIDC
application for Vault. A person logs in through the UI ("Sign in with OIDC
Provider") or `vault login -no-print -method=oidc`, which opens the browser.

- Cloudflare decides who gets in: its Access application admits only the
  team and the operator's emails. The roles bind the client ID as audience and
  nothing more, so a role gives its policies to every login Cloudflare lets
  through.
- `roles` maps a role's name to its policies and allowed redirect URIs. The
  user claim is `email`.
- The token lives `token_ttl` seconds and renews up to `token_max_ttl`.
- The client ID and secret are the operator's, in Vault at
  `platform/vault/oidc`; the root passes them as variables.

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
| [vault_jwt_auth_backend.main](https://registry.terraform.io/providers/hashicorp/vault/5.12.0/docs/resources/jwt_auth_backend) | resource |
| [vault_jwt_auth_backend_role.main](https://registry.terraform.io/providers/hashicorp/vault/5.12.0/docs/resources/jwt_auth_backend_role) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_client_id"></a> [client\_id](#input\_client\_id) | The OIDC application's client ID, which is also the audience of its tokens. | `string` | n/a | yes |
| <a name="input_client_secret"></a> [client\_secret](#input\_client\_secret) | The OIDC application's client secret. | `string` | n/a | yes |
| <a name="input_default_role"></a> [default\_role](#input\_default\_role) | The role a login uses when it names none. | `string` | n/a | yes |
| <a name="input_discovery_url"></a> [discovery\_url](#input\_discovery\_url) | The OIDC issuer: Vault reads its discovery document and keys from here. | `string` | n/a | yes |
| <a name="input_path"></a> [path](#input\_path) | Mount path of the auth method. | `string` | `"oidc"` | no |
| <a name="input_roles"></a> [roles](#input\_roles) | Roles by name: the policies a login gets and the redirect URIs it may use. | <pre>map(object({<br/>    policies              = list(string)<br/>    allowed_redirect_uris = list(string)<br/>  }))</pre> | n/a | yes |
| <a name="input_token_max_ttl"></a> [token\_max\_ttl](#input\_token\_max\_ttl) | Longest a login's token can be renewed to, in seconds. | `number` | `86400` | no |
| <a name="input_token_ttl"></a> [token\_ttl](#input\_token\_ttl) | Lifetime of a login's token, in seconds. | `number` | `28800` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_path"></a> [path](#output\_path) | Mount path of the auth method. |
<!-- END_TF_DOCS -->