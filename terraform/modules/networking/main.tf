terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# One flat VNet — deliberately not a hub-and-spoke. That topology exists in
# EAAP to let many apps share central services (Bastion, shared DNS); Clarity
# is a single application, so a hub here would be pure overhead. Never peer
# this VNet to EAAP's hub, even after Clarity moves to its own subscription —
# there's no shared-services reason to, and it would recreate exactly the
# coupling the two projects are otherwise kept free of.
resource "azurerm_virtual_network" "this" {
  name                = "clarity-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = ["10.30.0.0/16"]
  tags                = var.tags
}

# Delegated subnet for the dashboard's regional VNet integration (outbound
# only — inbound traffic still reaches App Service over its public endpoint;
# this subnet is how App Service reaches Postgres/Key Vault privately).
resource "azurerm_subnet" "app_service" {
  name                 = "snet-app-service"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.30.1.0/28"]

  delegation {
    name = "app-service-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Container Apps environment VNet integration needs a dedicated subnet,
# delegated to Microsoft.App/environments (learned the hard way — the
# environment creation fails with ManagedEnvironmentSubnetDelegationError
# without it). Sized well above the minimum since Consumption-only (no
# workload profiles) environments reserve a meaningful chunk of the range
# for their own infrastructure.
resource "azurerm_subnet" "container_apps" {
  name                 = "snet-container-apps"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.30.2.0/23"]

  delegation {
    name = "container-apps-delegation"
    service_delegation {
      name = "Microsoft.App/environments"
      # Azure stores this delegation's action as join/action and rewrites
      # anything else back to it -- declaring subnets/action here made every
      # plan show a phantom update (and every apply re-send it for nothing).
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Private endpoints for Key Vault and Postgres both land here.
resource "azurerm_subnet" "private_endpoints" {
  name                              = "snet-private-endpoints"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = ["10.30.4.0/24"]
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_network_security_group" "app_service" {
  name                = "nsg-clarity-app-service"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_network_security_group" "container_apps" {
  name                = "nsg-clarity-container-apps"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "app_service" {
  subnet_id                 = azurerm_subnet.app_service.id
  network_security_group_id = azurerm_network_security_group.app_service.id
}

resource "azurerm_subnet_network_security_group_association" "container_apps" {
  subnet_id                 = azurerm_subnet.container_apps.id
  network_security_group_id = azurerm_network_security_group.container_apps.id
}

# --- Private DNS zones ---
# Linked only to this VNet, so name resolution for the private endpoints
# below only works from inside it (App Service/Container Apps VNet
# integration puts them "inside" for this purpose) — anything outside still
# resolves the public hostname, which is exactly why the operator/CI
# allowlist path (see keyvault/postgres modules) keeps working unchanged.

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                  = "clarity-vnet-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = azurerm_virtual_network.this.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "clarity-vnet-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.this.id
}
