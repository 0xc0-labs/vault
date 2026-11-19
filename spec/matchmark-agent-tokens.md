# Matchmark agent tokens: a Transit key that never leaves Vault

Issue: 0xc0-labs/vault#91 (parent 0xc0-labs/workspace#252).

## Spec

Vault holds the `ed25519` key that signs Matchmark's agent tokens, generated
inside Vault and never exportable. Matchmark's API, and nothing else, signs
with it and reads its public half.

- `transit/keys/matchmark-agent-tokens`: `ed25519`, `exportable = false`,
  `deletion_allowed = false`, created by OpenTofu through the `transit`
  module. The module declares keys Vault generates, never keys someone else
  issued (those stay imported by the operator).
- `policies/matchmark-api.hcl`: `update` on
  `transit/sign/matchmark-agent-tokens`, `read` on
  `transit/keys/matchmark-agent-tokens`, nothing else.
- `kubernetes_roles."matchmark-api"`: namespace `matchmark`, service account
  `api`, policy `matchmark-api`.
- README, Transit: the key listed (type, used by, policy); the section no
  longer says OpenTofu creates the engine only.

### Not in scope

Rotating the key, any other Transit key, the API's KV secrets.

## Plan

1. `modules/transit`: a `keys` input (map of name to type) and a
   `vault_transit_secret_backend_key` per entry, `exportable = false`,
   `deletion_allowed = false`, `prevent_destroy`.
2. `environments/prod`: pass `transit_keys`; the root's variable and tfvars.
3. The policy and the Kubernetes role.
4. The pipeline's own policies. The `terraform` role has no path under
   `transit/keys/`, so applying would answer 403, and `terraform-plan` could
   not refresh the key in the next PR's plan. Both get a rule scoped to
   `transit/keys/*`. This is the one change besides the key, the policy and
   the role, and it is applied first: the transit module depends on the
   policies.
5. README and module README (terraform-docs regenerated).
6. State: the provider stores the key's `keys` (public keys per version),
   `latest_version`, `min_*`, `type`, and flags. A key that is not exportable
   has no private material for Vault to return; the PR confirms this against
   the provider's schema and the plan.

## Tasks

- [ ] transit module: keys
- [ ] root wiring and tfvars
- [ ] `matchmark-api` policy and role
- [ ] `terraform` and `terraform-plan` policies for `transit/keys/*`
- [ ] README and module docs
- [ ] `tofu validate`, `fmt`, plan evidence in the PR
