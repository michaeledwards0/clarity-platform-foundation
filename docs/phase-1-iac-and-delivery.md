# Phase 1 — Infrastructure as Code and delivery

## Problem

ClarityOS started as portal clicks and hand-run `terraform apply` from my laptop. Two things broke that model: CI and I were both running Terraform (and fighting over the same Key Vault role assignment), and three separate GitHub workflows could deploy to the same App Service at the same time. One of those races caused an outage.

## What I built

### Terraform layout

Four resource groups, each its own lifecycle and RBAC boundary:

| Resource group | Holds |
|---|---|
| `clarity-platform-rg` | App Service plan, dashboard, voice-relay, Container Apps (n8n), Key Vault, Content Safety, Foundry, API Management **[VERIFY: APIM resource group]** |
| `clarity-network-rg` | VNet, subnets, NSGs, private DNS zones |
| `clarity-data-rg` | PostgreSQL Flexible Server |
| `clarity-operations-rg` | Log Analytics, alerts, action group |

One module per concern: `networking`, `keyvault`, `postgres`, `operations`, `container-apps`, `app-service`, `voice-relay`, `calendar-oauth`, `content-safety`, `ai-foundry`, `monitoring`, `cicd-identity`, `api-management` **[VERIFY: module name]**. The root module wires them together ([root-structure.tf](../terraform/root-structure.tf)).

A separate **bootstrap** root, applied by a human once, creates the things CI must never be able to grant itself:

- The remote-state storage account and container (`clarity-tfstate-rg`)
- A subscription budget ($75/month, alerts at 50% and 80% actual and 100% forecast)
- The CI identity's one subscription-scoped role (Security Admin, for Defender plans)

### One pipeline, ordered jobs

[`pipeline/deploy.yml`](../pipeline/deploy.yml) replaced three independently triggered workflows:

```
changes (path filter) → terraform-plan → terraform-apply (production environment) → deploy-dashboard
                                                                                  → deploy-voice-relay
```

- `needs:` forces any Terraform apply to finish before either app deploy starts, which removed the race that caused the outage.
- A `concurrency` group queues a second push instead of running it alongside the first.
- Pull requests get `terraform validate` and `plan` only; applies run on `main`.

### OIDC federation, no client secrets

The CI identity ([cicd-identity](../terraform/modules/cicd-identity/main.tf)) is an Entra app registration with three federated credentials: `main`, `pull_request`, and the `production` environment. That third one exists because a job that uses a GitHub environment gets a different OIDC subject (`...:environment:production`), which I found the first time the apply job failed with `AADSTS700213`.

Its Azure access is **Contributor on the four Clarity resource groups and the state resource group only**, plus User Access Administrator on the platform resource group so it can create Key Vault role assignments. It never holds subscription Contributor.

## Security decisions

| Decision | Why |
|---|---|
| Static Key Vault Secrets Officer grants for each real actor (CI and operator) | A single grant tied to "whoever is running Terraform" flipped between CI and me and broke the next plan |
| Human-applied bootstrap | CI shouldn't be able to grant itself subscription-scoped roles or change its own budget |
| `.tfvars`, state and plan files ignored in git | Plan files contain resolved secret values |

## Evidence


- Successful CIDD pipeline run <img width="1464" height="705" alt="image" src="https://github.com/user-attachments/assets/858b3337-b211-4cfd-bb31-c492c6dbd85a" />
- CI identity federated credentials <img width="1457" height="502" alt="image" src="https://github.com/user-attachments/assets/3db3872e-15a0-47e8-9c72-0f31761e4742" />
- CI identity assignment scopes <img width="1245" height="315" alt="image" src="https://github.com/user-attachments/assets/b5965a53-8617-469c-be77-b48abc727c78" />
  
