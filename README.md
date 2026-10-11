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
| `ci/` | what the pipelines use (Proxmox, Cloudflare, RustFS, the runners' AppRole secret ID, the promoter App's IDs) | each repo's CI jobs, over JWT |
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
  the namespace taken from its service account's token. Plus two shared paths
  by name: `apps/shared/openobserve-rum`, OpenObserve's RUM client token, one
  per organization and public by design; and `apps/shared/ghcr-pull`, keys
  `username` and `password`, a token that can only read packages, which Vault
  Secrets Operator turns into an `imagePullSecret` where an application's
  images are private. A new application
  needs no change here, only the label on its namespace in `gitops`. Whoever
  can label a namespace there gives it its own `apps/` path, never another's.
  An application's staging is a namespace of its own, `<app>-staging`, so it
  reads `apps/<app>-staging/*` (`apps/payload-staging/*`), never prod's. The
  shared database servers read each environment's `database` by name
  (`policies/postgres.hcl`, `policies/mariadb.hcl`).
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
- `kv patch` changes the keys it names and keeps the others, on a path that
  exists. `kv put` creates a path, or rewrites it whole: on an existing path
  it drops every key it does not name. So a change to one key of an existing
  secret is always `kv patch`. Then `rotated_at`, so the next rotation knows
  how old it is.

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
GitHub issues it (JWT auth, `hashicorp/vault-action`, in the reusable
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

An application repo's role is narrower, because it signs as a GitHub App
that writes to `gitops` (Application delivery, below): only its `main`,
through `.github`'s `release*` workflows on `main`. A pull request's jobs,
which run third-party code, never log in with it.

| Role | Who | Policy |
|---|---|---|
| `payload` | `payload`'s `main`, from `.github`'s `release*` workflows on `main`: its rc and release jobs | `ci-payload`: `ci/payload/*`, `ci/shared/github-promoter-app`, and signing with `github-promoter-app` |

`ci/shared/github-promoter-app` holds the `0xc0-labs-promoter` App's IDs,
keys `app_id` (its JWT's issuer) and `installation_id` (its installation on
`gitops`, which a token is asked for). Its key is in Transit, never in `ci/`.

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
| `github-promoter-app` | `rsa-2048` | `payload`'s rc and release jobs, which sign the `0xc0-labs-promoter` App's JWT to open their promotion PR in `gitops`; later the other application repos | `ci-payload`: sign with it, SHA-256, nothing else |

Importing an App's key, from the laptop over WARP: `vault transit import`
takes it as base64 PKCS#8 DER. It goes from its source through a pipe and
process substitution, never onto disk or the screen:

```sh
export VAULT_ADDR=https://vault.int.0xc0.cc
mise exec -- vault login -no-print

key=github-promoter-app   # or github-runner-app

# From a .pem downloaded from the App's settings, deleted right after. For
# the runner App, from the copy in ci/infrastructure/runner-app while it
# still exists, -in takes
# <(mise exec -- vault kv get -mount=ci -field=private_key infrastructure/runner-app)
# instead of the file.
mise exec -- vault transit import "transit/keys/$key" \
  @<(openssl pkcs8 -topk8 -nocrypt -outform DER -in ~/Downloads/<app>.private-key.pem | openssl base64 -A) \
  type=rsa-2048
rm ~/Downloads/<app>.private-key.pem

# Check it: type, not exportable, no deletion. Reading a Transit key shows
# only its public half.
mise exec -- vault read -format=json "transit/keys/$key" \
  | jq '.data | {type, exportable, deletion_allowed, latest_version}'

rm -f ~/.vault-token
```

A new key for an App goes in as a new version of the same key
(`transit/keys/<key>/import_version`, same input); whoever signs uses the
latest. The old one is then deleted in the App's settings.

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

## Application delivery: what the operator writes

An application with delivery (`payload` today) cuts an rc on every merge to
its `main` and a release by hand, and each opens a PR in `gitops` that pins
the environment's image. The PR is opened by the `0xc0-labs-promoter` App,
installed on `gitops` alone, with contents and pull requests: the job signs
the App's JWT through Transit with its repo's role (How CI gets in) and
exchanges it for an installation token. The cluster pulls the private image
with `apps/shared/ghcr-pull`, and staging runs in its own namespace with its
own `apps/<app>-staging/` path.

After the apply that adds them, from the laptop over WARP, every value on
stdin as Writing or rotating a secret says. Each `kv put` below creates its
path; once it exists, a key changes with `kv patch`, never `kv put`:

1. **The promoter App's key:** create the App, then import its key into
   `transit/keys/github-promoter-app` (Transit, above, `key=github-promoter-app`).
2. **Its IDs**, `ci/shared/github-promoter-app`. Not secrets, but written
   here so a job reads them where it reads everything else:

   ```sh
   mise exec -- vault kv put -mount=ci shared/github-promoter-app \
     app_id=<the App's ID> installation_id=<its installation on gitops>
   mise exec -- vault kv metadata put -mount=ci \
     -custom-metadata=owner=operator -custom-metadata=rotated_at="$(date +%F)" shared/github-promoter-app
   ```

3. **The pull token**, `apps/shared/ghcr-pull`: `username`, the account the
   token belongs to, and `password`, a token that can only read packages,
   shown once on GitHub's page:

   ```sh
   read -rs v && printf '%s' "$v" | mise exec -- vault kv put -mount=apps shared/ghcr-pull \
     username=<its account> password=- ; unset v
   mise exec -- vault kv metadata put -mount=apps \
     -custom-metadata=owner=operator -custom-metadata=rotated_at="$(date +%F)" shared/ghcr-pull
   ```

4. **Staging's secrets**, `apps/<app>-staging/*`. For `payload`, prod's keys
   plus one that prod lacks:

   | Path | Keys |
   |---|---|
   | `apps/payload-staging/database` | `password` |
   | `apps/payload-staging/app` | `payload-secret`, and `seed-password` (staging alone) |

   What each one is: `gitops`' `apps/payload/README.md`. Generated here, so
   the trailing newline is stripped. `app` holds two keys, so `kv put` writes
   one and `kv patch` adds the other: a `kv put` on it later would drop
   `seed-password`, and the next seed of an empty database would fail. On an
   `app` that already holds `payload-secret`, run only the `kv patch` line.

   ```sh
   # The database role's password, hex because it goes into a URL: read by
   # payload-staging, and by platform/postgres to create the role.
   openssl rand -hex 24 | tr -d '\n' | mise exec -- vault kv put -mount=apps payload-staging/database password=-
   mise exec -- vault kv metadata put -mount=apps \
     -custom-metadata=owner=operator -custom-metadata=rotated_at="$(date +%F)" payload-staging/database

   # PAYLOAD_SECRET, which signs sessions and tokens: never prod's. kv put
   # creates the path.
   openssl rand -base64 48 | tr -d '\n' | mise exec -- vault kv put -mount=apps payload-staging/app payload-secret=-
   # The seed users' and the super-admin's password, SEED_PASSWORD. kv patch
   # adds it and keeps payload-secret.
   openssl rand -base64 24 | tr -d '\n' | mise exec -- vault kv patch -mount=apps payload-staging/app seed-password=-
   mise exec -- vault kv metadata put -mount=apps \
     -custom-metadata=owner=operator -custom-metadata=rotated_at="$(date +%F)" payload-staging/app

   rm -f ~/.vault-token
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
