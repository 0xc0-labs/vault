# The reusable tofu workflows request vault-addr as the token's audience.
jwt_audience = "https://vault.int.0xc0.cc"

# Operator decision, 2026-09-30: a PR plans read-only from any ref; only main,
# inside the approval-gated production environment, writes.
jwt_roles = {
  "terraform-plan" = {
    bound_claims = {
      repository       = "0xc0-labs/vault"
      job_workflow_ref = "0xc0-labs/.github/.github/workflows/tofu-plan.yml@refs/heads/main"
    }
    policies = ["terraform-plan"]
  }
  "terraform" = {
    bound_claims = {
      repository       = "0xc0-labs/vault"
      ref              = "refs/heads/main"
      environment      = "production"
      job_workflow_ref = "0xc0-labs/.github/.github/workflows/tofu-apply.yml@refs/heads/main"
    }
    policies = ["terraform"]
  }

  # The other repos' CI (operator decision, 2026-10-01). Read-only, so one role
  # serves plan and run; production's approval gates what changes anything.
  "github" = {
    claims_type = "glob"
    bound_claims = {
      repository       = "0xc0-labs/.github"
      job_workflow_ref = "0xc0-labs/.github/.github/workflows/*@refs/heads/main"
    }
    policies = ["ci-github"]
  }
  "infrastructure" = {
    claims_type = "glob"
    bound_claims = {
      repository       = "0xc0-labs/infrastructure"
      job_workflow_ref = "0xc0-labs/.github/.github/workflows/*@refs/heads/main"
    }
    policies = ["ci-infrastructure"]
  }
}

# One engine per trust boundary (operator decision, 2026-09-30; ops/ 2026-10-02).
kv_engines = {
  platform = "The cluster's shared services, one path per namespace, read by Vault Secrets Operator"
  apps     = "The applications, one path per namespace, read by Vault Secrets Operator"
  ci       = "The pipelines, one path per repo, read by that repo's CI jobs over JWT"
  ops      = "What only people use: UI logins and passwords in clear. No machine has a policy on it"
}

# The service account is declared in gitops, <component>/vault-secrets.yaml.
kubernetes_roles = {
  "cert-manager" = {
    namespace        = "cert-manager"
    service_accounts = ["vault-secrets"]
    policies         = ["cert-manager"]
  }
  "external-dns" = {
    namespace        = "external-dns"
    service_accounts = ["vault-secrets"]
    policies         = ["external-dns"]
  }
  "crowdsec" = {
    namespace        = "crowdsec"
    service_accounts = ["vault-secrets"]
    policies         = ["crowdsec"]
  }
  "traefik" = {
    namespace        = "traefik"
    service_accounts = ["vault-secrets"]
    policies         = ["traefik"]
  }
  "longhorn-system" = {
    namespace        = "longhorn-system"
    service_accounts = ["vault-secrets"]
    policies         = ["longhorn-system"]
  }
  "openobserve" = {
    namespace        = "openobserve"
    service_accounts = ["vault-secrets"]
    policies         = ["openobserve"]
  }
  "openobserve-collector" = {
    namespace        = "openobserve-collector"
    service_accounts = ["vault-secrets"]
    policies         = ["openobserve-collector"]
  }
  "mariadb" = {
    namespace        = "mariadb"
    service_accounts = ["vault-secrets"]
    policies         = ["mariadb"]
  }
  "postgres" = {
    namespace        = "postgres"
    service_accounts = ["vault-secrets"]
    policies         = ["postgres"]
  }
  # Its policy reads only apps/<the login's namespace>/*, so a new
  # application needs nothing here.
  "apps" = {
    namespace_labels = { "vault.0xc0.cc/apps" = "true" }
    service_accounts = ["vault-secrets"]
    policies         = ["apps"]
  }
}

# Machines outside the cluster and CI (operator decision, 2026-10-10). The role
# ID is the role's name; the operator writes the secret ID.
approle_roles = {
  # The CI VMs' JIT step: Vault signs the runner App's JWT, so the App's key
  # never sits on them (infrastructure, the github_runner role).
  "github-runner" = {
    policies  = ["github-runner"]
    token_ttl = 60
  }
}
