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
