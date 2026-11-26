# github-auth

Vault's GitHub auth method, for people. A member logs in with a personal
access token (`vault login -no-print -method=github`); Vault asks GitHub which
organization and teams the token's owner belongs to, and grants the policies
mapped to those teams.

- Only members of `organization` log in. The token needs the `read:org` scope.
- `teams` maps a team's slug to its policies. A team not listed grants nothing.
- The token lives `token_ttl` seconds and renews up to `token_max_ttl`.

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
| [vault_github_auth_backend.main](https://registry.terraform.io/providers/hashicorp/vault/5.12.0/docs/resources/github_auth_backend) | resource |
| [vault_github_team.main](https://registry.terraform.io/providers/hashicorp/vault/5.12.0/docs/resources/github_team) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_organization"></a> [organization](#input\_organization) | The GitHub organization whose members may log in. | `string` | n/a | yes |
| <a name="input_path"></a> [path](#input\_path) | Mount path of the auth method. | `string` | `"github"` | no |
| <a name="input_teams"></a> [teams](#input\_teams) | Policies by team slug: a member of the team gets them. | `map(list(string))` | `{}` | no |
| <a name="input_token_max_ttl"></a> [token\_max\_ttl](#input\_token\_max\_ttl) | Longest a login's token can be renewed to, in seconds. | `number` | `86400` | no |
| <a name="input_token_ttl"></a> [token\_ttl](#input\_token\_ttl) | Lifetime of a login's token, in seconds. | `number` | `28800` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_path"></a> [path](#output\_path) | Mount path of the auth method. |
<!-- END_TF_DOCS -->
