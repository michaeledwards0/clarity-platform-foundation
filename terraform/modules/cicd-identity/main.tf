terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Dedicated app registration for Clarity's own CI/CD — never reused or
# extended from any other project's identity.
resource "azuread_application" "cicd" {
  display_name = "clarity-platform-cicd"
}

resource "azuread_service_principal" "cicd" {
  client_id = azuread_application.cicd.client_id
}

# OIDC federation for GitHub Actions (workload identity federation) —
# no client secret to rotate or leak.
resource "azuread_application_federated_identity_credential" "github_main" {
  application_id = azuread_application.cicd.id
  display_name   = "clarity-github-main"
  description    = "Trusts GitHub Actions runs on main branch of the clarity-platform repo"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}@${var.github_org_id}/${var.github_repo}@${var.github_repo_id}:ref:refs/heads/main"
}

resource "azuread_application_federated_identity_credential" "github_pr" {
  application_id = azuread_application.cicd.id
  display_name   = "clarity-github-pull-request"
  description    = "Trusts GitHub Actions runs on pull_request events for the clarity-platform repo"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}@${var.github_org_id}/${var.github_repo}@${var.github_repo_id}:pull_request"
}

# A job that references an "environment:" (see the apply job in
# .github/workflows/terraform.yml, which uses one to gate applies behind a
# required reviewer) gets a DIFFERENT OIDC subject shape from GitHub —
# repo:ORG@ORG_ID/REPO@REPO_ID:environment:NAME, replacing the ref-based
# subject entirely, not adding to it. Hit as a second AADSTS700213 the first
# time the apply job actually ran, since github_main above only covers the
# ref-based subject.
resource "azuread_application_federated_identity_credential" "github_production_environment" {
  application_id = azuread_application.cicd.id
  display_name   = "clarity-github-production-environment"
  description    = "Trusts GitHub Actions runs against the production environment of the clarity-platform repo"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}@${var.github_org_id}/${var.github_repo}@${var.github_repo_id}:environment:production"
}

# Scoped ONLY to the resource groups Clarity's Terraform creates — never
# subscription-level, and never inherited/extended from another project.
# One assignment per RG (platform/network/data/operations) rather than a
# single subscription-wide grant.
resource "azurerm_role_assignment" "cicd_contributor_app_rgs" {
  for_each             = var.clarity_rg_ids
  scope                = each.value
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.cicd.object_id
}

resource "azurerm_role_assignment" "cicd_contributor_tfstate_rg" {
  scope                = var.tfstate_rg_id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.cicd.object_id
}

# Needed so CI/CD can create the Key Vault RBAC role assignments — only the
# platform RG holds Key Vault, so scope this narrowly rather than granting
# RBAC-on-RBAC across every resource group.
resource "azurerm_role_assignment" "cicd_user_access_admin_platform_rg" {
  scope                = var.platform_rg_id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.cicd.object_id
}

output "client_id" {
  value = azuread_application.cicd.client_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "service_principal_object_id" {
  value = azuread_service_principal.cicd.object_id
}

data "azurerm_client_config" "current" {}
