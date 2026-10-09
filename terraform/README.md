# Terraform

Copied from the private `clarity-platform` repo, which CI applies to production. Identifiers (subscription, tenant, GitHub org/repo IDs, Key Vault name) come from variables there and are not included here.

| Path | What it is |
|---|---|
| `root-structure.tf` | Excerpt of the root module: resource groups and how networking, Key Vault and Postgres are wired. Not standalone. |
| `modules/networking` | VNet, delegated subnets, NSGs, private DNS zones |
| `modules/keyvault` | Key Vault in RBAC mode and its private endpoint |
| `modules/cicd-identity` | GitHub Actions OIDC identity scoped to Clarity's resource groups |
