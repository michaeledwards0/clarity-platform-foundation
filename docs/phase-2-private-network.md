# Phase 2 — Private network

## Problem

The dashboard, voice-relay and n8n all need Key Vault and Postgres. Without private networking, every one of those calls crosses the public internet to a public endpoint.

## What I built

Module: [`terraform/modules/networking`](../terraform/modules/networking/main.tf)

| Subnet | Range | Purpose |
|---|---|---|
| `snet-app-service` | 10.30.1.0/28 | Regional VNet integration for the dashboard and voice-relay (delegated to `Microsoft.Web/serverFarms`) |
| `snet-container-apps` | 10.30.2.0/23 | Container Apps environment for n8n (delegated to `Microsoft.App/environments`) |
| `snet-private-endpoints` | 10.30.4.0/24 | Private endpoints for Key Vault and Postgres |

- NSGs attached to both workload subnets.
- Private DNS zones `privatelink.vaultcore.azure.net` and `privatelink.postgres.database.azure.com`, linked only to this VNet. Inside the VNet the vault and database resolve to private IPs; outside, they still resolve publicly.
- Both App Services set `vnet_route_all_enabled = true`, so all their outbound traffic goes through the VNet, not just RFC1918 traffic.
- Postgres connections use `sslmode=require`.

## Security decisions

**Flat VNet, not hub-and-spoke.** I've built hub-and-spoke before. It exists so many workloads can share Bastion, DNS and a firewall. Clarity is one application with no shared services, so a hub would add cost and peering complexity for nothing. The module comments say so, so the next engineer doesn't "fix" it.

**Lessons the Terraform now encodes:**
- The Container Apps subnet must be delegated to `Microsoft.App/environments` or the environment fails with `ManagedEnvironmentSubnetDelegationError`.
- Azure rewrites that delegation's action to `subnets/join/action`. Declaring anything else causes a phantom diff on every plan.
- The Consumption-only Container Apps environment reserves a large share of its subnet, so it gets a /23.

**What's still public, and why.** Key Vault's network ACL is `Allow` and Postgres keeps a firewall allowlist alongside its private endpoint. GitHub-hosted runners use rotating IP ranges, so CI can't reach a locked-down vault. RBAC (Key Vault) and per-role credentials (Postgres) are the gate today. A self-hosted runner inside the VNet is the planned fix.

## Evidence

**[VERIFY: capture these, see [screenshots/README.md](../screenshots/README.md)]**

- `screenshots/phase-2/01-vnet-subnets.png` — subnets with delegations
- `screenshots/phase-2/02-private-endpoints.png` — Key Vault and Postgres private endpoints, approved
- `screenshots/phase-2/03-private-dns.png` — DNS zone records pointing at 10.30.4.x
- `screenshots/phase-2/04-app-service-vnet-integration.png` — route all enabled
