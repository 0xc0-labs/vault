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
  Everything is lowercase and kebab-case: `platform/openobserve/root`,
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
  together. That token manages the DNS, the tunnels, Zero Trust and, since
  workspace#88, R2. So the cluster's copy, which cert-manager and
  external-dns read for the DNS alone, can also read and delete every bucket:
  an accepted risk (the workspace's
  [`docs/accepted-risks.md`](https://github.com/0xc0-labs/workspace/blob/main/docs/accepted-risks.md)).
  The applications never read it: each reads its own bucket with a token
  scoped to it
  ([Application delivery](#application-delivery-what-the-operator-writes)).
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
| The Resend account, and its 2FA | it issues the applications' email keys: a leaked one is revoked there, with or without Vault |

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
- Stdin carries one value. Several in one write each go through process
  substitution, `key=@<(printf '%s' "$v")`: `printf` is a builtin, so the
  value reaches no command line.
- `kv patch` changes the keys it names and keeps the others, on a path that
  exists. `kv put` creates a path, or rewrites it whole: on an existing path
  it drops every key it does not name. So a change to one key of an existing
  secret is always `kv patch`. Then `rotated_at`, so the next rotation knows
  how old it is.

Every procedure that writes a secret, in this repo or another, links here
and says only which keys at which path, and where each value comes from:

```sh
export VAULT_ADDR=https://vault.int.0xc0.cc
mise exec -- vault login -no-print

# One value, by where it comes from. On a new path, kv put instead of kv patch.
# Shown once on a web page (an API token):
read -rs v && printf '%s' "$v" | mise exec -- vault kv patch -mount=<engine> <owner>/<name> <key>=- ; unset v
# Generated here (a password):
openssl rand -base64 24 | tr -d '\n' | mise exec -- vault kv patch -mount=<engine> <owner>/<name> <key>=-
# Downloaded as a file (a private key), deleted right after:
mise exec -- vault kv patch -mount=<engine> <owner>/<name> <key>=- < ~/Downloads/<file> && rm ~/Downloads/<file>

# Several values that change together (a key ID and its secret): each read
# in turn, Enter after each.
read -rs a && read -rs b && mise exec -- vault kv put -mount=<engine> <owner>/<name> \
  <key_a>=@<(printf '%s' "$a") <key_b>=@<(printf '%s' "$b") ; unset a b

mise exec -- vault kv metadata put -mount=<engine> \
  -custom-metadata=owner=operator -custom-metadata=rotated_at="$(date +%F)" <owner>/<name>

rm -f ~/.vault-token
```

Every consumer follows on its own: the pipelines read Vault on every run, and
Vault Secrets Operator refreshes the cluster's Secrets within its refresh
interval. A credential that also lives with its provider (an API token, an
App key) is revoked there once the new one is in Vault and a run has used it.

## When the cluster or Vault is down

Every secret lives in Vault and nowhere else, so with Vault down no pipeline
runs (plan, apply, ansible, packer), nor do the local scripts. That is an
accepted risk (the workspace's
[`docs/accepted-risks.md`](https://github.com/0xc0-labs/workspace/blob/main/docs/accepted-risks.md)).
Besides Vault, the only copy of the secrets is PBS's backup of the RKE2
servers, whose Longhorn volumes hold Vault's Raft data.

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
| `offby1.cc` | `offby1.cc`'s `main`, from `.github`'s `release*` workflows on `main`: its release job, on every push | `ci-offby1-cc`: `ci/shared/github-promoter-app`, and signing with `github-promoter-app`; no `ci/offby1-cc/*`, as its release needs no secret of its own |
| `artistlabco.com` | `artistlabco.com`'s `main`, from `.github`'s `release*` workflows on `main`: its rc and release jobs | `ci-artistlabco-com`: `ci/shared/github-promoter-app`, and signing with `github-promoter-app`; no `ci/artistlabco-com/*`, as it keeps no CI secret |

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
| `github-promoter-app` | `rsa-2048` | `payload`'s and `artistlabco.com`'s rc and release jobs, and `offby1.cc`'s release job, which sign the `0xc0-labs-promoter` App's JWT to open their promotion PR in `gitops`; later the other application repos | `ci-payload`, `ci-artistlabco-com`, `ci-offby1-cc`: sign with it, SHA-256, nothing else |

Importing an App's key, logged in as
[Writing or rotating a secret](#writing-or-rotating-a-secret) says: `vault
transit import` takes it as base64 PKCS#8 DER. It goes from its source
through a pipe and process substitution, never onto disk or the screen:

```sh
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

Writing it, or a new one, as
[Writing or rotating a secret](#writing-or-rotating-a-secret) says, the
value straight from Vault into `ci/`. The path holds `secret_id` alone, so
`kv put` rewrites it whole:

```sh
mise exec -- vault write -f -field=secret_id auth/approle/role/github-runner/secret-id \
  | tr -d '\n' | mise exec -- vault kv put -mount=ci infrastructure/runner-approle secret_id=-
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
own `apps/<app>-staging/` path. Its files live in Cloudflare R2, one bucket
per environment (`<namespace>-<purpose>`), read with a token scoped to that
bucket at `apps/<namespace>/media`. It sends email through Resend, with a key
per environment at `apps/<namespace>/email`.

After the apply that adds them, each is written as
[Writing or rotating a secret](#writing-or-rotating-a-secret) says; below,
only which keys at which path, and where each value comes from. `kv put`
creates a path; once it exists, a key changes with `kv patch`.

1. **The promoter App's key:** create the App, then import its key into
   `transit/keys/github-promoter-app`
   ([Transit](#transit-keys-that-never-leave-vault), `key=github-promoter-app`).
2. **Its IDs**, `ci/shared/github-promoter-app`, written here so a job reads
   them where it reads everything else. Not secrets, so on the command line
   as they are:

   | Key | Value |
   |---|---|
   | `app_id` | the App's ID, on its settings page |
   | `installation_id` | its installation on `gitops`, the number in the installation's URL |

3. **The pull token**, `apps/shared/ghcr-pull`:

   | Key | Value |
   |---|---|
   | `username` | the account the token belongs to; not a secret |
   | `password` | a token that can only read packages, shown once on GitHub's page |

4. **Staging's secrets**, `apps/<app>-staging/*`. For `payload`, prod's keys
   plus one that prod lacks, `seed-password`; what each one is: `gitops`'
   `apps/payload/README.md`. All generated here:

   | Path | Key | Value |
   |---|---|---|
   | `apps/payload-staging/database` | `password` | `openssl rand -hex 24`: hex, because it goes into a URL |
   | `apps/payload-staging/app` | `payload-secret` | `openssl rand -base64 48`, never prod's |
   | `apps/payload-staging/app` | `seed-password` | `openssl rand -base64 24`, staging alone |

   `app` holds two keys: `kv put` creates it with `payload-secret`, then
   `kv patch` adds `seed-password`. A `kv put` on it later would drop
   `seed-password`, and the next seed of an empty database would fail. On an
   `app` that already holds `payload-secret`, only the `kv patch`.

5. **Each environment's media bucket**, `apps/<namespace>/media`, keys
   `access_key_id` and `secret_access_key`: an R2 token scoped to that bucket
   alone. Once `infrastructure`'s Cloudflare root has created the buckets:

   | Path | Bucket |
   |---|---|
   | `apps/payload/media` | `payload-media` |
   | `apps/payload-staging/media` | `payload-staging-media` |

   In the Cloudflare dashboard, R2, Manage API tokens: an API token with
   "Object Read & Write", applied to that one bucket. One token per bucket,
   never one for both. Cloudflare shows its Access Key ID and Secret Access
   Key once; both go in one write, as several values. The S3 endpoint and the
   bucket's name are not secrets: `gitops` sets them beside the application,
   never here. A new token changes both keys at once, so it goes in with the
   same `kv put`; the old token is then deleted in Cloudflare.

6. **Each environment's email**, `apps/<namespace>/email`: a Resend API key,
   which the application sends with over SMTP. Once `0xc0.cc` is verified in
   Resend:

   | Path | Keys |
   |---|---|
   | `apps/payload/email` | `api_key` |
   | `apps/payload-staging/email` | `api_key`, and `redirect_to` (staging alone) |

   In Resend's dashboard, API Keys: one key per environment, with "Sending
   access" only, restricted to the domain `0xc0.cc`. Resend shows it once.
   `redirect_to` is the inbox every staging message goes to instead of its
   recipient, so staging never mails a real person; staging's two go in one
   write, as several values. SMTP's host, port and user, and the sender's
   address, are not secrets: `gitops` sets them beside the application, never
   here. A new key changes `api_key` alone, so it goes in with `kv patch`,
   which keeps staging's `redirect_to`; the old key is then deleted in Resend.

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
