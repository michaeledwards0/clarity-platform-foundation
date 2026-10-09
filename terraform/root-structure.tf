# Excerpt from clarity-platform/terraform/main.tf (production, applied by CI).
# Not standalone: the other module blocks and role assignments are omitted.

# CI/CD-managed as of this commit: terraform plan/apply run via GitHub
# Actions (.github/workflows/terraform.yml) using the cicd_identity
# module's OIDC federation — no more applying by hand from an operator
# machine.

locals {
  # Mirrors EAAP's own resource-group convention (platform / network /
  # operations, seen in enterprise-azure-application-platform's
  # terraform/environments/dev/locals.tf) rather than inventing a third
  # pattern, plus a dedicated data tier since Postgres deserves its own
  # lifecycle/RBAC boundary separate from compute.
  resource_groups = {
    platform   = "clarity-platform-rg"
    network    = "clarity-network-rg"
    data       = "clarity-data-rg"
    operations = "clarity-operations-rg"
  }
}

resource "azurerm_resource_group" "clarity" {
  for_each = local.resource_groups

  name     = each.value
  location = var.location
  tags     = var.tags
}

module "networking" {
  source = "./modules/networking"

  resource_group_name = azurerm_resource_group.clarity["network"].name
  location            = azurerm_resource_group.clarity["network"].location
  tags                = var.tags
}

module "keyvault" {
  source = "./modules/keyvault"

  name                       = var.key_vault_name
  resource_group_name        = azurerm_resource_group.clarity["platform"].name
  location                   = azurerm_resource_group.clarity["platform"].location
  private_endpoint_subnet_id = module.networking.private_endpoints_subnet_id
  private_dns_zone_id        = module.networking.key_vault_private_dns_zone_id
  operator_allow_ips         = var.operator_allow_ips
  tags                       = var.tags

  depends_on = [module.networking]

  # Granted after the dashboard/n8n identities exist (see role assignments below)
  # rather than passed in here, to avoid a module dependency cycle.
}

module "postgres" {
  source = "./modules/postgres"

  name                       = var.postgres_server_name
  resource_group_name        = azurerm_resource_group.clarity["data"].name
  location                   = azurerm_resource_group.clarity["data"].location
  key_vault_id               = module.keyvault.id
  allow_azure_services       = true
  firewall_allow_ips         = var.postgres_firewall_allow_ips
  private_endpoint_subnet_id = module.networking.private_endpoints_subnet_id
  private_dns_zone_id        = module.networking.postgres_private_dns_zone_id
  tags                       = var.tags

  depends_on = [time_sleep.kv_rbac_ready, module.networking]
}
