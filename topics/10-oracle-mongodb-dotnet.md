# 10 — Oracle and MongoDB from .NET

> **Time:** 5 h · **Job requirement:** Oracle, MongoDB · **Builds on:** 03, 04, 08 · **Branch:** `feature/10-inventory-and-catalog-data`

## Why it matters

Knowing a database and using it from C# are two different skills. Here you call your PL/SQL package from .NET with ODP.NET (arrays, ref cursors, transactions, Oracle errors), and you replace Catalog's in-memory list with the MongoDB driver. After this topic, ShopFlow's three APIs each talk to their own real database.

---

## Learn

### ODP.NET (Oracle.ManagedDataAccess.Core)

```csharp
// dotnet add package Oracle.ManagedDataAccess.Core
await using var conn = new OracleConnection("User Id=app;Password=***;Data Source=localhost:1521/FREEPDB1");
await conn.OpenAsync(ct);                              // connections are pooled: open late, dispose early

await using var cmd = conn.CreateCommand();
cmd.CommandText = "payroll_pkg.give_raise";
cmd.CommandType = CommandType.StoredProcedure;
cmd.BindByName = true;                                 // ODP.NET binds by POSITION unless you set this!
cmd.Parameters.Add("p_emp_id", OracleDbType.Int32).Value = 10;
cmd.Parameters.Add("p_percent", OracleDbType.Decimal).Value = 5m;
await cmd.ExecuteNonQueryAsync(ct);
```

**Associative arrays** — send C# arrays into a PL/SQL `TABLE OF … INDEX BY PLS_INTEGER`:

```csharp
var names = new OracleParameter("p_names", OracleDbType.Varchar2)
{
    CollectionType = OracleCollectionType.PLSQLAssociativeArray,
    Value = new[] { "ana", "luis" },
    Size = 2,                                          // number of elements
    ArrayBindSize = new[] { 30, 30 }                   // max length of each VARCHAR2 element
};
```

**Ref cursors** — read a `SYS_REFCURSOR` OUT parameter:

```csharp
cmd.Parameters.Add("p_result", OracleDbType.RefCursor, ParameterDirection.Output);
await using var reader = await cmd.ExecuteReaderAsync(ct);
while (await reader.ReadAsync(ct)) { var sku = reader.GetString(0); /* … */ }
```

**Transactions and errors:**

```csharp
await using var tx = (OracleTransaction)await conn.BeginTransactionAsync(ct);
cmd.Transaction = tx;
try { await cmd.ExecuteNonQueryAsync(ct); await tx.CommitAsync(ct); }
catch (OracleException ex) when (ex.Number == 20001)   // RAISE_APPLICATION_ERROR(-20001, …) arrives as 20001
{
    await tx.RollbackAsync(ct);
    // translate to a 400/409 for the API
}
```

**Dapper works with Oracle too** for simple queries: `conn.QueryAsync<StockRow>("SELECT … FROM stock_items WHERE sku = :sku", new { sku })`. Note Oracle parameters use `:name`, not `@name`.

There's also an EF Core provider (`Oracle.EntityFrameworkCore`, `UseOracle(...)`). For package-centric code like Inventory, plain ODP.NET or Dapper is the usual choice.

### MongoDB.Driver

```csharp
// dotnet add package MongoDB.Driver
builder.Services.AddSingleton<IMongoClient>(_ => new MongoClient(connectionString));   // thread-safe: ONE per app

var books = client.GetDatabase("library").GetCollection<BookDocument>("books");

var filter = Builders<BookDocument>.Filter.And(
    Builders<BookDocument>.Filter.Gte(b => b.Year, 2000),
    Builders<BookDocument>.Filter.AnyEq(b => b.Tags, "craft"));

var page = await books.Find(filter)
    .SortByDescending(b => b.Year)
    .Skip(10).Limit(10)
    .ToListAsync(ct);

await books.UpdateOneAsync(b => b.Isbn == isbn,
    Builders<BookDocument>.Update.Set(b => b.Price, 2100m).CurrentDate(b => b.UpdatedAt), cancellationToken: ct);

var stats = await books.Aggregate()
    .Match(b => b.Year >= 2000)
    .Group(b => b.Publisher, g => new { Publisher = g.Key, Count = g.Count() })
    .ToListAsync(ct);

var viaLinq = await books.AsQueryable().Where(b => b.Year >= 2000).OrderBy(b => b.Title).ToListAsync(ct);
```

Mapping tips:

```csharp
public class BookDocument
{
    [BsonId] public ObjectId Id { get; set; }
    public string Isbn { get; set; } = "";
    [BsonRepresentation(BsonType.Decimal128)] public decimal Price { get; set; }
    public BsonDocument Extra { get; set; } = new();     // flexible part of the document
}

// Once at startup: camelCase names, and ignore fields the class doesn't have
ConventionRegistry.Register("shopflow", new ConventionPack
{
    new CamelCaseElementNameConvention(),
    new IgnoreExtraElementsConvention(true)
}, _ => true);
```

Use `BsonDocument` for a truly flexible sub-document (like product `attributes`), and convert it to a `Dictionary<string, object?>` for the DTO with `BsonTypeMapper.MapToDotNetValue`.

**Transactions in MongoDB need a replica set.** A plain single `mongo` container isn't one; start it with `--replSet rs0` and run `rs.initiate()` once if you want to try them.

---

## Build part 1: `ShopFlow.Inventory.Api` + Oracle

### Folder layout

```text
ShopFlow.Inventory.Api/
├── Controllers/   StockController, ReservationsController
├── Data/          IInventoryRepository, OracleInventoryRepository, OracleConnectionFactory, OracleErrors
├── Models/        request/response records
└── Program.cs
```

### Endpoints

| Method and route | Calls | Success |
| --- | --- | --- |
| `GET /api/stock?page=1&pageSize=20` | Dapper query with `OFFSET … FETCH` | 200 page of `{ sku, onHand, reserved, available }` totals |
| `GET /api/stock/{sku}` | `inventory_pkg.get_stock` (ref cursor) | 200 per-warehouse rows + total / 404 |
| `GET /api/stock/low` | `inventory_pkg.get_low_stock` (ref cursor) | 200 list (the Azure Function uses it in topic 16) |
| `POST /api/stock/receipts` | `inventory_pkg.receive_stock` | 204 / 400 |
| `POST /api/reservations` | `inventory_pkg.reserve_stock` with arrays | 200 `{ status, message }` |
| `DELETE /api/reservations/{orderId}` | `inventory_pkg.release_reservation` | 200 `{ released }` |
| `GET /health` | Oracle health check | 200 / 503 |

The two reservation endpoints are for manual testing now. In topic 12, events call the same repository methods.

### Tasks

- [ ] ⭐ `OracleInventoryRepository.ReserveAsync(int orderId, IReadOnlyList<(string Sku, int Quantity)> items, …)`: open a connection and transaction, call `reserve_stock` with two associative arrays and the two OUT parameters, **commit if `RESERVED`**, roll back otherwise, and return a result record.
  - Hints: `BindByName = true`; OUT `VARCHAR2` parameters need a `Size`; read them with `.Value.ToString()`.
- [ ] ⭐ `GetStockAsync` and `GetLowStockAsync` reading ref cursors.
- [ ] `ReceiveAsync` and `ReleaseAsync` with a transaction each.
- [ ] `ListAsync` with **Dapper** and an Oracle paging query; compare how much code it needed vs the ref-cursor version.
- [ ] ⭐ `OracleErrors`: translate `OracleException` numbers from your package (`20010`, …) into 400 ProblemDetails with a readable code; anything else is a 500.
- [ ] Register an `OracleConnectionFactory` (singleton holding the connection string) and the repository (scoped). Connection string in user secrets.
- [ ] Add an Oracle health check (package `AspNetCore.HealthChecks.Oracle`).
- [ ] Write `ShopFlow.Inventory.Api.http` covering every endpoint, including: reserving the same order twice (`ALREADY_RESERVED`) and reserving `UPS-APC-1500` (`FAILED`).

## Build part 2: `ShopFlow.Catalog.Api` + MongoDB

### Tasks

- [ ] ⭐ Write `ProductDocument` and `ReviewDocument` mapped to the collections from topic 04 (camelCase convention, `Decimal128` price, `BsonDocument` attributes).
- [ ] ⭐ Write `MongoProductRepository : IProductRepository` and register it **instead of** the in-memory one. The endpoints from topic 08 must not change at all; that's the proof your abstraction works.
  - List: build the filter with `Builders`; text search with `Filter.Text` when `search` is present; `CountDocumentsAsync` for the total.
  - Lookup by many SKUs: one query with `Filter.In`.
  - Stats: an aggregation pipeline.
- [ ] ⭐ Add `UpdateAvailabilityAsync(string sku, int available, DateTime occurredAt)` that updates `availability` **only if** `occurredAt` is newer than the stored `availability.updatedAt` (put the condition in the update filter). Events can arrive late or out of order; topic 12 calls this.
- [ ] Write an `IHostedService` that creates the indexes from topic 04 at startup (`CreateManyAsync` is safe to repeat).
- [ ] Read the connection string from `ConnectionStrings:CatalogDb` and bind `CatalogMongoOptions` (`Database`) to the `CatalogMongo` section with validation on start; register `IMongoClient` as a singleton and `IMongoDatabase` from it.
- [ ] Add the reviews endpoints: `GET /api/products/{sku}/reviews?page=…` and `POST /api/products/{sku}/reviews` (stars 1–5). After inserting a review, recalculate the product's `rating` summary.
- [ ] Bonus: restart MongoDB as a single-node replica set and make "insert review + update rating" one **transaction** with `IClientSessionHandle`. Write two lines on why it needed a replica set.
- [ ] Write one list query a second time with the LINQ provider (`AsQueryable()`) and compare it with the `Builders` version.
- [ ] Add a MongoDB health check.

---

## Check yourself

- `GET /api/stock/MON-LG-24` returns both warehouses; the totals match a SQL query in Oracle.
- `POST /api/reservations` for an order with one impossible line returns `FAILED`, and `stock_items.reserved` hasn't changed.
- Catalog behaves exactly as in topic 08, but data survives an API restart.
- Calling `UpdateAvailabilityAsync` with an older timestamp after a newer one leaves the newer value.
- Each API's `/health` reports its own database.

---

## Interview questions

1. How do you call a PL/SQL procedure with array parameters from .NET?
2. How do you read a `SYS_REFCURSOR` in C#?
3. Why is `BindByName` important in ODP.NET?
4. Who should commit: the PL/SQL package or the application? Why?
5. Why is `MongoClient` registered as a singleton?
6. Builders vs LINQ in the MongoDB driver?
7. How do you handle events that arrive out of order when updating a read copy?
8. What does MongoDB need to support multi-document transactions?

Answers: [interview question bank](99-interview-questions.md#10--oracle-and-mongodb-from-net).

---

## Done when

- [ ] Inventory.Api works against Oracle; Catalog.Api works against MongoDB.
- [ ] No endpoint signature in Catalog changed when switching from memory to MongoDB.
- [ ] Pull request into `develop` merged.
