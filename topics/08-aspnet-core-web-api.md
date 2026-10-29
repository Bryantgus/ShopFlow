# 08 — ASP.NET Core Web API

> **Time:** 5 h · **Job requirement:** .NET Core 6+ · **Builds on:** 07 · **Branch:** `feature/08-web-apis`

## Why it matters

This is the core of the job. Expect questions on the middleware pipeline, dependency injection lifetimes, controllers vs minimal APIs, and error handling. In ShopFlow you build two APIs in the two styles: **Orders** with controllers (the classic style most companies have) and **Catalog** with minimal APIs (the modern default). Both start with in-memory fakes, so you see Dependency Inversion pay off when you plug in real databases in topics 09 and 10.

---

## Learn

### Program.cs in two halves

```csharp
var builder = WebApplication.CreateBuilder(args);

// 1. Register services (the DI container)
builder.Services.AddControllers();
builder.Services.AddOpenApi();
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
builder.Services.AddScoped<IWidgetService, WidgetService>();

var app = builder.Build();

// 2. Build the middleware pipeline (ORDER MATTERS)
app.UseExceptionHandler();
app.UseHttpsRedirection();
app.UseCors();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapOpenApi();
app.Run();
```

### The middleware pipeline

Each middleware gets the request, may do work, calls `next`, and sees the response on the way back, in reverse order. The exception handler goes first so it can catch errors from everything after it; authentication must run before authorization.

```csharp
app.Use(async (context, next) =>
{
    var sw = Stopwatch.StartNew();
    await next(context);
    app.Logger.LogInformation("{Method} {Path} -> {Status} in {Ms} ms",
        context.Request.Method, context.Request.Path, context.Response.StatusCode, sw.ElapsedMilliseconds);
});
```

### Dependency injection lifetimes

| Lifetime | One instance per… | Typical use |
| --- | --- | --- |
| Singleton | Application | Caches, clients that are thread-safe (`MongoClient`, `ServiceBusClient`) |
| Scoped | HTTP request | `DbContext`, repositories, handlers |
| Transient | Every resolution | Small stateless helpers |

**Captive dependency:** a Singleton that receives a Scoped service keeps the first instance forever. In Development, ASP.NET Core detects it at startup. If a singleton really needs scoped services, it creates a scope with `IServiceScopeFactory` (you'll do this in topic 12).

### Controllers vs minimal APIs

```csharp
// Controller
[ApiController]
[Route("api/[controller]")]
public class BooksController(IBookService books) : ControllerBase
{
    [HttpGet("{id:int}")]
    public async Task<ActionResult<BookDto>> Get(int id, CancellationToken ct)
        => await books.FindAsync(id, ct) is { } b ? Ok(b) : NotFound();
}

// Minimal API with a route group and typed results
var group = app.MapGroup("/api/books").WithTags("Books");
group.MapGet("/{id:int}", async Task<Results<Ok<BookDto>, NotFound>> (int id, IBookService books, CancellationToken ct)
    => await books.FindAsync(id, ct) is { } b ? TypedResults.Ok(b) : TypedResults.NotFound());
```

| | Controllers | Minimal APIs |
| --- | --- | --- |
| Shape | Classes, attributes, action filters | Lambdas or static methods, route groups, endpoint filters |
| Strength | Familiar, lots of existing code | Less ceremony, slightly faster, the default in new templates |
| Validation | `[ApiController]` returns 400 automatically | Endpoint filter, or built-in validation in .NET 10 (`AddValidation()`) |

### Model binding

`[FromRoute]`, `[FromQuery]`, `[FromBody]`, `[FromHeader]`, `[FromServices]`, `[AsParameters]` (minimal APIs: bind a record from several sources). Route constraints: `{id:int}`, `{sku:regex(...)}`, `{page:int:min(1)}`.

### Errors the standard way: ProblemDetails

`AddProblemDetails()` + `IExceptionHandler` turn unhandled exceptions into RFC 9457 JSON with `type`, `title`, `status`, `detail`, `instance` and your own extensions (like an error `code` and the `traceId`). For **expected** failures (your `Result` errors), return ProblemDetails yourself with the right status code.

### Configuration and the Options pattern

Sources, last one wins: `appsettings.json` → `appsettings.{Environment}.json` → user secrets (Development) → environment variables (`Catalog__BaseUrl` maps to `Catalog:BaseUrl`) → command line.

```csharp
builder.Services.AddOptions<SmtpOptions>()
    .Bind(builder.Configuration.GetSection("Smtp"))
    .ValidateDataAnnotations()
    .ValidateOnStart();          // fail fast at startup, not at the first email
```

`IOptions<T>` reads once · `IOptionsSnapshot<T>` re-reads per request · `IOptionsMonitor<T>` notifies on change.

### HTTP you must get right

| Verb | Use | Idempotent |
| --- | --- | --- |
| GET | Read | Yes |
| POST | Create / start an action | No |
| PUT | Replace | Yes |
| PATCH | Partial update | Not necessarily |
| DELETE | Remove | Yes |

Status codes: 200 OK · 201 Created + `Location` header · 204 No Content · 400 Bad Request · 401 Unauthorized · 403 Forbidden · 404 Not Found · 409 Conflict · 422 Unprocessable Entity · 429 Too Many Requests · 500 Internal Server Error · 503 Service Unavailable.

### OpenAPI

Since .NET 9, templates use `Microsoft.AspNetCore.OpenApi` (`AddOpenApi()` / `MapOpenApi()`) instead of Swashbuckle. For a UI, add a package such as Scalar (`MapScalarApiReference()`) in Development only.

---

## Build part 1: `ShopFlow.Orders.Api` (controllers)

For now the API runs **with fakes**: in-memory implementations of the Application ports in a `DevFakes/` folder. Topic 09 replaces them with SQL Server, and only the registration lines in `Program.cs` change.

### Endpoints

| Method and route | Use case | Success | Errors |
| --- | --- | --- | --- |
| `POST /api/orders` | `PlaceOrderCommand` | 201 + `Location` + `{ "id": 16 }` | 400, 404 |
| `GET /api/orders/{id:int}` | `GetOrderByIdQuery` | 200 `OrderDetailsDto` | 404 |
| `GET /api/customers/{customerId:int}/orders?page=1&pageSize=10` | `GetCustomerOrdersQuery` | 200 `PagedResult<OrderSummaryDto>` | 400 |
| `POST /api/orders/{id:int}/cancel` | `CancelOrderCommand` (body `{ "reason": "..." }`) | 204 | 404, 409 |
| `GET /api/reports/sales?from=2026-10-01&to=2026-10-31` | `GetSalesReportQuery` | 200 `SalesReportDto` | 400 |
| `POST /api/orders/{id:int}/confirm` and `/reject` | Confirm / Reject | 204 | 404, 409 |
| `GET /health` | Health checks | 200 `Healthy` | 503 |

The `confirm` and `reject` endpoints are **temporary**: in topic 12 these transitions happen through events from Inventory, and you delete both endpoints.

### Tasks

- [ ] ⭐ Write the request records (`PlaceOrderRequest`, `CancelOrderRequest`) — don't expose the commands directly as the API contract. Explain in a comment why.
- [ ] ⭐ Write `OrdersController`, `CustomerOrdersController` and `ReportsController`. Controllers only translate HTTP ↔ use case: no business logic, no `try/catch`.
- [ ] ⭐ Write `ResultExtensions.ToActionResult()` (and a version for `Result<T>`) that maps `ErrorType` to status codes (`Validation → 400`, `NotFound → 404`, `Conflict → 409`, `Failure → 500`) and returns ProblemDetails with the error `code` as an extension.
- [ ] ⭐ Write `GlobalExceptionHandler : IExceptionHandler`: `DomainException` → 409 with its code; anything else → 500 with a generic message (never the exception text) and the `traceId`. Log the exception.
- [ ] Write `CorrelationIdMiddleware`: read `X-Correlation-ID` from the request or create a new one, put it in the response header, and open a logging scope with it so every log line of the request carries it. (Topic 12 sends it to Service Bus.)
- [ ] Add `CatalogOptions` (`BaseUrl`, `TimeoutSeconds` between 1 and 30) bound to `"Catalog"` with validation on start. Nothing uses it yet; topic 12's HTTP client does.
- [ ] ⭐ Write the fakes in `DevFakes/`: an in-memory order repository/read service (a static list seeded with a few orders), a customer repository with 3 customers, a catalog client that returns the 10 shared products (mark one as inactive), and a unit of work that does nothing.
- [ ] ⭐ Register everything: `AddApplication()`, the fakes, `AddProblemDetails()`, the exception handler, health checks, OpenAPI and a UI in Development.
- [ ] Write `ShopFlow.Orders.Api.http` with a request for every endpoint, including failing ones.

## Build part 2: `ShopFlow.Catalog.Api` (minimal APIs)

Catalog is small, so one project with folders: `Products/` (model, DTOs, validators, endpoints), `Data/` (repository interface and implementations).

### Endpoints (group `/api/products`)

| Method and route | Does | Success |
| --- | --- | --- |
| `GET /` | Filter by `category`, `search` (in name or brand), `minPrice`, `maxPrice`; page with `page`, `pageSize` | 200 `PagedResult<ProductSummaryDto>` |
| `GET /{sku}` | One product with all its attributes | 200 / 404 |
| `GET /lookup?skus=MON-LG-24,HUB-USBC-7` | Name, price and `isActive` for many SKUs at once (**the Orders service calls this**) | 200 list; unknown SKUs are left out |
| `POST /` | Create a product | 201 / 400 / 409 if the SKU exists |
| `PUT /{sku}` | Update name, price, category, attributes, tags | 204 / 400 / 404 |
| `DELETE /{sku}` | Soft delete: `isActive = false` | 204 / 404 |
| `GET /stats` | Products and average price per category | 200 |

### Tasks

- [ ] ⭐ Write `Product` (with `Attributes` as `Dictionary<string, object>` for now), the DTOs as records, and `IProductRepository`.
- [ ] ⭐ Write `InMemoryProductRepository` (singleton, thread-safe with `ConcurrentDictionary`) seeded with the 10 shared products.
- [ ] ⭐ Map the endpoints with a route group, `TypedResults` and `Results<…>` return types, so OpenAPI knows every possible response.
- [ ] Write a generic endpoint filter `ValidationFilter<T>` that runs the FluentValidation validator for `T` and returns 400 ProblemDetails if it fails. Use it on `POST` and `PUT`. (Then read about .NET 10's built-in `AddValidation()` and write one sentence comparing them.)
- [ ] Put the endpoints in a static class with an extension method `app.MapProductEndpoints()` so `Program.cs` stays short.
- [ ] Add the same `GlobalExceptionHandler` idea, health checks and OpenAPI.

---

## Check yourself

- With both APIs running (`dotnet run` in each; ports 5102 and 5101), every request in your `.http` files returns the documented status code.
- `POST /api/orders` with an inactive SKU → 400 with `code: "order.product_inactive"`.
- `POST /api/orders/{id}/confirm` twice → the second returns 409.
- Throw a test exception in a controller: you get a 500 ProblemDetails **without** the exception message, and the log shows the full exception with the correlation ID.
- `GET /openapi/v1.json` lists every endpoint with all its response codes.

---

## Interview questions

1. What is middleware, and why does the order matter?
2. Singleton vs Scoped vs Transient? What is a captive dependency?
3. Controllers vs minimal APIs?
4. How do you handle errors globally? What is ProblemDetails?
5. `IOptions` vs `IOptionsSnapshot` vs `IOptionsMonitor`?
6. Which configuration source wins, and how do environment variables map to nested keys?
7. What makes an HTTP method idempotent? Which ones are?
8. 401 vs 403? 400 vs 422? When do you return 409?
9. Why shouldn't you expose your domain entities or commands as the API contract?

Answers: [interview question bank](99-interview-questions.md#08--aspnet-core-web-api).

---

## Done when

- [ ] Both APIs run and every endpoint behaves as documented.
- [ ] Controllers and endpoints contain no business logic.
- [ ] Pull request into `develop` merged.
