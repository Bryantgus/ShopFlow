# 06 — Generics, delegates, LINQ and async

> **Time:** 4 h · **Job requirement:** .NET Core 6+ · **Builds on:** 05 · **Branch:** `feature/06-generics-linq-async`

## Why it matters

These four topics are where interviewers separate junior from mid-level: generic constraints, `Func` vs `Action`, deferred execution, `IEnumerable` vs `IQueryable`, and what `async/await` really does. In ShopFlow you build reusable generic types, add domain events, write sales reports with LINQ, and measure async code in a playground.

---

## Learn

### Generics

```csharp
public class Box<T>
{
    public T Value { get; }
    public Box(T value) => Value = value;
}

public static T Max<T>(T a, T b) where T : IComparable<T> => a.CompareTo(b) >= 0 ? a : b;
```

| Constraint | T must be… |
| --- | --- |
| `where T : class` / `class?` | A reference type (nullable allowed with `?`) |
| `where T : struct` | A non-nullable value type |
| `where T : notnull` | Any non-nullable type |
| `where T : new()` | Creatable with a parameterless constructor |
| `where T : BaseEntity` | That class or a subclass |
| `where T : IComparable<T>` | A type that implements the interface |

**Covariance (`out T`)**: an `IEnumerable<string>` can be used as an `IEnumerable<object>`. **Contravariance (`in T`)**: an `Action<object>` can be used as an `Action<string>`.

### Delegates, lambdas and events

| Type | Signature | Example |
| --- | --- | --- |
| `Func<T, TResult>` | Returns a value | `Func<int, int> square = x => x * x;` |
| `Action<T>` | Returns nothing | `Action<string> log = Console.WriteLine;` |
| `Predicate<T>` | Returns `bool` | `Predicate<int> isEven = n => n % 2 == 0;` |
| `Expression<Func<T, bool>>` | Code as **data** (a tree) | What EF Core translates to SQL |

```csharp
public class Thermostat
{
    public event EventHandler<decimal>? TemperatureChanged;      // only this class can raise it
    public void Set(decimal t) => TemperatureChanged?.Invoke(this, t);
}

var t = new Thermostat();
t.TemperatureChanged += (_, value) => Console.WriteLine($"Now {value} °C");
```

A lambda **captures** outer variables by reference (a closure): it sees later changes to them.

### LINQ

```csharp
var result = people
    .Where(p => p.Age >= 18)
    .GroupBy(p => p.City)
    .Select(g => new { City = g.Key, Count = g.Count(), Oldest = g.MaxBy(p => p.Age)!.Name })
    .OrderByDescending(x => x.Count)
    .ToList();
```

| Operator | Purpose |
| --- | --- |
| `Where`, `Select`, `SelectMany` | Filter, transform, flatten |
| `OrderBy`, `ThenBy`, `…Descending` | Sort |
| `GroupBy`, `ToLookup` | Group (deferred / immediate) |
| `Join`, `GroupJoin` | Inner join / left-join style |
| `Any`, `All`, `Contains`, `Count` | Questions |
| `First`, `FirstOrDefault`, `Single`, `SingleOrDefault` | One element (`Single` throws if more than one) |
| `Sum`, `Average`, `Min`, `Max`, `MinBy`, `MaxBy` | Aggregates |
| `Distinct`, `DistinctBy`, `Union`, `Intersect`, `Except` | Sets |
| `Skip`, `Take`, `Chunk` | Paging and batches |
| `Aggregate` | Custom fold |

**Deferred execution:** a query runs when you iterate it (`foreach`, `ToList`, `Count`, `First`…), not when you write it, and it runs **again** each time you iterate. **`IEnumerable<T>`** runs in memory with compiled delegates; **`IQueryable<T>`** keeps an expression tree that a provider (EF Core, the MongoDB driver) translates into SQL or a MongoDB query.

### async / await

- `await` frees the thread while waiting for I/O (database, HTTP, disk). The server serves more requests with the same threads. It doesn't make a single call faster.
- Return `Task` / `Task<T>`; `async void` only for event handlers.
- Never block on async code with `.Result` or `.Wait()`: deadlocks and thread-pool starvation.
- Pass a `CancellationToken` all the way down.
- Independent calls can run at the same time with `Task.WhenAll`; limit how many with `SemaphoreSlim` or `Parallel.ForEachAsync`.
- CPU-bound work → `Task.Run` or `Parallel`; I/O-bound → `async/await`.
- `IAsyncEnumerable<T>` + `await foreach` streams items as they arrive.
- `ValueTask<T>` avoids an allocation when the result is often already available.

```csharp
using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));   // timeout
var tasks = urls.Select(u => http.GetStringAsync(u, cts.Token));
string[] pages = await Task.WhenAll(tasks);
```

---

## Build

### Part 1 — `Result<T>` and `PagedResult<T>` (in `ShopFlow.Orders.Application/Common`)

Expected failures (product not found, not enough stock) aren't exceptional; return them as values so the caller must handle them.

**`Error`** (record): `Code`, `Message`, `Type` (enum `ErrorType`: `Validation`, `NotFound`, `Conflict`, `Failure`). Static helpers like `Error.NotFound(code, message)`.

**`Result`** and **`Result<T>`**:

| Member | Behavior |
| --- | --- |
| `IsSuccess`, `IsFailure`, `Error` | Failure always has an error; success never does |
| `Value` (only `Result<T>`) | Throws `InvalidOperationException` if read on a failure |
| `Result.Success()`, `Result.Failure(error)`, `Result<T>.Success(value)` | Factories; constructors are private |
| Implicit conversions | From `T` to `Result<T>`, and from `Error` to `Result<T>` |
| `Map<TOut>(Func<T, TOut>)` | Transform the value if success; keep the error otherwise |
| `Bind<TOut>(Func<T, Result<TOut>>)` | Chain another operation that can fail |
| `Match<TOut>(Func<T, TOut> onSuccess, Func<Error, TOut> onFailure)` | Turn the result into one value (the API uses it in topic 08) |

**`PagedResult<T>`** (record): `Items` (`IReadOnlyList<T>`), `Page`, `PageSize`, `TotalCount`, computed `TotalPages`, `HasNextPage`, and `PagedResult<TOut> Map<TOut>(Func<T, TOut>)`.

- [ ] ⭐ Write `Error`, `ErrorType`, `Result`, `Result<T>` and `PagedResult<T>` exactly as specified.

### Part 2 — generic entities and domain events (in the Domain)

- [ ] ⭐ Refactor `Entity` into `Entity<TId> where TId : notnull`, with `Id` of type `TId`. Order, OrderItem and Customer become `Entity<int>`.
- [ ] ⭐ Add `IDomainEvent` (a marker interface with `DateTime OccurredAt`) and `AggregateRoot<TId> : Entity<TId>` that keeps a private list of events with `Raise(IDomainEvent)`, `DomainEvents` (read-only) and `ClearDomainEvents()`.
- [ ] ⭐ Make `Order` an aggregate root and raise records `OrderConfirmedDomainEvent`, `OrderRejectedDomainEvent` and `OrderCancelledDomainEvent` from `Confirm`, `Reject` and `Cancel`. Include what a listener needs: order Id, customer Id, total, reason.
  - These events don't leave the Orders service by themselves. In topic 09 an EF Core interceptor turns them into outbox rows; in topic 12 those rows become integration events on Service Bus. Domain events ≠ integration events: be ready to explain the difference.

### Part 3 — LINQ reports (in `tools/ShopFlow.Playground`)

- [ ] Create a console app `tools/ShopFlow.Playground` that references the Domain project.
- [ ] Write a `SampleData` class that generates 10 customers and 60 orders across 2026 with a **fixed** `Random(42)` seed, using the shared SKUs and prices. Mix statuses.
- [ ] ⭐ Write a static class `OrderReports` with **extension methods on `IEnumerable<Order>`**:
  1. `RevenueByCustomer()` — only `Confirmed` and `Shipped`, highest first.
  2. `TopSkus(int count)` — by units and by revenue (`SelectMany` over items).
  3. `MonthlyRevenue(int year)` — all 12 months, including months with zero.
  4. `AverageOrderValueByStatus()`.
  5. `CustomersWithoutOrders(IEnumerable<Customer> customers)` — use `GroupJoin` or `Except`.
  6. `Where(Func<Order, bool> filter)` style: a method `Filter(params Func<Order, bool>[] rules)` that keeps orders matching **all** rules. Call it with three lambdas.
- [ ] Write report 1 a second time in **query syntax** and check both give the same output.
- [ ] Prove deferred execution: build a query, add an order to the source list, then iterate. Write a comment explaining the output.

### Part 4 — async experiments (in the Playground)

- [ ] Write `FakeCatalogClient.GetPriceAsync(string sku, CancellationToken ct)` that waits a random 100–400 ms (`Task.Delay(…, ct)`) and returns the shared price.
- [ ] ⭐ Get the prices of all 10 SKUs four ways and print the time of each with `Stopwatch`:
  1. One by one with `await` in a `foreach`.
  2. All at once with `Task.WhenAll`.
  3. At most 3 at a time with `SemaphoreSlim`.
  4. With `Parallel.ForEachAsync` and `MaxDegreeOfParallelism = 3`.
- [ ] Add a 250 ms timeout with `CancellationTokenSource` and handle `OperationCanceledException` so the program reports which SKUs didn't arrive.
- [ ] Write `IAsyncEnumerable<decimal> StreamPricesAsync(...)` and consume it with `await foreach`.
- [ ] Write 4–5 lines in a comment: why version 2 is fastest, and why a real service might still prefer version 3.

---

## Check yourself

- `Result<int>.Success(5).Map(x => x * 2).Value == 10`; reading `Value` on a failure throws.
- Confirming an order leaves exactly one `OrderConfirmedDomainEvent` in `DomainEvents`.
- The Playground prints all six reports, and both versions of report 1 match.
- The `WhenAll` version takes about as long as the slowest single call; the sequential one takes the sum.

---

## Interview questions

1. Why use generics? Name four constraints.
2. `Func` vs `Action` vs `Predicate`; `Func<T,bool>` vs `Expression<Func<T,bool>>`?
3. What is deferred execution? Give a bug it can cause.
4. `IEnumerable` vs `IQueryable`?
5. `First` vs `FirstOrDefault` vs `Single`; `Select` vs `SelectMany`?
6. What does `async/await` do, and what does it not do?
7. Why should you avoid `.Result` and `async void`?
8. `Task.WhenAll` vs `Parallel.ForEachAsync`? When would you limit concurrency?
9. Exceptions vs a `Result` type: when do you use each?
10. Domain event vs integration event?

Answers: [interview question bank](99-interview-questions.md#06--generics-delegates-linq-and-async).

---

## Done when

- [ ] `Result<T>`, `PagedResult<T>` and domain events exist and build without warnings.
- [ ] The Playground runs all reports and the four async versions.
- [ ] Pull request into `develop` merged.
