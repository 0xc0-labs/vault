# transit

A Transit secrets engine, with `prevent_destroy`: recreating the mount
deletes every key in it. Vault signs and encrypts with its keys, which never
leave it.

The module creates the engine, not the keys. A key someone else issued (a
GitHub App's private key) is imported by the operator, non-exportable, with
`vault transit import` (the repo README, Transit); OpenTofu never sees it.

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
| [vault_mount.main](https://registry.terraform.io/providers/hashicorp/vault/5.12.0/docs/resources/mount) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_description"></a> [description](#input\_description) | What the engine's keys are for. | `string` | n/a | yes |
| <a name="input_path"></a> [path](#input\_path) | Mount path of the engine. | `string` | `"transit"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_path"></a> [path](#output\_path) | Mount path of the engine. |
<!-- END_TF_DOCS -->
