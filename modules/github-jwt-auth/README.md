# github-jwt-auth

Vault's JWT auth method for GitHub Actions. A job logs in with the OIDC token
GitHub issues it: `hashicorp/vault-action` with `method: jwt`, asking GitHub
for the `audience` here. Vault checks the token against a role:

- `bound_claims` must match, exactly or as globs (`claims_type = "glob"`).
  Every role binds `repository`, never as a glob, and the module refuses one
  that does not, or any repository on GitHub could log in. Bind `ref` and
  `environment` too for a role that writes.
- `user_claim` is `job_workflow_ref`: one entity per calling workflow.
- The token lives `token_ttl` seconds and never renews past it.

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
| <a name="input_audience"></a> [audience](#input\_audience) | The aud claim a token must carry: what the workflow asks GitHub for (vault-action's jwtGithubAudience). | `string` | n/a | yes |
| <a name="input_issuer"></a> [issuer](#input\_issuer) | GitHub Actions' OIDC issuer: discovery URL and bound issuer. | `string` | `"https://token.actions.githubusercontent.com"` | no |
| <a name="input_path"></a> [path](#input\_path) | Mount path of the auth method. | `string` | `"jwt"` | no |
| <a name="input_roles"></a> [roles](#input\_roles) | Roles by name: the claims a token must match exactly, the policies it gets, and its TTL in seconds. | <pre>map(object({<br/>    bound_claims = map(string)<br/>    # "string": exact match; "glob": * matches, in every claim of the role.<br/>    claims_type = optional(string, "string")<br/>    policies    = list(string)<br/>    token_ttl   = optional(number, 1200)<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_path"></a> [path](#output\_path) | Mount path of the auth method. |
<!-- END_TF_DOCS -->
