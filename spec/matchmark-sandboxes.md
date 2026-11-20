# matchmark-sandboxes: the sandboxes' namespace reads one secret

Issue: 0xc0-labs/vault#95. Parent: 0xc0-labs/workspace#269.

## Spec

The namespace `matchmark-sandboxes`, where Matchmark's task sandboxes run
code a coding agent writes, can read one secret from Vault,
`apps/matchmark/claude-subscription`, and nothing else.

- It is a role of its own, not the `apps` role: that one admits any namespace
  labelled `vault.0xc0.cc/apps` and grants `apps/<namespace>/*`. This
  namespace is not labelled, on purpose: it holds no path of its own.
- The secret is not written a second time: one service, one path. The new
  namespace is granted it by name, with the reason in the policy.
- No secret value is written or moved here.

## Plan

1. `policies/matchmark-sandboxes.hcl`: `read` on
   `apps/data/matchmark/claude-subscription`, with the reason. The
   `policies/` directory is discovered by `environments/prod/main.tf`, so no
   wiring is needed.
2. `kubernetes_roles["matchmark-sandboxes"]` in
   `environments/prod/terraform.tfvars`: namespace `matchmark-sandboxes`,
   service account `vault-secrets`, policy `matchmark-sandboxes`.
3. `README.md`: the role and its one path under Secrets, and why the
   namespace is not labelled `vault.0xc0.cc/apps`.
4. Checks: `tofu fmt`, `tofu validate`, the repo's CI.

## Tasks

- [ ] Policy
- [ ] Role
- [ ] README
- [ ] Checks pass; the plan adds one policy and one role, nothing else
