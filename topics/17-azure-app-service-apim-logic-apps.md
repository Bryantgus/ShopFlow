# 17 — Azure: App Service, API Management and Logic Apps

> **Time:** 5 h · **Job requirement:** Azure App Services, API Management, Logic Apps (and Functions from topic 16) · **Builds on:** 14, 15, 16 · **Branch:** `feature/17-azure`

## Why it matters

The job lists four Azure services as desirable. Here ShopFlow leaves your machine: the API images run on **App Service**, the Functions app runs in Azure, **API Management** becomes the single front door with JWT validation and rate limits, and a **Logic App** emails each invoice to the customer. Secrets live in **Key Vault**, read with **Managed Identity**, and **Application Insights** shows the traces.

> **Cost control first.** Create everything in one resource group, `rg-shopflow-dev`, use the smallest tiers, set a **budget alert** on your subscription, and delete the resource group when you finish practicing (`az group delete -n rg-shopflow-dev`). Check current prices and free offers before you create anything.

---

## Learn

### The services and why each one is here

| Service | What it is | In ShopFlow |
| --- | --- | --- |
| App Service | Managed hosting (PaaS) for web apps and APIs, from code or containers | The three APIs, as containers |
| App Service Plan | The machines your apps run on; the tier sets size, price and features | One Linux plan shared by the three APIs |
| Azure Container Registry | Private Docker registry | Your images, pushed by the pipeline |
| Azure Functions | Event-driven, serverless code | `GenerateInvoice`, `DailySalesReport` |
| API Management (APIM) | API gateway: one front door with policies, products, keys and a developer portal | Routes `/catalog`, `/orders`, `/inventory` to the APIs |
| Logic Apps | Low-code workflows with hundreds of connectors | Email the invoice when it lands in Blob Storage |
| Service Bus | Managed messaging | The real `shopflow-events` topic (Standard tier) |
| Key Vault | Secrets, keys and certificates | Connection strings and the JWT signing key |
| Managed Identity | An identity Azure gives your app, so it needs no password to reach Key Vault, ACR, Storage… | Each App Service and the Functions app |
| Application Insights | Monitoring: requests, failures, dependencies, traces, logs | All services |

### App Service essentials

| Concept | Know this |
| --- | --- |
| Tiers | Free/Basic for practice; **deployment slots and autoscale need Standard or higher** |
| Deployment slots | Deploy to `staging`, test, then **swap** to production with no downtime; swap back to roll back |
| App settings | Environment variables for your app; override `appsettings.json`; `__` for nested keys |
| Key Vault references | An app setting whose value is `@Microsoft.KeyVault(SecretUri=…)`: App Service reads the secret with the app's Managed Identity |
| Scale up / scale out | Bigger machine / more instances (manual or rules) |
| Always On | Keeps the app warm (Basic and higher) |
| Health check path | App Service stops sending traffic to an instance that fails `/health` |
| Logs | Log stream, Application Insights |

### API Management essentials

| Concept | Meaning |
| --- | --- |
| API | Imported from an OpenAPI document; operations map to your endpoints |
| Backend | The real service URL behind an API |
| Product | A bundle of APIs consumers subscribe to |
| Subscription key | `Ocp-Apim-Subscription-Key` header identifying the consumer |
| Policies | XML rules at four stages: `inbound`, `backend`, `outbound`, `on-error`; scopes: global → product → API → operation |
| Versions / revisions | Breaking vs non-breaking changes of an API |
| Tiers | Consumption (serverless, pay per call) for practice; Developer/Basic/Standard/Premium (and v2 tiers) for more features. Not every policy exists in every tier: check the policy's docs |

```xml
<policies>
  <inbound>
    <base />
    <set-header name="X-Correlation-ID" exists-action="skip">
      <value>@(context.RequestId.ToString())</value>
    </set-header>
    <rate-limit calls="60" renewal-period="60" />
  </inbound>
  <backend><base /></backend>
  <outbound>
    <base />
    <set-header name="X-Powered-By" exists-action="delete" />
  </outbound>
  <on-error><base /></on-error>
</policies>
```

### Logic Apps essentials

- A **trigger** then **actions**, built in a visual designer (stored as JSON).
- Consumption (multi-tenant, pay per action) vs Standard (single-tenant, runs on its own plan, can run locally in VS Code).
- **Logic Apps vs Functions:** connecting systems with ready-made connectors and little code → Logic Apps; custom logic in C# → Functions. They call each other easily.

### Infrastructure as Code (know the idea)

Creating resources by clicking isn't repeatable. **Bicep** (Azure's language), ARM templates or Terraform describe resources in files that live in Git and run from the pipeline. Bonus task below.

---

## Build

### Plan of resources (`rg-shopflow-dev`)

| Resource | Suggested tier | For |
| --- | --- | --- |
| Container Registry | Basic | Images |
| App Service Plan (Linux) | B1 (Standard if you want to try slots) | 3 API apps |
| Web App for Containers × 3 | — | `app-shopflow-orders`, `-catalog`, `-inventory` (add a unique suffix) |
| Azure SQL Database | Serverless / free offer | Orders |
| MongoDB | MongoDB Atlas free cluster, or Azure Cosmos DB for MongoDB (check its current free tier) | Catalog and reports |
| Oracle | See the options below | Inventory |
| Service Bus | **Standard** (topics) | `shopflow-events` + 4 subscriptions |
| Storage Account | Standard LRS | Functions runtime + `invoices` container |
| Function App | Flex Consumption | `func-shopflow` |
| Key Vault | Standard | Secrets |
| Application Insights + Log Analytics | Pay as you go | Monitoring |
| API Management | Consumption | Front door |
| Logic App | Consumption | Invoice emails |

**Oracle in the cloud — choose one and explain why in your README:**
1. **Oracle Cloud "Always Free" Autonomous Database** (a different cloud): free, real Oracle; your Inventory API connects to it over TLS.
2. Run the `gvenzl/oracle-free` container in Azure (Container Instances or Container Apps): simple but costs money while it runs (it needs several GB of memory).
3. Keep Inventory local and deploy the other two services: honest and fine for a portfolio, as long as you can explain the trade-off.

### Tasks

- [ ] ⭐ Install the Azure CLI, `az login`, create the resource group and a **budget alert**.
- [ ] ⭐ Create the ACR. Create the Azure Pipelines service connection to it, set `pushImages = true`, and let the `Images` stage from topic 15 push your three images.
- [ ] ⭐ Create the databases, Service Bus (same topic, subscriptions and filters as `Config.json`), Storage (`invoices` container) and Key Vault. Run your SQL Server migrations + seed and your MongoDB scripts against the cloud databases.
- [ ] ⭐ Create the App Service Plan and the three apps from your ACR images:
  - Turn on a **system-assigned Managed Identity** on each app; give it `AcrPull` on the registry and **Key Vault Secrets User** on the vault (Azure RBAC).
  - Put every secret in Key Vault and reference it from app settings with `@Microsoft.KeyVault(SecretUri=…)`.
  - Set `ASPNETCORE_ENVIRONMENT=Production`, `Database__MigrateOnStartup=false`, the health check path `/health`, and `WEBSITES_PORT=8080`.
  - Connect Application Insights.
- [ ] Prove the dev token endpoint from topic 11 returns 404 in Azure (Production). To call the APIs, generate tokens locally with the same signing key, or (better, bonus) switch the APIs to accept tokens from **Microsoft Entra ID**.
- [ ] ⭐ Deploy `ShopFlow.Functions` to the Function App (`func azure functionapp publish func-shopflow`, or a pipeline stage). Use Managed Identity + Key Vault references for its settings too.
- [ ] ⭐ **API Management:**
  - Import the three APIs from their OpenAPI documents with URL suffixes `catalog`, `orders`, `inventory`.
  - A product `ShopFlow Public` that contains all three and requires a subscription key.
  - Global policy: add the correlation ID header, remove server headers, and a rate limit.
  - Orders and Inventory APIs: a `validate-jwt` policy that checks issuer, audience and signature **at the gateway**, before the request reaches App Service. (With a symmetric key, use `issuer-signing-keys` with the key in an APIM **named value** backed by Key Vault.)
  - Catalog API: a short `cache-lookup` / `cache-store` for `GET /api/products` (if your tier supports it).
  - Save every policy XML in `deploy/azure/apim/` so it's in Git.
- [ ] Restrict the App Services so they only accept traffic from APIM (access restrictions), and explain why the gateway alone isn't enough without it.
- [ ] ⭐ **Logic App (Consumption):** trigger *"When a blob is added or modified"* on `invoices` → read the blob's metadata (`customerEmail`, `orderId`) → *Send an email* (Outlook.com or Gmail connector, to **your own** address while testing) with the invoice attached → (optional) post a message to a Teams channel. Export the workflow definition JSON to `deploy/azure/logic-app/`.
- [ ] Try a **deployment slot** (needs Standard): deploy a change to `staging` on Orders, check it, swap. Then downgrade the plan again.
- [ ] Bonus: describe the core resources in `deploy/azure/main.bicep` and deploy them with `az deployment group create`.
- [ ] ⭐ Update your project README with the Azure architecture diagram, the URL of the APIM gateway, and a section *"What I'd do for production"* (private endpoints, Entra ID, autoscale, alerts, Bicep in the pipeline, separate dev/prod subscriptions).

---

## Check yourself

- Through the **APIM URL** with a subscription key and a token: place an order, see it confirmed, and receive the invoice email from the Logic App.
- Without the subscription key → 401 from APIM; with a tampered token → 401 from APIM, and App Service never sees the request.
- Application Insights → Transaction search: one order shows the request in APIM, the call to Orders, the call to Catalog and the Service Bus messages.
- No secret appears in any App Service setting value: only Key Vault references.
- The `DailySalesReport` function ran at 10:00 UTC and saved a document.

---

## Interview questions

1. App Service vs Azure Functions vs Container Apps vs AKS: when would you choose each?
2. What are deployment slots for? Which tier do they need?
3. What is a Managed Identity, and why is it better than a connection string with a password?
4. How does an app read Key Vault secrets without code changes?
5. What does API Management give you that your API doesn't have already?
6. Name four APIM policies and where they run (inbound/outbound).
7. Logic Apps vs Functions?
8. How do you keep Azure costs under control while learning?
9. What is Infrastructure as Code? Bicep vs ARM vs Terraform?

Answers: [interview question bank](99-interview-questions.md#17--app-service-api-management-logic-apps).

---

## Done when

- [ ] An order placed through APIM ends with an invoice email.
- [ ] All secrets come from Key Vault via Managed Identity.
- [ ] `deploy/azure/` holds the APIM policies and the Logic App definition.
- [ ] Pull request into `develop` merged, and the resource group deleted or scaled down.
