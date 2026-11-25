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
  in with it is a machine's (`platform/grafana/admin`: Grafana reads its
  admin login from it).
- **One service, one path.** A secret belongs to the service it is for, not
  to whoever reads it: ArgoCD's is `platform/argocd/admin`, even though
  infrastructure's CI writes it into the cluster. A reader across a boundary is
  granted it by name, with the reason in its policy (`ci-infrastructure.hcl`).
- **Paths:** `<engine>/<owner>/<name>`. The owner is the namespace, the repo
  under `ci/`, or the service under `ops/`, and it is what a policy scopes to.
  Everything is lowercase and kebab-case: `platform/loki/r2`,
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
  by name: `apps/shared/ghcr-pull`, keys
  `username` and `password`, a token that can only read packages, which Vault
  Secrets Operator turns into an `imagePullSecret` where an application's
  images are private. A new application
  needs no change here, only the label on its namespace in `gitops`. Whoever
  can label a namespace there gives it its own `apps/` path, never another's.
  An application's staging is a namespace of its own, `<app>-staging`, so it
  reads `apps/<app>-staging/*` (`apps/artistlabco-com-staging/*`), never prod's. The
  shared database servers read each environment's `database` by name
  (`policies/postgres.hcl`, `policies/mariadb.hcl`).
- **Matchmark's sandboxes:** a role of its own, `matchmark-sandboxes`
  (namespace `matchmark-sandboxes`, service account `vault-secrets`), that
  reads two paths by name and nothing else
  (`policies/matchmark-sandboxes.hcl`): `apps/matchmark/claude-subscription`,
  the Claude subscription's token (key `oauth_token`), and
  `apps/shared/ghcr-pull`, the org's pull credential, because a sandbox's
  init container copies the runner from a private image of `ghcr.io/0xc0-labs`;
  that credential can only read packages. The namespace is **not** labelled
  `vault.0xc0.cc/apps`, on purpose: it holds no path of its own, and the
  `apps` role does not admit it. The sandboxes run code a coding agent
  writes, so they get the narrowest grant there is.
- **A site's Strapi:** a second role, `cms`, for the namespaces labelled
  `vault.0xc0.cc/cms: "true"` (`artistlabco-com` and
  `artistlabco-com-staging`), service account `cms`, and the templated policy
  `policies/cms.hcl.tftpl`: the login creates, reads, updates, deletes and
  lists only `apps/<its own namespace>/integrations/*`, where the keys set in
  Strapi's admin live, and removes their versions with them. Nothing else of
  the namespace. A new site's Strapi gets it with the label on its namespace
  in `gitops` and a service account named `cms`.
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
  becomes part of the secret (a generated root password, 2026-10-01).
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
| `offby1.cc` | `offby1.cc`'s `main`, from `.github`'s `release*` workflows on `main`: its release job, on every push | `ci-offby1-cc`: `ci/shared/github-promoter-app`, and signing with `github-promoter-app`; no `ci/offby1-cc/*`, as its release needs no secret of its own |
| `artistlabco.com` | `artistlabco.com`'s `main`, from `.github`'s `release*` workflows on `main`: its rc and release jobs | `ci-artistlabco-com`: `ci/shared/github-promoter-app`, and signing with `github-promoter-app`; no `ci/artistlabco-com/*`, as it keeps no CI secret |
| `matchmark` | `matchmark`'s `main`, from `.github`'s `release*` workflows on `main`: its release job, on every push | `ci-matchmark`: `ci/shared/github-promoter-app`, and signing with `github-promoter-app`; no `ci/matchmark/*`, as its release needs no secret of its own |

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
value; one Vault generates is created by the operator too. The pipeline's
roles have nothing on `transit/keys/`.

| Key | Type | Used by | Policy |
|---|---|---|---|
| `github-runner-app` | `rsa-2048` | the CI VMs' JIT step, which signs the runner App's JWT before every job (infrastructure, the `github_runner` role). The App's IDs are plain configuration in `infrastructure` (`ansible/inventory/group_vars/ci.yml`), not in Vault | `github-runner`: sign with it, SHA-256, nothing else |
| `github-promoter-app` | `rsa-2048` | `artistlabco.com`'s rc and release jobs, and the release jobs of `offby1.cc` and `matchmark`, which sign the `0xc0-labs-promoter` App's JWT to open their promotion PR in `gitops`; later the other application repos | `ci-artistlabco-com`, `ci-matchmark`, `ci-offby1-cc`: sign with it, SHA-256, nothing else |
| `matchmark-agent-tokens` | `ed25519`, generated in Vault | Matchmark's API (Kubernetes auth role `matchmark-api`: namespace `matchmark`, service account `api`), which signs the agent tokens (EdDSA JWTs) and publishes the key's public half as a JWKS for the gateway | `matchmark-api`: sign with it, read the key, nothing else |

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

A key Vault generates is created by the operator with no input, and Vault
never shows its private half. It is non-exportable and not deletable by
default; the check is the one above:

```sh
key=matchmark-agent-tokens

mise exec -- vault write -f "transit/keys/$key" type=ed25519
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

An application with delivery (`artistlabco.com` today) cuts an rc on every merge to
its `main` and a release by hand, and each opens a PR in `gitops` that pins
the environment's image. The PR is opened by the `0xc0-labs-promoter` App,
installed on `gitops` alone, with contents and pull requests: the job signs
the App's JWT through Transit with its repo's role (How CI gets in) and
exchanges it for an installation token. The cluster pulls the private image
with `apps/shared/ghcr-pull`, and staging runs in its own namespace with its
own `apps/<app>-staging/` path.

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

4. **The application's own secrets**, `apps/<namespace>/*`, are listed in its
   README in `gitops`, the one home of that fact: for `artistlabco.com`,
   [`apps/artistlabco-com/README.md`](https://github.com/0xc0-labs/gitops/blob/main/apps/artistlabco-com/README.md),
   "Before the first sync: the secrets".
5. **The keys of its integrations** (the R2 token, the Resend key) are not
   written here: they are entered in Strapi's admin, and Strapi writes them
   under `apps/<namespace>/integrations/` with the `cms` role (Secrets,
   above). What the operator creates in each service to enter there:
   - **R2:** an API token with "Object Read & Write", applied to that
     site's own buckets alone, never another environment's.
   - **Resend:** one key per environment, with "Sending access" only,
     restricted to the sending domain.

## The auction watcher's mail secret

`auction-watch` (a CronJob that mails the operator when a server in Hetzner's
auction meets the operator's limits) reads one secret, written as
[Writing or rotating a secret](#writing-or-rotating-a-secret) says; below,
only which keys at which path:

`platform/auction-watch/mail`:

| Key | Value |
|---|---|
| `api_key` | a Resend key with "Sending access" only, restricted to `0xc0.cc`, as for the keys above |
| `to` | the address the mails go to; kept here so no repo holds it |

## Grafana's admin login

Grafana, in kube-prometheus-stack (namespace `monitoring`), reads its admin
login through Vault Secrets Operator (`policies/monitoring.hcl`: `read` on
`platform/grafana/*` alone). Written as
[Writing or rotating a secret](#writing-or-rotating-a-secret) says; below,
only which keys at which path:

`platform/grafana/admin`:

| Key | Value |
|---|---|
| `admin_user` | the login name; not a secret |
| `admin_password` | the password, generated and stripped of its newline (`openssl rand -base64 32 \| tr -d '\n'`) |

The chart's `admin.existingSecret` names them as values, `admin.userKey` and
`admin.passwordKey`, so they follow the `snake_case` rule above.

## Loki's and Tempo's R2 keys

Loki (namespace `loki`) and Tempo (namespace `tempo`) keep their data in
Cloudflare R2 buckets and read its keys through Vault Secrets Operator
(`policies/loki.hcl` and `policies/tempo.hcl`: each `read` on its own
`platform/<name>/*` alone). Written as
[Writing or rotating a secret](#writing-or-rotating-a-secret) says; below,
only which keys at which paths: `platform/loki/r2` and `platform/tempo/r2`,
the same three keys each:

| Key | Value |
|---|---|
| `access_key_id` | the R2 API token's access key ID |
| `secret_access_key` | the R2 API token's secret access key |
| `endpoint` | the R2 S3 address, `https://<account id>.r2.cloudflarestorage.com`; not a secret, kept with its keys as `artistlabco.com`'s Strapi does |

The token is one R2 API token per bucket, Object Read & Write: `loki-chunks`
for Loki, `tempo-blocks` for Tempo, as `infrastructure`'s README ("Private
buckets") says.

## Secrets no longer read

OpenObserve and its collector left the cluster, and their roles and policies
with them. The secrets at `platform/openobserve/*`,
`platform/openobserve-collector/*` and `apps/shared/openobserve-rum` are read by
nothing now; the operator may delete them (`vault kv metadata delete`).

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
