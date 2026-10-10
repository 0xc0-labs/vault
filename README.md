# vault

The configuration of the cluster's Vault, as OpenTofu: auth methods and their
roles, policies, secret engines. Vault itself is deployed by `gitops`
(`platform/vault`); this repo configures what runs.

```
environments/prod/   the root: only calls modules
modules/             github-jwt-auth, kubernetes-auth, approle-auth, policy, kv, transit
policies/            one ACL policy per file, named after it
scripts/             tofu (local runs, credentials from Vault)
```

State: `0xc0/vault/prod.tfstate` in RustFS, whose credentials come from
Vault itself (`ci/shared/rustfs`).

## Secrets: the standard

One KV v2 engine per trust boundary, never one for everything, so a policy
for one never reaches another:

| Engine | Holds | Read by |
|---|---|---|
| `platform/` | the cluster's shared services | Vault Secrets Operator, per namespace |
| `apps/` | the applications | Vault Secrets Operator, per namespace |
| `ci/` | what the pipelines use (Proxmox, Cloudflare, RustFS, the runners' AppRole secret ID) | each repo's CI jobs, over JWT |
| `ops/` | what only people use: UI logins, passwords in clear | the operator; **no machine has a policy on it** |

There is no dynamic engine (`pki/`, `database/`); one is added when something
needs it. Keys that must never leave Vault live in `transit/` (Transit,
below), not in a KV engine.

- **People or machines.** A secret a machine reads lives in `platform/`,
  `apps/` or `ci/`. One only a person uses lives in `ops/`, and no machine is
  ever granted it. When both need the same credential, each gets its own form:
  the machine the bcrypt or the htpasswd line (`platform/argocd/admin`,
  `platform/shared/ui-basic-auth`), the person the password (`ops/argocd/admin`,
  `ops/ui-basic-auth`). A secret a machine must read even though a person logs
  in with it is a machine's (`platform/openobserve/root`: OpenObserve reads it
  at its first start).
- **One service, one path.** A secret belongs to the service it is for, not
  to whoever reads it: ArgoCD's is `platform/argocd/admin`, even though
  infrastructure's CI writes it into the cluster. A reader across a boundary is
  granted it by name, with the reason in its policy (`ci-infrastructure.hcl`).
- **Paths:** `<engine>/<owner>/<name>`. The owner is the namespace, the repo
  under `ci/`, or the service under `ops/`, and it is what a policy scopes to.
  Everything is lowercase and kebab-case: `platform/grafana/admin`,
  `ci/infrastructure/proxmox`.
- **Keys inside a secret:** `snake_case`, so they map to a Kubernetes Secret
  as they are: `username`, `password`, `api_token`.
- **Metadata:** every secret carries `custom_metadata` `owner` and
  `rotated_at`.
- **Who reads:** a namespace's Kubernetes auth role reads only
  `<engine>/<namespace>/*`. A repo's JWT role reads only `ci/<repo>/*`. There
  is no global reader.
- **Applications:** one role, `apps`, for every namespace labelled
  `vault.0xc0.cc/apps: "true"`, and one templated policy
  (`policies/apps.hcl.tftpl`): each login reads `apps/<its own namespace>/*`,
  the namespace taken from its service account's token. Plus one shared path
  by name, `apps/shared/openobserve-rum`: OpenObserve's RUM client token, one
  per organization and public by design. A new application
  needs no change here, only the label on its namespace in `gitops`. Whoever
  can label a namespace there gives it its own `apps/` path, never another's.
- **Shared secrets: one secret, one path, never a copy.** A credential more
  than one consumer uses lives once, at `<engine>/shared/<name>`
  (`platform/shared/cloudflare`, `ci/shared/rustfs`), and each consumer's
  policy grants it by name, next to its own paths. Never `shared/*` whole:
  who shares what is written in the policies, and reviewed in their PRs.
  Rotating it is one write, and every consumer follows. The one copy across
  engines is Cloudflare's token, in `ci/shared` and `platform/shared`, written
  together.
- **Who writes:** whoever holds the secret, the operator or a rotation job.
  Never this repo: it defines engines, roles and policies, never values.

## Recovery credentials: outside Vault

What restoring Vault takes cannot live only in Vault. These are kept in the
operator's password manager and in an offline copy, never in Vault, the
cluster or a repo:

| Credential | Why outside |
|---|---|
| Vault's five unseal keys, and its root token | Vault cannot open itself |
| PBS: its `root`, and the Hetzner Storage Box it backs up to | the backups Vault is restored from |
| Hetzner Robot, and the Rescue system | the node's way back in |
| Proxmox `root@pam` | restoring the VMs, Vault's among them |
| RustFS admin | the OpenTofu state, before any pipeline runs |
| The Cloudflare and GitHub accounts, and their 2FA | WARP, the tunnels and the pipelines all depend on them |

The section below, "When the cluster or Vault is down", is the order to use
them in.

## Writing or rotating a secret

The operator writes, from the laptop over WARP, with a token that may. Nothing
a secret or a token holds ever reaches a screen, a shell history or a command
line:

- `vault login -no-print`: `vault login` alone prints the token it stores.
- The value on stdin, `key=-`, straight from where it is issued: a file
  downloaded from the provider, deleted right after, or `read -rs` for one shown
  on a web page. Never pasted into the command.
- `key=-` stores stdin exactly, a trailing newline included. A generated value
  (`openssl rand`, `pwgen`) ends in one: strip it with `tr -d '\n'`, or it
  becomes part of the secret (OpenObserve's first root password, 2026-10-01).
  `printf '%s'` adds none; a downloaded key file keeps its own, as it should.
- `kv patch` changes one key and keeps the others; `kv put` writes a new
  secret whole. Then `rotated_at`, so the next rotation knows how old it is.

```sh
export VAULT_ADDR=https://vault.int.0xc0.cc
mise exec -- vault login -no-print

# A key shown once on a web page (a new API token):
read -rs v && printf '%s' "$v" | mise exec -- vault kv patch -mount=ci infrastructure/proxmox api_token=- ; unset v
# A value generated here (a password): strip the trailing newline.
openssl rand -base64 24 | tr -d '\n' | mise exec -- vault kv patch -mount=platform openobserve/root password=-
# A key downloaded as a file (a GitHub App's private key):
mise exec -- vault kv patch -mount=ci github/org-app private_key=- < ~/Downloads/app.private-key.pem && rm ~/Downloads/app.private-key.pem

mise exec -- vault kv metadata put -mount=ci \
  -custom-metadata=owner=operator -custom-metadata=rotated_at="$(date +%F)" infrastructure/proxmox

rm -f ~/.vault-token
```

Every consumer follows on its own: the pipelines read Vault on every run, and
Vault Secrets Operator refreshes the cluster's Secrets within its refresh
interval. A credential that also lives with its provider (an API token, an
App key) is revoked there once the new one is in Vault and a run has used it.

## When the cluster or Vault is down

Every secret lives in Vault and nowhere else, so with Vault down no pipeline
runs (plan, apply, ansible, packer), nor do the local scripts. That is the
accepted risk (operator decision, 2026-10-01). Besides Vault, the only copy
of the secrets is PBS's backup of the RKE2 servers, whose Longhorn volumes
hold Vault's Raft data.

1. **Sealed only** (the pods run, `vault status` says `Sealed true`), after a
   restart: unseal each pod, as `gitops/platform/vault/README.md` says, "After
   every restart: unseal".
2. **The cluster is lost:** restore `vm-rke2-01`, `-02` and `-03` from PBS,
   all three from the same night, so Raft's members agree. Start them one at
   a time, and wait for each node Ready and Longhorn healthy (as
   `scripts/rolling-reboot` checks in infrastructure). Then unseal each pod.
3. **Check:**
   - `vault status`: `Sealed false`, HA mode `active` on one pod.
   - A CI login: re-run a PR's plan in any repo.
   - The cluster's Secrets: every `VaultStaticSecret` `Ready`.
4. Only then does anything else get fixed through the pipelines.

The unseal keys and the root token are in the operator's password manager and
offline, never in Vault, the cluster or a repo.

## How CI gets in

No Vault credential is stored anywhere. Each job logs in with the OIDC token
GitHub issues it (JWT auth, `hashicorp/vault-action`, in the reusable tofu
workflows in `0xc0-labs/.github`):

| Role | Who | Policy |
|---|---|---|
| `terraform-plan` | any ref of this repo, through `.github`'s plan workflow on `main`: a PR's plan | `terraform-plan`: reads its own configuration |
| `terraform` | `main`, through `.github`'s apply workflow on `main`, inside the `production` environment, after the operator's approval | `terraform`: manages the configuration |

The other repos' CI reads its secrets with one role per repo:

| Role | Who | Policy |
|---|---|---|
| `github` | `.github`, from any of its own reusable workflows on `main` | `ci-github`: `ci/github/*`, `ci/shared/rustfs` |
| `infrastructure` | `infrastructure`, from any of `.github`'s reusable workflows on `main` | `ci-infrastructure`: `ci/infrastructure/*`, `ci/shared/rustfs`, `ci/shared/cloudflare` |

A plan and a real run read the same secrets, so one role serves both: what
changes infrastructure still waits for the `production` environment's
approval, not for Vault.

A PR's plan refreshes every resource with `terraform-plan`, and fails on one
that policy cannot read: an auth method or engine added here brings its read
path in `policies/terraform-plan.hcl` in the same PR. Its own plan passes
regardless, before the resource exists, so the gap shows only in the next PR.

Neither of this repo's own policies grants a stored secret, but for its
state's (`ci/shared/rustfs`). `terraform` can still rewrite any policy,
its own included, so it is effectively an admin: what guards it is its role's
binding and the operator's approval of every run from `main`.

The CI VMs reach Vault at `https://vault.int.0xc0.cc`, the internal VIP,
through an `/etc/hosts` entry (infrastructure, the `github_runner` role).

## Transit: keys that never leave Vault

`transit/` holds keys Vault signs or encrypts with, non-exportable: whoever
uses one gets a signature, never the key. OpenTofu creates the engine only.
A key someone else issued is imported by the operator, like any other secret
value.

| Key | Type | Used by | Policy |
|---|---|---|---|
| `github-runner-app` | `rsa-2048` | the CI VMs' JIT step, which signs the runner App's JWT before every job (infrastructure, the `github_runner` role) | `github-runner`: sign with it, SHA-256, nothing else |

Importing the runner App's key, from the laptop over WARP: `vault transit
import` takes it as base64 PKCS#8 DER. It goes from its source through a pipe
and process substitution, never onto disk or the screen:

```sh
export VAULT_ADDR=https://vault.int.0xc0.cc
mise exec -- vault login -no-print

# From a .pem downloaded from the App's settings, deleted right after. From
# the copy in ci/infrastructure/runner-app while it still exists, -in takes
# <(mise exec -- vault kv get -mount=ci -field=private_key infrastructure/runner-app)
# instead of the file.
mise exec -- vault transit import transit/keys/github-runner-app \
  @<(openssl pkcs8 -topk8 -nocrypt -outform DER -in ~/Downloads/<app>.private-key.pem | openssl base64 -A) \
  type=rsa-2048
rm ~/Downloads/<app>.private-key.pem

# Check it: type, not exportable, no deletion. Reading a Transit key shows
# only its public half.
mise exec -- vault read -format=json transit/keys/github-runner-app \
  | jq '.data | {type, exportable, deletion_allowed, latest_version}'

rm -f ~/.vault-token
```

A new key for the App goes in as a new version of the same key
(`transit/keys/github-runner-app/import_version`, same input); the JIT step
signs with the latest. The old one is then deleted in the App's settings.

## AppRole: machines outside the cluster and CI

A machine with no service account and no OIDC token logs in with an AppRole:
a role ID, which is the role's name and goes in its configuration, and a
secret ID, which is a secret. The operator writes the secret ID into `ci/`,
and the pipeline that configures the machine puts it there, root-only. A
login gets a batch token that lives `token_ttl` seconds.

| Role | Machine | Policy | Secret ID in |
|---|---|---|---|
| `github-runner` | the CI VMs' JIT step, as root, before every job | `github-runner` | `ci/infrastructure/runner-approle`, key `secret_id` |

The secret ID is not bound to the machine's address: Vault sees every
connection from Traefik. What a stolen one gives is what its policy says,
only from inside the network, until it is revoked here.

Writing it, or a new one, from the laptop over WARP, straight from Vault into
`ci/`:

```sh
mise exec -- vault write -f -field=secret_id auth/approle/role/github-runner/secret-id \
  | tr -d '\n' | mise exec -- vault kv put -mount=ci infrastructure/runner-approle secret_id=-
mise exec -- vault kv metadata put -mount=ci \
  -custom-metadata=owner=operator -custom-metadata=rotated_at="$(date +%F)" infrastructure/runner-approle
```

Infrastructure's pipeline carries it to the CI VMs on its next run of
`playbooks/vm-ci.yml`. Then the old one, if any, is destroyed by its accessor
(`vault list auth/approle/role/github-runner/secret-id` lists them):

```sh
mise exec -- vault write auth/approle/role/github-runner/secret-id-accessor/destroy secret_id_accessor=<old>
```

## Bootstrap, once: the first apply is local

The CI can only log in once its auth method and roles exist. So the first
apply runs from the operator's laptop, over WARP, with the root token (operator
decision, 2026-09-30): the only apply of this repo that ever runs outside the
pipeline. It creates everything in `environments/prod` at once, the CI's way
in included; from then on every change goes through a PR and the pipeline.

```sh
# From this repo's root, over WARP (Vault on the internal VIP, RustFS for the
# state). The root token goes into the environment only: read -s keeps it out
# of the shell history and off the screen.
export VAULT_ADDR=https://vault.int.0xc0.cc
read -rs VAULT_TOKEN && export VAULT_TOKEN

scripts/tofu prod init
scripts/tofu prod plan      # read it: the auth methods, their roles, the policies, the KV engines
scripts/tofu prod apply

unset VAULT_TOKEN
```

Then check the CI gets in: open a PR here. Its plan logs in as
`terraform-plan` and shows no changes. The root token is not needed again;
it is kept outside Vault with the unseal keys (Recovery credentials).

## Running by hand

Over WARP, with a token in `VAULT_TOKEN`:

```sh
export VAULT_ADDR=https://vault.int.0xc0.cc
scripts/tofu prod plan
```

Past the bootstrap, changes run from the pipeline only, never from here.
