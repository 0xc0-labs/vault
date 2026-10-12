# vault

The OpenTofu configuration of the cluster's Vault: auth methods and roles,
policies, secret engines. Vault is deployed by `gitops` (`platform/vault`), so
this repo is downstream of it: `.github → infrastructure → gitops → vault →
offby1.cc and app-*`. The design is in the workspace's
`docs/design/secrets.md`.

The workspace's `CLAUDE.md` holds the rules every repo follows; these are
this repo's alone.

## Hard rules

- **No secret value ever goes into this repo, nor into Vault from here.** This
  repo configures Vault; secrets are written by whoever owns them. A policy
  for this repo's CI never grants access to stored secrets.
- **No Vault token is stored.** The CI logs in with GitHub's OIDC token (JWT).
  The `terraform` role binds `ref` and `environment`: only `main`, behind the
  operator's approval, writes.
- Nothing changes Vault from a laptop but the one bootstrap (README.md): the
  first run, by the operator, with the root token, over WARP. From then on,
  only the pipeline. Plans by hand go over WARP with a short-lived token.
- The root token is for that bootstrap and recovery only; it is kept with the
  unseal keys, outside Vault, never revoked.
