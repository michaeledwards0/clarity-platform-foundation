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

**[VERIFY: capture these, see [screenshots/README.md](../screenshots/README.md)]**

- `screenshots/phase-3/01-managed-identities.png`
- `screenshots/phase-3/02-keyvault-rbac-per-secret.png` — a secret's Access control blade showing one identity
- `screenshots/phase-3/03-alert-rules.png`
- `screenshots/phase-3/04-availability-tests.png`
- `screenshots/phase-3/05-rls-test-pass.png` — test output
