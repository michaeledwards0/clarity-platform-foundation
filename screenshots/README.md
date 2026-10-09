# Screenshot checklist

Save each file with the exact name below so the phase docs link to it. Crop out subscription IDs, tenant IDs, emails and IP addresses before committing.

| File | Where to capture it |
|---|---|
| `phase-1/01-pipeline-run.png` | GitHub → clarity-platform → Actions → latest green `deploy` run (job graph view) |
| `phase-1/02-federated-credentials.png` | Entra ID → App registrations → `clarity-platform-cicd` → Certificates & secrets → Federated credentials |
| `phase-1/03-cicd-role-assignments.png` | Entra ID → Enterprise applications → `clarity-platform-cicd` → Azure role assignments (or `az role assignment list --assignee <appId> -o table`) |
| `phase-1/04-budget-alerts.png` | Cost Management → Budgets → `clarity-monthly-budget` |
| `phase-2/01-vnet-subnets.png` | Virtual networks → `clarity-vnet` → Subnets |
| `phase-2/02-private-endpoints.png` | Private Link Center → Private endpoints (filter `pe-clarity`) |
| `phase-2/03-private-dns.png` | Private DNS zones → `privatelink.vaultcore.azure.net` → Recordsets |
| `phase-2/04-app-service-vnet-integration.png` | App Service (dashboard) → Networking → VNet integration |
| `phase-3/01-managed-identities.png` | Managed Identities (filter `clarity`) |
| `phase-3/02-keyvault-rbac-per-secret.png` | Key Vault → Secrets → `stripe-secret-key` → Access control (IAM) → Role assignments |
| `phase-3/03-alert-rules.png` | Monitor → Alerts → Alert rules (filter `clarity-`) |
| `phase-3/04-availability-tests.png` | Application Insights (dashboard) → Availability |
| `phase-3/05-rls-test-pass.png` | Terminal running `npm test -- rls` in `dashboard/` |
