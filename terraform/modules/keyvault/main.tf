terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  # Key Vault names must be globally unique across Azure. Chosen as a real
  # production-worthy name now, no throwaway -dev/-test suffix.
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # RBAC authorization model (not legacy access policies) — permissions are
  # granted via azurerm_role_assignment against built-in roles.
  rbac_authorization_enabled = true

  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  # Network layer intentionally open (RBAC is the real gate — see the
  # cicd_kv_secrets_officer/operator_kv_secrets_officer/dashboard_kv_reader/
  # n8n_kv_reader role assignments in the root module; rbac_authorization_enabled
  # above still requires an actual role assignment to read or write any
  # secret). An IP-allowlisted "Deny" here
  # was tried first, but GitHub-hosted Actions runners get a different
  # public IP every run, drawn from huge published ranges — there's no
  # allowlist that stays valid, and "AzureServices" bypass doesn't cover
  # third-party CI infrastructure. The real fix is a self-hosted runner
  # living inside the VNet (already noted as deferred in README.md,
  # scoped into Phase 6 of docs/clarity-os-roadmap.md); revisit then.
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "this" {
  name                = "pe-clarity-kv"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-clarity-kv"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

# Secrets Officer/User role assignments for every real actor that needs to
# read or write secrets in this vault — the CI/CD identity, the human
# operator, and the dashboard/n8n managed identities — are granted in the
# root module (terraform/main.tf), after those identities all exist, to
# avoid a cross-module dependency cycle.
#
# This used to be a single dynamic grant here, bound to whichever identity
# happened to be running `terraform apply` (data.azurerm_client_config.current).
# That worked until CI/CD started running terraform too: CI and a human
# both being valid "current" identities meant this dynamic grant collided
# with CI's own static grant in the root module (RoleAssignmentExists 409)
# whenever CI ran apply, and flipped away from CI (breaking its next plan)
# whenever a human ran apply locally. Static, per-identity grants for every
# real actor — instead of one grant that shifts under whoever's currently
# running Terraform — avoids both failure modes for good.
