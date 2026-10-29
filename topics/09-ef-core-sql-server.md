# 09 — EF Core with SQL Server

> **Time:** 5 h · **Job requirement:** Entity Framework / Core MSSQL · **Builds on:** 02, 07, 08 · **Branch:** `feature/09-orders-infrastructure`

## Why it matters

The job asks for EF Core with SQL Server *and* hand-written T-SQL. The best answer to *"EF Core or stored procedures?"* is "both, for different jobs", and in this topic you build exactly that: EF Core for loading and changing an order, your `usp_PlaceOrder` procedure for the heavy insert, and Dapper for the report with two result sets. Then you swap the fakes from topic 08 for the real database by changing two lines in `Program.cs`.

---

## Learn

### The pieces

| Piece | Role |
| --- | --- |
| `DbContext` | A unit of work: tracks loaded entities and saves all changes in one transaction. Scoped lifetime, **not** thread-safe |
| `DbSet<T>` | A queryable collection of one entity type |
| `IEntityTypeConfiguration<T>` | Fluent mapping for one entity, in its own class |
| Migrations | Versioned schema changes generated from your model |
| Change tracker | Knows each entity's state: `Added`, `Modified`, `Deleted`, `Unchanged`, `Detached` |

```bash
dotnet tool install --global dotnet-ef
dotnet ef migrations add InitialCreate -p src/Orders/ShopFlow.Orders.Infrastructure -s src/Orders/ShopFlow.Orders.Api
dotnet ef migrations script            # see the SQL it will run
dotnet ef database update
```

### Mapping a rich domain model

```csharp
public sealed class InvoiceConfiguration : IEntityTypeConfiguration<Invoice>
{
    public void Configure(EntityTypeBuilder<Invoice> b)
    {
        b.ToTable("Invoices");
        b.HasKey(i => i.Id);
        b.Property(i => i.Number).HasMaxLength(20).IsRequired();
        b.HasIndex(i => i.Number).IsUnique();

        b.Property(i => i.Status).HasConversion<string>().HasMaxLength(20);          // enum as text
        b.Property(i => i.Email).HasConversion(e => e.Value, v => Email.Create(v));  // value object ↔ column
        b.Property<byte[]>("RowVersion").IsRowVersion();                            // shadow property

        b.HasMany(i => i.Lines).WithOne().HasForeignKey("InvoiceId").OnDelete(DeleteBehavior.Cascade);
        b.Navigation(i => i.Lines).UsePropertyAccessMode(PropertyAccessMode.Field); // use the private _lines field
        b.Ignore(i => i.DomainEvents);
    }
}
```

### Reading efficiently

| Technique | Use it when |
| --- | --- |
| `AsNoTracking()` | Read-only queries: faster, less memory |
| Projection with `Select` into a DTO | APIs: load only the columns you return |
| `Include` / `ThenInclude` | You need the related entities themselves (to change them) |
| `AsSplitQuery()` | An `Include` of a big collection multiplies rows (cartesian explosion) |
| `query.ToQueryString()` | See the SQL before running it |
| `ExecuteUpdateAsync` / `ExecuteDeleteAsync` | Change many rows without loading them (no change tracking, no domain events) |

**N+1:** one query for the parents, then one more per parent for its children. EF Core has no lazy loading unless you turn it on, but N+1 still happens when you query inside a loop. Fix it with `Include`, a projection, or one query with `Contains`.

### Raw SQL, procedures and Dapper

```csharp
// Interpolated → parameterized automatically (safe)
var rows = await db.Database.SqlQuery<TopItemDto>($"EXEC dbo.usp_TopItems @Year = {year}").ToListAsync(ct);

// A table-valued parameter: send a DataTable as SqlDbType.Structured
var table = new DataTable();
table.Columns.Add("Id", typeof(int));
foreach (var id in ids) table.Rows.Add(id);
var tvp = new SqlParameter("@Ids", SqlDbType.Structured) { TypeName = "dbo.IdList", Value = table };

// Dapper: great for read models and multiple result sets
await using var conn = new SqlConnection(connectionString);
using var grid = await conn.QueryMultipleAsync("dbo.usp_Report", new { From = from }, commandType: CommandType.StoredProcedure);
var first  = (await grid.ReadAsync<DailyRow>()).ToList();
var second = (await grid.ReadAsync<TopRow>()).ToList();
```

Never build SQL by concatenating user input: that's SQL injection.

### Concurrency

A `rowversion` column changes on every update. EF Core adds it to the `WHERE` of the `UPDATE`; if someone changed the row since you loaded it, zero rows are affected and EF throws `DbUpdateConcurrencyException`. That's **optimistic concurrency**: no locks while the user thinks.

### Interceptors

A `SaveChangesInterceptor` runs code just before or after `SaveChanges`, inside the same transaction. It's the cleanest place to turn domain events into outbox rows.

### Resilience

`UseSqlServer(cs, sql => sql.EnableRetryOnFailure())` retries transient errors (a dropped connection, a failover). With retries on, wrap any manual transaction in `db.Database.CreateExecutionStrategy().ExecuteAsync(...)`.

---

## Build: `ShopFlow.Orders.Infrastructure`

### Folder layout

```text
ShopFlow.Orders.Infrastructure/
├── Persistence/
│   ├── OrdersDbContext.cs
│   ├── Configurations/     OrderConfiguration, OrderItemConfiguration, CustomerConfiguration, OutboxMessageConfiguration
│   ├── Migrations/
│   ├── Interceptors/       DomainEventsToOutboxInterceptor.cs
│   └── Outbox/             OutboxMessage.cs, IntegrationEventMapper.cs
├── Repositories/           OrderRepository, CustomerRepository, UnitOfWork
├── ReadServices/           OrderReadService.cs (EF projections + Dapper)
└── DependencyInjection.cs  AddInfrastructure(configuration)
```

### Decisions already made (so you can explain them)

- **The schema from topic 02 is the truth.** You map EF Core to it, then let migrations own it from now on.
- **ShopFlow sells in one currency (DOP).** Money columns store only the amount, and a value converter restores `Money(amount, "DOP")`. Multi-currency would need a currency column per amount, mapped with EF Core **complex types**. Know how you'd change it.
- **Placing an order uses `usp_PlaceOrder`** (all-or-nothing insert + outbox in SQL). **Confirm, reject and cancel use EF Core** (load the aggregate, call a domain method, `SaveChanges`) and the interceptor writes their outbox rows.

### Tasks

- [ ] ⭐ Write `OrdersDbContext` and the four configuration classes. Match the topic 02 schema exactly: table names, column types and lengths, constraint and index names, the `CHECK` constraints (`ToTable(t => t.HasCheckConstraint(...))`), and the `Total = Subtotal - Discount` rule.
  - Hints: `Sku`, `Email` and `Money` with value converters; `Status` as a string; `RowVersion` as a shadow property; items through the private field; ignore `DomainEvents`; `OutboxMessage` is an infrastructure class, not a domain entity.
- [ ] ⭐ Create the `InitialCreate` migration and compare `dotnet ef migrations script` with your `01_schema.sql`. Fix the configuration until they're equivalent.
- [ ] Bonus: scaffold the existing database into a scratch folder with `dotnet ef dbcontext scaffold "<connection>" Microsoft.EntityFrameworkCore.SqlServer -o scratch/Scaffolded` and compare it with your hand-written mapping. That's **Database First**; what you're doing is **Code First** on an existing schema. Delete the scratch folder afterwards.
- [ ] ⭐ Add a migration `AddProgrammability` that creates the TVP type, view, function, procedures and indexes from topic 02 with `migrationBuilder.Sql(...)`, and drops them in `Down()`.
  - Hint: `migrationBuilder.Sql` can't contain `GO`. Each batch (each `CREATE PROCEDURE`, `CREATE TYPE`…) is a separate `Sql(...)` call. You can embed the `.sql` files as resources and split them on `GO` lines.
- [ ] ⭐ Drop the database, run `dotnet ef database update`, then run `02_seed.sql`. Everything from topic 02 must work again.
- [ ] ⭐ `OrderRepository.PlaceAsync`: call `usp_PlaceOrder` through `Database.ExecuteSqlRawAsync` with the TVP (a `DataTable` matching `dbo.OrderItemInput`) and an `OUTPUT` parameter; return the new Id.
- [ ] `OrderRepository.GetByIdAsync`: tracked, with items.
- [ ] `CustomerRepository` and `UnitOfWork`. In `UnitOfWork`, catch `DbUpdateConcurrencyException` and throw an Application-level `ConcurrencyConflictException`; map it to 409 in the API's exception handler.
- [ ] ⭐ `OrderReadService`:
  - Details: `AsNoTracking` + `Select` straight into `OrderDetailsDto`, with customer name and lines in **one** SQL query. Check it with `ToQueryString()`.
  - Customer orders page: LINQ with `Skip`/`Take` plus a count. Then read `usp_GetCustomerOrders` from topic 02 and write two lines on which one you'd keep and why.
  - Sales report: **Dapper** `QueryMultipleAsync` on `usp_GetSalesReport`, reading both result sets.
- [ ] ⭐ `DomainEventsToOutboxInterceptor`: before saving, find tracked aggregates with domain events, convert each into an `OutboxMessage` (`Type` = the integration event name from the main README, `Payload` = JSON with a new `EventId`), add them to the context, and clear the events.
  - `OrderConfirmed` needs the customer's email and the items; the mapper may read the customer from the same `DbContext`.
  - `OrderRejected` only stays inside Orders (nobody listens yet), so decide: write it to the outbox anyway, or skip it? Write your reasoning in a comment.
- [ ] ⭐ `AddInfrastructure(IConfiguration)`: DbContext with the interceptor and `EnableRetryOnFailure`, repositories, read service. In Development only, log SQL to the console.
- [ ] ⭐ In `Orders.Api/Program.cs`, replace the fake registrations with `AddInfrastructure(...)`, and add a health check for SQL Server. Keep only the fake catalog client (the real one comes in topic 12) and delete the other fakes.
- [ ] If you did topic 02's extras: declare the triggers on `Orders` with `ToTable(t => t.HasTrigger("trg_Orders_StatusHistory"))` (EF Core can't use its `OUTPUT` clause on tables with triggers otherwise), map `OrderNumber` as a computed column, and add `ErrorLog`, `OrderStatusHistory` and the new procedures to the `AddProgrammability` migration (or a new one).
- [ ] Store the connection string with `dotnet user-secrets` in the Api project, never in `appsettings.json`.
- [ ] N+1 lab in the Playground (or a scratch test): load 20 orders, then read each order's items inside a loop; count the SQL statements in the log. Fix it two ways (`Include`, projection) and write the counts in a comment.

---

## Check yourself

- `POST /api/orders` creates rows in `Orders`, `OrderItems` and `OutboxMessages` (`OrderPlaced`).
- `POST /api/orders/{id}/confirm` sets `Confirmed` **and** creates an `OrderConfirmed` outbox row in the same transaction. Stop the database between the two statements in a debugger, and neither should be saved.
- Two parallel confirm calls on the same order: one gets 204, the other 409 (concurrency or invalid transition).
- `GET /api/orders/{id}` runs exactly one SQL query.
- `GET /api/reports/sales` returns the same numbers as running the procedure in VS Code.

---

## Interview questions

1. What is a `DbContext`? Why is it scoped and not a singleton?
2. Tracking vs `AsNoTracking`?
3. `Include` vs projection vs split queries?
4. What is the N+1 problem, and how do you detect it?
5. How do you call a stored procedure with a table-valued parameter and an output parameter from EF Core?
6. EF Core vs Dapper vs stored procedures: how do you choose?
7. Code First vs Database First? How do you start using migrations on an existing database?
8. How does optimistic concurrency work with `rowversion`?
9. What is a `SaveChangesInterceptor` useful for?
10. What do you lose with `ExecuteUpdateAsync`?

Answers: [interview question bank](99-interview-questions.md#09--ef-core-with-sql-server).

---

## Done when

- [ ] A fresh `dotnet ef database update` + seed recreates the full topic 02 database.
- [ ] Orders.Api works end to end against SQL Server; only the catalog client is still a fake.
- [ ] Pull request into `develop` merged.
