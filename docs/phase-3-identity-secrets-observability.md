# Phase 3 — Identity, secrets and observability

## Problem

Three workloads, one database and roughly two dozen third-party credentials (Twilio, Stripe, Cal.com, Anthropic, Postmark, calendar OAuth). I needed every workload to reach exactly what it uses, with no credentials in code or app settings, and to know when something breaks before a customer does.

## What I built

### A managed identity per workload

| Workload | Identity | Uses it for |
|---|---|---|
| Dashboard (App Service) | user-assigned | Key Vault secrets |
| voice-relay (App Service) | user-assigned | Key Vault secrets, Content Safety, Azure OpenAI |
| n8n (Container Apps) | user-assigned | No Key Vault access at all (its credentials live in n8n's encrypted store) |

Key Vault runs in **RBAC mode** (no access policies). Each identity gets **Key Vault Secrets User on individual secrets**, not the vault. That design and the finding that drove it are in [securing-clarityos](https://github.com/michaeledwards0/securing-clarityos).

### Making row-level security real

Postgres row-level security policies isolate each customer's data. In testing I found they had never been enforced: the app connected as the table owner, which also had `BYPASSRLS`. Querying with no tenant context, which should return zero rows, returned every row.

The fix was a second role, `clarity_app`, with `nobypassrls` that owns nothing, so RLS applies to it automatically. Migrations still run as the owner; the app runs as `clarity_app`. n8n got its own login (`clarity_n8n`) for the same reason. The dashboard has an RLS test (`tests/rls.test.ts`) that checks a tenant can't read another tenant's rows.

### Observability

- **Diagnostic settings** send App Service HTTP/console/app logs, Key Vault `AuditEvent`, Postgres logs, and Foundry and Content Safety logs to one Log Analytics workspace.
- **Application Insights** for the dashboard and voice-relay.
- **Metric alerts** (`modules/monitoring`) to an ops action group:

| Alert | Threshold |
|---|---|
| Postgres not responding | any, 1-minute check |
| Postgres CPU / memory / storage | 80% / 90% / 80% |
| App Service plan CPU / memory | 85% (dashboard and voice-relay share the plan) |
| Dashboard 5xx | >10 in 15 min |
| voice-relay 5xx | >5 in 15 min (Twilio webhooks fail here, so calls go unanswered) |
| n8n restarts | >2 in 15 min (usually a crash loop) |

- **Availability tests** from three US regions every 15 minutes against the dashboard login and voice-relay `/healthz`, with SSL checks that warn 7 days before a certificate expires.

## Security decisions

| Decision | Why |
|---|---|
| User-assigned, not system-assigned, identities | Role assignments survive an app being recreated, and grants can exist before the app does |
| n8n has no Key Vault role | No workflow reads Key Vault, so any grant would be pure excess |
| An RLS regression test | The bug was silent from the first migration; a test is what keeps it fixed. Running it in CI is next |

## Evidence

  ## One Managed identity per workload 
  img width="1632" height="236" alt="image" src="https://github.com/user-attachments/assets/85467a12-417b-4ce5-aa4c-61a9cad445f3" />
  
  ## Keyvault RBAC for dashboard identitiy
  <img width="1438" height="454" alt="image" src="https://github.com/user-attachments/assets/24e654a9-cd76-4c40-80ab-ca07f77c4720" />
  
  ## Alert rules
  <img width="1516" height="616" alt="image" src="https://github.com/user-attachments/assets/056787b3-e135-4823-ab4b-0422d6d19daa" />
  
  ## Availability tests
  <img width="507" height="269" alt="image" src="https://github.com/user-attachments/assets/3bcce4ff-a19e-433c-8a20-86b0ea042af5" />
  
  ## Row level security (RLS) test passed on 108 rows
  <img width="936" height="175" alt="image" src="https://github.com/user-attachments/assets/029d68d4-f8e3-45b9-8c15-29bfcde3d8e0" />

