# 16 — Azure Functions

> **Time:** 4 h · **Job requirement:** Azure Functions · **Builds on:** 12, 14 · **Branch:** `feature/16-functions`

## Why it matters

Functions handle the work that shouldn't slow down an API: reacting to events and running on a schedule. In ShopFlow you write two: one creates an **invoice** when an order is confirmed (Service Bus trigger → Blob Storage), and one builds a **daily report** from the Orders and Inventory APIs (timer trigger → MongoDB). You run both locally first; topic 17 deploys them.

---

## Learn

### Triggers and bindings

| Piece | Meaning | Examples |
| --- | --- | --- |
| Trigger | What starts the function (exactly one) | HTTP, Timer, Service Bus, Storage Queue, Blob, Event Grid, Cosmos DB |
| Input binding | Data read for you | A blob, a table row |
| Output binding | Data written for you | A blob, a queue message, a Service Bus message |

### Isolated worker model

Your functions run in **their own process**, as a normal .NET app with `Program.cs`, middleware and dependency injection. It's the only model going forward: support for the old in-process model ends on November 10, 2026, and .NET 10 is supported on the isolated model.

```csharp
// Program.cs
var builder = FunctionsApplication.CreateBuilder(args);
builder.Services.AddHttpClient();
builder.Build().Run();

public class Cleanup(ILogger<Cleanup> log)
{
    [Function("NightlyCleanup")]
    public void Run([TimerTrigger("0 30 3 * * *")] TimerInfo timer)       // second minute hour day month weekday (UTC)
        => log.LogInformation("Next run: {Next}", timer.ScheduleStatus?.Next);
}

public class Thumbnails
{
    [Function("MakeThumbnail")]
    [BlobOutput("thumbs/{name}")]                                           // output binding: return value is written
    public byte[] Run([BlobTrigger("uploads/{name}")] byte[] image, string name) => Resize(image);
}
```

Note: Timer CRON in Functions has **six** fields (it starts with seconds), and runs in **UTC** unless you set the `WEBSITE_TIME_ZONE` app setting (supported on some plans only).

### Hosting plans

| Plan | Scales to zero | Cold start | Use for |
| --- | --- | --- | --- |
| Flex Consumption | Yes | Reduced (always-ready instances optional) | The recommended serverless plan for new apps |
| Consumption (classic) | Yes | Yes | Older apps |
| Premium | No (pre-warmed) | No | Long runs, VNet, no cold starts |
| Dedicated (App Service plan) | No | No | You already pay for a plan |

### Durable Functions (know the idea)

Stateful workflows in code: an **orchestrator** calls **activities** and can wait for events, timers or human approval. Patterns: function chaining, fan-out/fan-in, async HTTP APIs, human interaction. It's the **orchestration** style of saga from topic 12.

### Local development

- **Azure Functions Core Tools:** `func init --worker-runtime dotnet-isolated`, `func new`, `func start`.
- **Azurite:** the local Storage emulator (Blob, Queue, Table). Functions need a storage account (`AzureWebJobsStorage`); locally it's `UseDevelopmentStorage=true`.
- **`local.settings.json`:** local app settings. Never commit it.
- Bindings are **at-least-once** too: make functions idempotent.

---

## Build: `ShopFlow.Functions`

Create `src/Functions/ShopFlow.Functions` (isolated worker, .NET 10) and add it to the solution. Reference `ShopFlow.Contracts`.

### Function 1 — `GenerateInvoice`

| Item | Value |
| --- | --- |
| Trigger | Service Bus topic `shopflow-events`, subscription `functions-sub` (receives `OrderConfirmed`) |
| Output | Blob `invoices/{orderId}.pdf` (or `.html` if you skip the PDF library) |
| Blob metadata | `customerEmail`, `orderId` (the Logic App in topic 17 reads them) |

- [ ] ⭐ Deserialize the message body into `OrderConfirmed`.
- [ ] ⭐ Build the invoice: ShopFlow's name, invoice number `INV-{orderId:D6}`, date, customer email, a table of lines (SKU, name, quantity, unit price, line total), subtotal, total, currency.
  - Simple version: an HTML document built with a `StringBuilder` or a raw string literal.
  - Better version: a PDF with **QuestPDF** (free under its community license for small companies and individuals; read the license).
- [ ] ⭐ Write the blob with the **Azure Storage SDK** (`BlobContainerClient`, registered in DI) rather than an output binding, so you can set **metadata** and content type. Overwrite if it exists: the same order always produces the same file name, which makes the function idempotent.
- [ ] A malformed message must end in the dead-letter queue, not loop forever. Decide how (let it throw after logging, and rely on `MaxDeliveryCount`), and write it down.

### Function 2 — `DailySalesReport`

| Item | Value |
| --- | --- |
| Trigger | Timer, every day at 06:00 Santo Domingo time = `0 0 10 * * *` (UTC) |
| Reads | `GET /api/reports/sales?from=…&to=…` on Orders (yesterday), `GET /api/stock/low` on Inventory |
| Writes | One document per day into MongoDB database `shopflow_reports`, collection `daily_reports` |

- [ ] ⭐ Two typed `HttpClient`s with base URLs from settings, `AddStandardResilienceHandler()`, and a bearer token for the `Service` role (topic 11). Locally, generate a long-lived development token and store it in `local.settings.json`; write a comment on what replaces it in Azure (Managed Identity + Entra ID, or calling through API Management with a subscription key).
- [ ] ⭐ Call both APIs **in parallel** (`Task.WhenAll`).
- [ ] ⭐ Save `{ _id: "2026-10-28", generatedAt, sales: {…}, topSkus: […], lowStock: […] }`. Using the **date as `_id`** with an upsert (`ReplaceOneAsync` with `IsUpsert = true`) makes reruns safe.
- [ ] If one API fails, still save the report with what you have plus an `errors` array, and log a warning. Decide whether the function should fail (and retry) or succeed; justify it.
- [ ] For testing, run it on demand: Core Tools lets you call a non-HTTP function through the admin endpoint (`POST http://localhost:7071/admin/functions/DailySalesReport` with body `{ "input": "" }`), or set `RunOnStartup = true` **only** locally.

### Function 3 (optional) — `GetInvoiceLink`

- [ ] HTTP trigger `GET /api/invoices/{orderId}` (Admin or the order's owner) that returns a **SAS URL** valid for 15 minutes to download the invoice. Explain why you hand out a short-lived link instead of making the container public.

### Local setup

- [ ] ⭐ Run Azurite (from your compose `infra` profile), create the `invoices` container, and fill `local.settings.json`: `AzureWebJobsStorage`, `FUNCTIONS_WORKER_RUNTIME=dotnet-isolated`, `ServiceBus` (the `Connection` name in your trigger), `InvoicesStorage`, `ReportsMongo`, the API base URLs and the token.
- [ ] Add `local.settings.json` to `.gitignore` and commit a `local.settings.example.json` with empty values.
- [ ] Add a Dockerfile for the Functions app (base image `mcr.microsoft.com/azure-functions/dotnet-isolated:4-dotnet-isolated10.0` or the current equivalent; check the tag) and a `functions` service in compose under the `apps` profile.

---

## Check yourself

- Confirm an order through the saga → within seconds `invoices/{id}.pdf` (or `.html`) appears in Azurite (look with Azure Storage Explorer or the VS Code Azure Storage extension), with the metadata set.
- Re-send the same `OrderConfirmed` → the same blob is overwritten, not duplicated.
- Trigger `DailySalesReport` by hand twice → one document for that date in `shopflow_reports.daily_reports`.
- Stop Inventory and trigger the report → it's saved with an `errors` entry.

---

## Interview questions

1. What are triggers and bindings? Give examples.
2. Isolated worker vs in-process model? Why does it matter now?
3. Consumption / Flex Consumption vs Premium vs Dedicated?
4. What is a cold start, and how do you reduce it?
5. How do you make a Service Bus–triggered function idempotent?
6. What is Durable Functions for?
7. Functions vs a `BackgroundService` in your API: how do you choose?
8. How do you run and test Functions locally?

Answers: [interview question bank](99-interview-questions.md#16--azure-functions).

---

## Done when

- [ ] Both functions work locally against the emulators and the running APIs.
- [ ] No settings file with secrets is committed.
- [ ] Pull request into `develop` merged.
