# 13 — Unit and integration testing

> **Time:** 5 h · **Job requirement:** Unit Testing, Integration Testing · **Builds on:** 05–12 · **Branch:** `feature/13-tests`

## Why it matters

The job lists both kinds of tests, and a mid-level developer is expected to write them without being asked. ShopFlow is a great place to show it: pure domain rules for fast unit tests, and three different databases for real integration tests with Testcontainers.

---

## Learn

### The test pyramid

| Level | Tests | Speed | In ShopFlow |
| --- | --- | --- | --- |
| Unit | One class, dependencies replaced | Milliseconds | Domain, Application handlers, `Result<T>` |
| Integration | Real parts together: API + real database in a container | Seconds | Each API against SQL Server, Oracle or MongoDB |
| End-to-end | The whole system like a user | Minutes | The saga, by hand or with a script (topic 12 checks) |

Many unit tests, fewer integration tests, very few end-to-end tests.

### xUnit basics

```csharp
public class CalculatorTests
{
    [Fact]
    public void Divide_ByZero_Throws()
    {
        var calc = new Calculator();                                   // Arrange
        var act = () => calc.Divide(10, 0);                            // Act
        Assert.Throws<DivideByZeroException>(act);                     // Assert
    }

    [Theory]
    [InlineData(10, 2, 5)]
    [InlineData(9, 3, 3)]
    public void Divide_ReturnsQuotient(int a, int b, int expected)
        => Assert.Equal(expected, new Calculator().Divide(a, b));
}
```

- Name tests `Method_Scenario_ExpectedResult`.
- One behavior per test; arrange, act, assert.
- `[Theory]` with `[InlineData]`, `[MemberData]` or `[ClassData]` for several cases.
- Shared expensive setup: `IClassFixture<T>` (one per test class) or `ICollectionFixture<T>` (shared across classes); async setup with `IAsyncLifetime`.
- Readable assertions: `Shouldly` or `AwesomeAssertions` (a community fork of FluentAssertions, whose newer versions require a paid license for commercial use).

### Test doubles

| Double | What it is |
| --- | --- |
| Stub | Returns canned answers |
| Mock | A stub that also **verifies** how it was called |
| Fake | A working light implementation (an in-memory repository) |
| Spy | Records calls for later inspection |

```csharp
// NSubstitute (Moq works the same way: Mock<T>, Setup, Verify)
var repo = Substitute.For<IInvoiceRepository>();
repo.FindAsync(7, Arg.Any<CancellationToken>()).Returns(new Invoice(7));

await sut.PayAsync(7, CancellationToken.None);

await repo.Received(1).SaveAsync(Arg.Is<Invoice>(i => i.IsPaid), Arg.Any<CancellationToken>());
```

Mock what you **don't own** at the boundary (repositories, HTTP clients, the clock). Don't mock the domain: use the real objects.

### Controlling time

`TimeProvider` (topic 07) has a fake: `Microsoft.Extensions.TimeProvider.Testing` → `FakeTimeProvider`, which you can set and advance.

### Integration tests with WebApplicationFactory and Testcontainers

```csharp
public sealed class ApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly MsSqlContainer _db = new MsSqlBuilder().Build();      // Testcontainers.MsSql

    public async Task InitializeAsync() => await _db.StartAsync();
    public new async Task DisposeAsync() => await _db.DisposeAsync();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.UseSetting("ConnectionStrings:OrdersDb", _db.GetConnectionString());
        builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<IEventBus>();
            services.AddSingleton<IEventBus, RecordingEventBus>();      // a fake that remembers what was published
        });
    }
}
// In Program.cs, so the test project can see it:  public partial class Program;
```

- Prefer a **real** database in a container over EF Core's InMemory provider: InMemory doesn't run SQL, constraints, procedures or transactions.
- Reset data between tests: recreate the database per test class, wrap each test in a transaction, or use the `Respawn` package.
- Testcontainers has modules for SQL Server, Oracle and MongoDB. They need Docker running.

### Authentication in tests

Create a real token with the same signing key (your token code from topic 11), or replace authentication with a test scheme that builds a `ClaimsPrincipal` from a header.

### Coverage

`dotnet test --collect:"XPlat Code Coverage"` (coverlet) creates a report; `reportgenerator` turns it into HTML. Use coverage to find untested code, not as a target: 100 % isn't the goal; testing the rules and the failure paths is.

---

## Build

### Test projects

```text
tests/
├── ShopFlow.Orders.UnitTests/              xUnit + NSubstitute (or Moq)
├── ShopFlow.Orders.IntegrationTests/       + Microsoft.AspNetCore.Mvc.Testing + Testcontainers.MsSql
├── ShopFlow.Catalog.IntegrationTests/      + Testcontainers.MongoDb
└── ShopFlow.Inventory.IntegrationTests/    + Testcontainers.Oracle
```

### Unit tests — `ShopFlow.Orders.UnitTests`

- [ ] ⭐ **Domain** (the checks from topic 05, now as tests):
  - `Money`: adding different currencies throws; negative amounts throw; `*` works.
  - `Sku`: valid values are normalized; invalid values throw with code `sku.invalid` (a `[Theory]` with 5+ cases).
  - `Order`: one test per allowed transition, and a `[Theory]` covering **every** forbidden transition; totals after adding items and a discount; the same SKU twice merges; confirming raises exactly one `OrderConfirmedDomainEvent`.
- [ ] **`Result<T>`**: `Map`, `Bind`, `Match`, reading `Value` of a failure.
- [ ] ⭐ **`PlaceOrderHandler`** with doubles for its ports:
  - Unknown customer → `NotFound`, and the repository is **never** called.
  - Unknown SKU → `Validation` with `order.unknown_sku`.
  - Inactive product → `Validation`.
  - Prices come from the catalog even if they differ from anything else.
  - First order gets 10 % (max 2,000); a large order gets 5 %.
  - Catalog throws `HttpRequestException` → `Failure` with `catalog.unavailable`.
- [ ] `PlaceOrderValidator`: one test per rule.
- [ ] Discount policies and the factory, using `FakeTimeProvider` if any rule depends on dates.
- [ ] `StockReservedHandler`: a duplicate `EventId` doesn't run the command again.

### Integration tests — Orders (SQL Server)

- [ ] ⭐ `ApiFactory` like the example: SQL Server container, apply EF migrations once, run the seed, replace `IEventBus` with a recording fake and `ICatalogClient` with a stub, turn off the `OutboxPublisher` hosted service.
- [ ] ⭐ `POST /api/orders` with a customer token → 201; the database has the order, its lines and one `OrderPlaced` outbox row with valid JSON that deserializes into the `OrderPlaced` contract.
- [ ] `POST /api/orders` with an invalid customer in the procedure path → no rows left behind.
- [ ] Customer A reading customer B's order → 404; Admin → 200; no token → 401.
- [ ] `GET /api/reports/sales` returns the two parts of the report (tests the Dapper multi-result code).
- [ ] Cancel → status `Cancelled` and an `OrderCancelled` outbox row in the same transaction.
- [ ] The `OutboxPublisher` itself: with the recording bus, run one cycle and check the message is published once and marked processed.

### Integration tests — Inventory (Oracle)

- [ ] ⭐ Start an Oracle container, run your scripts `01`–`04` against it (split on `/` lines for PL/SQL), seed a known stock state.
- [ ] `ReserveAsync` success, failure (nothing changed), and idempotency (`ALREADY_RESERVED`).
- [ ] Two parallel `ReserveAsync` calls for the last unit of a SKU: exactly one succeeds. This proves your `SELECT … FOR UPDATE`.
- [ ] `ReleaseAsync` restores `reserved`.
- [ ] The Oracle container is slow to start: share it across the test classes with a collection fixture.

### Integration tests — Catalog (MongoDB)

- [ ] ⭐ MongoDB container; `GET /api/products` filters and paging; `GET /lookup` with known and unknown SKUs; `POST` with an existing SKU → 409.
- [ ] `UpdateAvailabilityAsync` ignores an older event.

### Contract test

- [ ] One test per integration event: serialize → deserialize → equal. And one that deserializes a **hand-written JSON sample** of each event (kept in the test project), so renaming a property breaks a test before it breaks another service.

### Coverage

- [ ] Run the tests with coverage, generate the HTML report, and write in your PR the three least-covered important areas and whether they need tests.

---

## Check yourself

- `dotnet test` at the root runs every project; unit tests finish in a few seconds.
- Integration tests pass on a machine with only Docker (no local SQL Server, Oracle or MongoDB).
- Breaking a rule on purpose (e.g. allowing `Rejected → Confirmed`) makes at least one test fail.

---

## Interview questions

1. Unit vs integration vs end-to-end tests?
2. Mock vs stub vs fake?
3. What should you mock, and what shouldn't you?
4. Why use a real database in a container instead of the InMemory provider?
5. How does `WebApplicationFactory` work? How do you replace a service in it?
6. How do you test code that depends on the current time?
7. What is a contract test, and why does it matter between microservices?
8. Is 100 % code coverage a good goal?
9. What is TDD?

Answers: [interview question bank](99-interview-questions.md#13--unit-and-integration-testing).

---

## Done when

- [ ] All four test projects pass with `dotnet test`.
- [ ] Each database has at least one real integration test.
- [ ] Pull request into `develop` merged.
