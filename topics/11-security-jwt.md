# 11 — Security: JWT, policies, CORS and rate limiting

> **Time:** 3 h · **Job requirement:** not listed, but asked in almost every interview · **Builds on:** 08, 09, 10 · **Branch:** `feature/11-security`

## Why it matters

No company ships an API without authentication, so interviewers always ask about it: 401 vs 403, how JWT works, roles vs policies, CORS. In ShopFlow you secure all three APIs with the same token, give each role only what it needs, make sure a customer can only see **their own** orders, and limit how fast anyone can place orders.

---

## Learn

### Authentication vs authorization

| | Question | Fails with |
| --- | --- | --- |
| Authentication | *Who are you?* | 401 Unauthorized |
| Authorization | *Are you allowed to do this?* | 403 Forbidden |

### JWT (JSON Web Token)

- Three Base64Url parts: `header.payload.signature`. The payload holds **claims**: `sub` (user id), `name`, `role`, `exp` (expiry), `iss` (issuer), `aud` (audience), plus your own (`customer_id`).
- **Signed, not encrypted.** Anyone can read it (paste one into jwt.io); nobody can change it without the key. Never put secrets in it.
- **Stateless:** the API only checks the signature and the claims; no session lookup.
- Symmetric signing (HMAC, one shared secret) is simple; asymmetric (RSA/ECDSA: the issuer signs with a private key, APIs verify with the public key) is what identity providers use.
- Short-lived access tokens (minutes) + refresh tokens to get new ones.

```csharp
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o => o.TokenValidationParameters = new()
    {
        ValidateIssuer = true,            ValidIssuer = jwt.Issuer,
        ValidateAudience = true,          ValidAudience = jwt.Audience,
        ValidateLifetime = true,          ClockSkew = TimeSpan.FromSeconds(30),
        ValidateIssuerSigningKey = true,  IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.SigningKey))
    });
```

### Where tokens come from in real systems

| Flow (OAuth 2.0 / OpenID Connect) | Used by |
| --- | --- |
| Authorization Code + PKCE | Web and mobile apps with a user (your Angular or React app) |
| Client Credentials | Service-to-service, no user |
| Refresh token | Get a new access token without logging in again |

Issuers: Microsoft Entra ID, Auth0, Keycloak, Duende IdentityServer… ShopFlow uses a **development-only** token endpoint so you can focus on the API side. Say that clearly in interviews.

### Three levels of authorization

```csharp
[Authorize]                                    // any authenticated user
[Authorize(Roles = "Admin")]                   // role-based
[Authorize(Policy = "CanManageStock")]         // policy: roles, claims or custom requirements

builder.Services.AddAuthorizationBuilder()
    .AddPolicy("CanManageStock", p => p.RequireRole("Warehouse", "Admin"));
```

**Resource-based** authorization checks the user **against a specific object** (is this the owner of this order?). The resource isn't known until you load it, so you call `IAuthorizationService.AuthorizeAsync(User, resource, requirement)` inside the action:

```csharp
public sealed class DocumentOwnerRequirement : IAuthorizationRequirement;

public sealed class DocumentOwnerHandler : AuthorizationHandler<DocumentOwnerRequirement, DocumentDto>
{
    protected override Task HandleRequirementAsync(AuthorizationHandlerContext ctx,
        DocumentOwnerRequirement req, DocumentDto doc)
    {
        if (ctx.User.IsInRole("Admin") || ctx.User.FindFirstValue("sub") == doc.OwnerId)
            ctx.Succeed(req);
        return Task.CompletedTask;
    }
}
```

### CORS

A **browser** rule: a page from `http://localhost:4200` can't call `http://localhost:5102` unless the API allows that origin. CORS doesn't protect your API from Postman or other servers; it protects users' browsers.

```csharp
builder.Services.AddCors(o => o.AddPolicy("Frontend",
    p => p.WithOrigins("http://localhost:4200").AllowAnyHeader().AllowAnyMethod()));
```

### Rate limiting (built in since .NET 7)

```csharp
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    o.AddPolicy("per-user", ctx => RateLimitPartition.GetFixedWindowLimiter(
        ctx.User.Identity?.Name ?? ctx.Connection.RemoteIpAddress?.ToString() ?? "anon",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 10, Window = TimeSpan.FromMinutes(1) }));
});
app.UseRateLimiter();
```

### Other things they ask

- Secrets: user secrets in development; Key Vault in Azure (topic 17); never in the repository.
- HTTPS everywhere, HSTS in production.
- OWASP API risks: broken object-level authorization (exactly what resource-based checks fix), broken authentication, excessive data exposure (DTOs fix it), lack of rate limiting, injection.

---

## Build

### Shared code: `ShopFlow.ServiceDefaults`

All three APIs need the same authentication, ProblemDetails, correlation ID and health checks. Don't copy them three times.

- [ ] ⭐ Create `src/BuildingBlocks/ShopFlow.ServiceDefaults` (class library with `<FrameworkReference Include="Microsoft.AspNetCore.App" />`) and reference it from the three APIs.
- [ ] ⭐ Move `GlobalExceptionHandler` and `CorrelationIdMiddleware` there, and write:
  - `AddServiceDefaults(this WebApplicationBuilder)`: ProblemDetails, exception handler, JWT authentication from a `"Jwt"` section (`Issuer`, `Audience`, `SigningKey` of at least 32 characters, validated on start), authorization, health checks, CORS policy `"Frontend"`.
  - `UseServiceDefaults(this WebApplication)`: the middleware in the right order, and `/health`.
  - A `ClaimTypes`-style static class with ShopFlow's claim names (`customer_id`) and role names (`Customer`, `Admin`, `Warehouse`, `Service`).
- [ ] Each API's `Program.cs` should now be short: `AddServiceDefaults()`, its own services, `UseServiceDefaults()`, its endpoints.

### Development token endpoint (Orders.Api, Development only)

- [ ] ⭐ `POST /api/dev/token` with body `{ "userName": "ana", "roles": ["Customer"], "customerId": 3 }` returns a signed JWT valid for 60 minutes. Map it **only** when `app.Environment.IsDevelopment()`, and write a comment on what replaces it in production.

### Rules per API

**Orders**

| Endpoint | Who |
| --- | --- |
| `POST /api/orders` | `Customer` (the customer Id comes **from the token**, not the body) or `Admin` (may order for any customer by passing `customerId`) |
| `GET /api/orders/{id}` | The owner, or `Admin` — **resource-based** |
| `GET /api/customers/{customerId}/orders` | Same customer as the token, or `Admin` |
| `POST /api/orders/{id}/cancel` | The owner, or `Admin` |
| `GET /api/reports/sales` | `Admin` or `Service` |

**Catalog** — all `GET`s are anonymous (Orders reads prices without a user); `POST`/`PUT`/`DELETE` products need `Admin`; posting a review needs `Customer`.

**Inventory** — everything needs `Warehouse` or `Admin`, except `GET /api/stock/low`, which also allows `Service` (the Azure Function in topic 16).

### Tasks

- [ ] ⭐ Change `PlaceOrderRequest` so customers don't send their own `customerId`; read it from the `customer_id` claim. Explain in your pull request which OWASP risk this prevents.
- [ ] ⭐ Write `OrderOwnerRequirement` and its handler; use them in the order details and cancel actions. A customer asking for someone else's order gets **404, not 403**. Write a comment explaining why (hint: don't confirm that the order exists).
- [ ] Apply the policies in the three APIs (`[Authorize(Policy = …)]` on controllers, `.RequireAuthorization(…)` on minimal API groups, `.AllowAnonymous()` for public reads).
- [ ] ⭐ Add the per-user rate limiter to `POST /api/orders` (10 per minute); it must return 429 with ProblemDetails.
- [ ] Add the security scheme to OpenAPI so the UI has an "Authorize" button for a bearer token.
- [ ] Put the `Jwt` settings in user secrets for each API (same values), and document the setting names in your project README (not the values).
- [ ] Update every `.http` file: get a token first, save it in a variable, and use it in the requests.

---

## Check yourself

| Request | Expected |
| --- | --- |
| Any Orders endpoint with no token | 401 |
| Customer 3 reads customer 3's order | 200 |
| Customer 3 reads customer 5's order | 404 |
| Customer token on `GET /api/reports/sales` | 403 |
| Anonymous `GET` on Catalog products | 200 |
| Anonymous `POST` on Catalog products | 401 |
| `Warehouse` token on `POST /api/stock/receipts` | 204 |
| 11 orders in one minute with the same user | the 11th gets 429 |
| An expired or tampered token | 401 |
| `POST /api/dev/token` with `ASPNETCORE_ENVIRONMENT=Production` | 404 |

---

## Interview questions

1. Authentication vs authorization? 401 vs 403?
2. How does JWT work? Is the payload secret?
3. Symmetric vs asymmetric signing?
4. Roles vs claims vs policies vs resource-based authorization?
5. Which OAuth 2.0 flow fits a SPA? A background service?
6. What is CORS, and what doesn't it protect against?
7. What is broken object-level authorization, and how did you prevent it?
8. How do you limit abusive clients?
9. Where do you keep secrets in development and in production?

Answers: [interview question bank](99-interview-questions.md#11--security-jwt-policies-cors).

---

## Done when

- [ ] Every row in the "Check yourself" table behaves as expected.
- [ ] The three `Program.cs` files use `AddServiceDefaults` / `UseServiceDefaults`.
- [ ] Pull request into `develop` merged.
