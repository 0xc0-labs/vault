jwt_audience = "https://vault.int.0xc0.cc"

# This repo's plan and apply (README, How CI gets in; operator decision,
# 2026-09-30).
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

  # The other repos' CI, one role each for plan and run (README, How CI gets
  # in; operator decision, 2026-10-01).
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

  # Application delivery: main's release jobs only, never a pull request's
  # (README, How CI gets in; operator decisions, 2026-10-10, 2026-10-11 and
  # 2026-10-12).
  "payload" = {
    claims_type = "glob"
    bound_claims = {
      repository       = "0xc0-labs/payload"
      ref              = "refs/heads/main"
      job_workflow_ref = "0xc0-labs/.github/.github/workflows/release*.yml@refs/heads/main"
    }
    policies = ["ci-payload"]
  }
  # The role's name is the repo's: the release workflow logs in as
  # github.event.repository.name.
  "offby1.cc" = {
    claims_type = "glob"
    bound_claims = {
      repository       = "0xc0-labs/offby1.cc"
      ref              = "refs/heads/main"
      job_workflow_ref = "0xc0-labs/.github/.github/workflows/release*.yml@refs/heads/main"
    }
    policies = ["ci-offby1-cc"]
  }
  "artistlabco.com" = {
    claims_type = "glob"
    bound_claims = {
      repository       = "0xc0-labs/artistlabco.com"
      ref              = "refs/heads/main"
      job_workflow_ref = "0xc0-labs/.github/.github/workflows/release*.yml@refs/heads/main"
    }
    policies = ["ci-artistlabco-com"]
  }
}

# One engine per trust boundary (README, Secrets; operator decision,
# 2026-09-30; ops/ 2026-10-02).
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
  # A new application needs only this label on its namespace (README, Secrets).
  "apps" = {
    namespace_labels = { "vault.0xc0.cc/apps" = "true" }
    service_accounts = ["vault-secrets"]
    policies         = ["apps"]
  }
  # Payload's own identity over its tenants' secrets (README, Secrets).
  "payload-tenants" = {
    namespace_labels = { "vault.0xc0.cc/payload-tenants" = "true" }
    service_accounts = ["payload"]
    policies         = ["payload-tenants"]
  }
}

# Machines outside the cluster and CI (README, AppRole; operator decision,
# 2026-10-10).
approle_roles = {
  # The CI VMs' JIT step (infrastructure, the github_runner role).
  "github-runner" = {
    policies  = ["github-runner"]
    token_ttl = 60
  }
}
