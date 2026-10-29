# 02 — SQL Server and T-SQL

> **Time:** 6 h · **Job requirement:** T-SQL, SQL Server · **Builds on:** 01 · **Branch:** `feature/02-orders-database`

## Why it matters

The job lists T-SQL as a requirement, and many .NET interviews include a live SQL exercise. In ShopFlow, SQL Server is the **Orders** database: the place where money lives, so it needs transactions, constraints and stored procedures you write by hand.

---

## Learn

### Warm-up

Before building ShopFlow's database, finish the 10 exercises at the bottom of [`practice/shop-practice.sql`](../practice/shop-practice.sql) (the ShopPractice database you already created). They cover everything below.

### The commands, by family

| Family | Commands | Purpose |
| --- | --- | --- |
| DDL | `CREATE`, `ALTER`, `DROP`, `TRUNCATE` | Define structure: tables, views, indexes, procedures |
| DML | `INSERT`, `UPDATE`, `DELETE`, `MERGE` | Change data |
| DQL | `SELECT` | Read data |
| DCL | `GRANT`, `REVOKE`, `DENY` | Permissions |
| TCL | `BEGIN TRAN`, `COMMIT`, `ROLLBACK`, `SAVE TRAN` | Transactions |

### Logical order of a SELECT

`FROM/JOIN → WHERE → GROUP BY → HAVING → SELECT → ORDER BY → OFFSET/FETCH`

That's why a column alias works in `ORDER BY` but not in `WHERE`.

### Joins, grouping and window functions

```sql
-- Generic example (a school, not ShopFlow)
SELECT s.Name,
       COUNT(e.CourseId)                                   AS Courses,
       AVG(e.Grade)                                        AS AvgGrade,
       RANK() OVER (ORDER BY AVG(e.Grade) DESC)            AS Position
FROM Students AS s
LEFT JOIN Enrollments AS e ON e.StudentId = s.Id
GROUP BY s.Name
HAVING COUNT(e.CourseId) >= 2;
```

| Function | Result for ties (100, 100, 90) |
| --- | --- |
| `ROW_NUMBER()` | 1, 2, 3 |
| `RANK()` | 1, 1, 3 |
| `DENSE_RANK()` | 1, 1, 2 |
| `LAG(col)` / `LEAD(col)` | value from the previous / next row |
| `SUM(col) OVER (ORDER BY …)` | running total |

### CTEs and paging

```sql
WITH Ranked AS (
    SELECT Id, Name, Price,
           ROW_NUMBER() OVER (PARTITION BY Category ORDER BY Price DESC) AS rn
    FROM Items
)
SELECT * FROM Ranked WHERE rn <= 3;

SELECT Id, Name FROM Items
ORDER BY Id
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;   -- page 3, 10 per page
```

### Constraints you'll use

`PRIMARY KEY`, `FOREIGN KEY … REFERENCES`, `UNIQUE`, `CHECK (Quantity > 0)`, `DEFAULT (SYSUTCDATETIME())`, `NOT NULL`, and `ROWVERSION` (a value SQL Server changes on every update; EF Core uses it for optimistic concurrency in topic 09).

### Stored procedures, transactions and errors

```sql
CREATE OR ALTER PROCEDURE dbo.usp_TransferPoints
    @FromId INT, @ToId INT, @Points INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;          -- any error rolls back the whole transaction
    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.Wallets SET Points = Points - @Points
        WHERE Id = @FromId AND Points >= @Points;

        IF @@ROWCOUNT = 0
            THROW 50001, 'Not enough points.', 1;

        UPDATE dbo.Wallets SET Points = Points + @Points WHERE Id = @ToId;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;                   -- re-throw the original error to the caller
    END CATCH
END
```

### Table-valued parameters (TVP)

A TVP lets you send **many rows in one parameter**. It's how .NET sends a list of order lines to a procedure in a single call (you'll do this from EF Core in topic 09).

```sql
CREATE TYPE dbo.IdList AS TABLE (Id INT NOT NULL PRIMARY KEY);
GO
CREATE OR ALTER PROCEDURE dbo.usp_GetItems @Ids dbo.IdList READONLY
AS
    SELECT i.* FROM dbo.Items AS i JOIN @Ids AS x ON x.Id = i.Id;
GO
DECLARE @ids dbo.IdList;
INSERT INTO @ids VALUES (1), (5), (9);
EXEC dbo.usp_GetItems @Ids = @ids;
```

### Producing JSON in T-SQL

```sql
SELECT o.Id AS OrderId,
       (SELECT i.Sku, i.Quantity FROM dbo.Lines AS i WHERE i.OrderId = o.Id FOR JSON PATH) AS Items
FROM dbo.Orders AS o
WHERE o.Id = 7
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
-- {"OrderId":7,"Items":[{"Sku":"A-1","Quantity":2}]}
```

Watch out: a nested `FOR JSON` inside another one is returned as JSON, but if you store it in a variable first, wrap it in `JSON_QUERY()` or it gets escaped as text.

### Views, functions and indexes

| Object | Use it for | Rule |
| --- | --- | --- |
| View | A saved query that hides joins | Usually stores no data |
| Scalar function | A calculation you reuse (`dbo.fn_LineTotal`) | Avoid in big `WHERE` clauses: it can be slow |
| Inline table-valued function | A view with parameters | Fast: the optimizer inlines it |
| Clustered index | The table's physical order (one per table, the PK by default) | Choose a narrow, increasing key |
| Non-clustered index | Fast lookups on other columns | Add `INCLUDE (…)` to cover a query |
| Filtered index | Index only some rows: `WHERE ProcessedAt IS NULL` | Small and fast for "queue" tables |

**SARGable** filters can use an index: `WHERE CreatedAt >= '2026-01-01' AND CreatedAt < '2027-01-01'` works; `WHERE YEAR(CreatedAt) = 2026` does not.

### Reading an execution plan

In VS Code (mssql) or SSMS, run the query with the **actual execution plan**. Look for: `Index Seek` (good) vs `Table/Index Scan` (reads everything), `Key Lookup` repeated many times (add `INCLUDE` columns), and the operator with the highest cost. `SET STATISTICS IO ON;` shows logical reads: fewer reads = faster query.

---

## Build: the Orders database (`ShopFlowOrders`)

Create these files in `database/sqlserver/`. Each one must be **re-runnable** (use `CREATE OR ALTER`, `DROP … IF EXISTS`, or `IF NOT EXISTS`).

| File | Contents |
| --- | --- |
| `00_create_database.sql` | Create `ShopFlowOrders` if it doesn't exist |
| `01_schema.sql` | Tables, constraints, the TVP type |
| `02_seed.sql` | Customers and sample orders |
| `03_views_functions.sql` | View and function |
| `04_procedures.sql` | Stored procedures |
| `05_indexes.sql` | Indexes |
| `99_exercises.sql` | Your report queries |

### Table specification

**`dbo.Customers`**

| Column | Type | Rules |
| --- | --- | --- |
| `Id` | `INT IDENTITY` | Primary key |
| `FullName` | `NVARCHAR(150)` | Required |
| `Email` | `NVARCHAR(200)` | Required, unique |
| `City` | `NVARCHAR(80)` | Required |
| `CreatedAt` | `DATETIME2(0)` | Required, default current UTC time |

**`dbo.Orders`**

| Column | Type | Rules |
| --- | --- | --- |
| `Id` | `INT IDENTITY` | Primary key |
| `CustomerId` | `INT` | FK → `Customers` |
| `Status` | `VARCHAR(20)` | Required, default `'Pending'`; `CHECK` it's one of `Pending, Confirmed, Rejected, Cancelled, Shipped` |
| `Subtotal` | `DECIMAL(18,2)` | Required, ≥ 0 |
| `Discount` | `DECIMAL(18,2)` | Required, default 0, ≥ 0 |
| `Total` | `DECIMAL(18,2)` | Required; `CHECK (Total = Subtotal - Discount)` |
| `Currency` | `CHAR(3)` | Required, default `'DOP'` |
| `CreatedAt` | `DATETIME2(0)` | Required, default current UTC time |
| `ConfirmedAt` | `DATETIME2(0)` | Nullable |
| `CancelledAt` | `DATETIME2(0)` | Nullable |
| `StatusReason` | `NVARCHAR(300)` | Nullable (why it was rejected or cancelled) |
| `RowVersion` | `ROWVERSION` | Concurrency token |

**`dbo.OrderItems`**

| Column | Type | Rules |
| --- | --- | --- |
| `Id` | `INT IDENTITY` | Primary key |
| `OrderId` | `INT` | FK → `Orders`, delete cascade |
| `Sku` | `VARCHAR(30)` | Required |
| `ProductName` | `NVARCHAR(150)` | Required (a copy, so old orders keep the old name) |
| `Quantity` | `INT` | Required, > 0 |
| `UnitPrice` | `DECIMAL(18,2)` | Required, ≥ 0 (a copy of the price at order time) |
| — | — | Unique `(OrderId, Sku)`: one line per product |

**`dbo.OutboxMessages`** (used in topic 12)

| Column | Type | Rules |
| --- | --- | --- |
| `Id` | `UNIQUEIDENTIFIER` | Primary key, default `NEWSEQUENTIALID()` |
| `Type` | `VARCHAR(100)` | Required, e.g. `OrderPlaced` |
| `Payload` | `NVARCHAR(MAX)` | Required; `CHECK (ISJSON(Payload) = 1)` |
| `OccurredAt` | `DATETIME2(3)` | Required, default current UTC time |
| `ProcessedAt` | `DATETIME2(3)` | Nullable; set when published |
| `Attempts` | `INT` | Required, default 0 |
| `LastError` | `NVARCHAR(1000)` | Nullable |

**Type `dbo.OrderItemInput`** (TVP): `Sku VARCHAR(30)`, `ProductName NVARCHAR(150)`, `Quantity INT`, `UnitPrice DECIMAL(18,2)`, primary key on `Sku`.

### Tasks

- [ ] ⭐ **00 + 01:** write the database and schema scripts from the specification. Name every constraint yourself (`PK_Orders`, `FK_Orders_Customers`, `CK_Orders_Status`…): it makes errors readable and migrations predictable.
- [ ] ⭐ **02_seed:** 8 customers from different Dominican cities and 15 orders spread over 2026 with 1–3 lines each. Use only the SKUs, names and prices from the shared product list in the main README. Include every status, and one customer with no orders.
  - Hint: for orders, insert the header with `Subtotal = 0`, insert the lines, then `UPDATE` the totals from the lines with a join. Your `CHECK (Total = Subtotal - Discount)` will force you to update all three together.
- [ ] **03:** `dbo.vw_OrderSummary`: one row per order with customer name, email, status, number of lines, number of units, total. And `dbo.fn_LineTotal(@Quantity, @UnitPrice)` returning `DECIMAL(18,2)`.
- [ ] ⭐ **04 — `dbo.usp_PlaceOrder`**
  - Parameters: `@CustomerId INT`, `@Items dbo.OrderItemInput READONLY`, `@Discount DECIMAL(18,2) = 0`, `@OrderId INT OUTPUT`.
  - Validates: customer exists (`THROW 50010`), at least one item (`THROW 50011`), every quantity > 0 (`THROW 50012`), discount not greater than subtotal (`THROW 50013`).
  - In **one transaction**: insert the order as `Pending` with calculated totals, insert all lines from `@Items`, and insert one `OutboxMessages` row with `Type = 'OrderPlaced'` and a JSON payload with `EventId` (a new GUID), `OrderId`, `CustomerId`, `OccurredAt` and `Items` (`Sku`, `Quantity`). Build the JSON with `FOR JSON PATH`.
  - Hints: `SET XACT_ABORT ON`; `SCOPE_IDENTITY()` for the new Id; `NEWID()` for the EventId; test that an invalid customer leaves **no** rows behind.
- [ ] **04 — `dbo.usp_GetCustomerOrders`**: `@CustomerId`, `@PageNumber`, `@PageSize`, `@TotalCount INT OUTPUT`. Returns one page of orders, newest first, using `OFFSET … FETCH`.
- [ ] ⭐ **04 — `dbo.usp_GetSalesReport`**: `@From DATE`, `@To DATE` (inclusive). Returns **two result sets**: (1) one row per day with number of orders, units and revenue, counting only `Confirmed` and `Shipped` orders; (2) the top 5 SKUs by revenue in the period. The Azure Function uses it in topic 16.
- [ ] **05_indexes:** an index for "orders of one customer, newest first"; a covering index for the sales report; a **filtered** index on `OutboxMessages` for unprocessed messages. For each, write a comment explaining which query it serves.
- [ ] **99_exercises:** write and save these queries:
  1. Revenue per customer, including customers with zero (LEFT JOIN, `COALESCE`).
  2. Each customer's biggest order (CTE + `ROW_NUMBER`).
  3. Monthly revenue in 2026 with a running total and the change from the previous month (`LAG`).
  4. SKUs never ordered, compared against a values list of the 10 shared SKUs (`EXCEPT` or `NOT EXISTS`).
  5. Average days between a customer's orders (`LAG` + `DATEDIFF`).
  6. `MERGE` a small "price update" table into an `#ExpectedPrices` temp table.
- [ ] Take one slow query from 99, read its plan, add or change one index, and write the before/after logical reads in a comment.

---

## Check yourself

```sql
-- Should create order + lines + one outbox row
DECLARE @items dbo.OrderItemInput, @id INT;
INSERT INTO @items VALUES ('MOU-LOGI-M185', N'Logitech M185 wireless mouse', 2, 850.00);
EXEC dbo.usp_PlaceOrder @CustomerId = 1, @Items = @items, @OrderId = @id OUTPUT;
SELECT * FROM dbo.Orders WHERE Id = @id;
SELECT * FROM dbo.OrderItems WHERE OrderId = @id;
SELECT TOP 1 * FROM dbo.OutboxMessages ORDER BY OccurredAt DESC;
```

- The payload in the last row is valid JSON and contains the items.
- Calling with `@CustomerId = 9999` raises error 50010, and the row counts of all three tables don't change.
- Running every script twice in order works without errors.

---

## Interview questions

1. `WHERE` vs `HAVING`?
2. `INNER JOIN` vs `LEFT JOIN`; when would you use `EXISTS` instead of `IN`?
3. Clustered vs non-clustered index; what is a covering index?
4. Stored procedure vs function vs view?
5. `DELETE` vs `TRUNCATE` vs `DROP`?
6. What does `SET XACT_ABORT ON` do, and why use it with `TRY…CATCH`?
7. `ROW_NUMBER` vs `RANK` vs `DENSE_RANK`?
8. What is a SARGable query? Give an example that isn't.
9. How do you find out why a query is slow?
10. What is a table-valued parameter and when would you use one?

Answers: [interview question bank](99-interview-questions.md#02--sql-server-and-t-sql).

---

## Done when

- [ ] All scripts run twice in a row without errors.
- [ ] `usp_PlaceOrder` writes order, lines and an outbox message, or nothing at all.
- [ ] `usp_GetSalesReport` returns two result sets with correct numbers (check one day by hand).
- [ ] Pull request into `develop` merged.

---

## Extra tasks: the rest of T-SQL

> **Optional, about 4 h · Branch:** `feature/02b-tsql-extras` · Do these after the main topic is merged. In interview mode, read each **Learn** snippet and its interview questions; build them after the interview if you're short on time.

The main tasks cover what a .NET backend developer writes most. These cover the rest of the language, and each one has a real job in ShopFlow. Put the scripts in `database/sqlserver/` with the numbers shown, re-runnable like the others.

Most asked in interviews: **triggers (`inserted`/`deleted`)**, **dynamic SQL and injection**, **`CROSS APPLY`**, **temp table vs table variable**, **why cursors are slow**, **isolation levels and deadlocks**.

### E1 — Trigger: order status history (`07_status_history.sql`)

**Learn**

```sql
CREATE OR ALTER TRIGGER dbo.trg_Products_PriceAudit
ON dbo.Products
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(Price) RETURN;                       -- only when the column was in the UPDATE
    INSERT INTO dbo.PriceAudit (ProductId, OldPrice, NewPrice, ChangedAt)
    SELECT d.Id, d.Price, i.Price, SYSUTCDATETIME()
    FROM inserted AS i                                  -- new values of ALL changed rows
    JOIN deleted  AS d ON d.Id = i.Id                   -- old values
    WHERE i.Price <> d.Price;
END
```

- A trigger fires **once per statement**, not once per row. `inserted` and `deleted` can hold many rows: always write set-based code, never `SELECT @x = … FROM inserted`.
- `AFTER` triggers run after the change, inside the same transaction. `INSTEAD OF` triggers replace the change (useful on views, or to block an operation).
- Triggers are hidden logic: use them for auditing and protection, not for business rules the application should own.

**Tasks**
- [ ] Create `dbo.OrderStatusHistory`: `Id`, `OrderId` (FK), `OldStatus`, `NewStatus`, `ChangedAt`, `ChangedBy` (`NVARCHAR(128)`, default `SUSER_SNAME()`).
- [ ] An `AFTER INSERT, UPDATE` trigger on `dbo.Orders` that writes one history row per order whose `Status` changed (and one for each new order, with `OldStatus` NULL). It must work for an `UPDATE` that touches 10 orders at once.
- [ ] An `INSTEAD OF DELETE` trigger on `dbo.Orders` that refuses hard deletes with `THROW 50020, 'Orders cannot be deleted; cancel them instead.', 1`. If SQL Server refuses to create it because of the cascading foreign key from `OrderItems`, change that key to `NO ACTION` (orders are never deleted anyway) and write down the error you got.
- [ ] **Topic 09 note:** EF Core saves changes with an `OUTPUT` clause, which SQL Server doesn't allow on tables with triggers unless EF knows about them. When you reach topic 09, declare the triggers in `OrderConfiguration`: `ToTable(t => t.HasTrigger("trg_Orders_StatusHistory"))`.

**Check:** `UPDATE dbo.Orders SET Status = 'Shipped' WHERE Status = 'Confirmed';` creates one history row per affected order; `DELETE FROM dbo.Orders WHERE Id = 1;` fails with error 50020.

### E2 — Dynamic SQL: order search with optional filters (`08_search_orders.sql`)

**Learn**

```sql
DECLARE @sql NVARCHAR(MAX) = N'SELECT Id, Name FROM dbo.Items WHERE 1 = 1';
IF @Category IS NOT NULL SET @sql += N' AND Category = @Category';
IF @MaxPrice IS NOT NULL SET @sql += N' AND Price <= @MaxPrice';
SET @sql += N' ORDER BY ' + QUOTENAME(@SortColumn);          -- identifiers can't be parameters

EXEC sys.sp_executesql @sql,
     N'@Category NVARCHAR(50), @MaxPrice DECIMAL(18,2)',     -- declare every parameter
     @Category = @Category, @MaxPrice = @MaxPrice;          -- values are passed, never concatenated
```

- `sp_executesql` with parameters is safe from SQL injection and reuses plans. `EXEC(@sql)` with concatenated values is the classic injection hole.
- Values → parameters. Column or table names → validate against a whitelist and wrap with `QUOTENAME`.
- The alternative "catch-all" query, `WHERE (@Category IS NULL OR Category = @Category)`, is simpler but often gets a bad plan; `OPTION (RECOMPILE)` fixes that at the cost of compiling every time.

**Tasks**
- [ ] `dbo.usp_SearchOrders` with optional `@CustomerId`, `@Status`, `@From`, `@To`, `@MinTotal`, `@SkuContains`, plus `@SortBy` (only `CreatedAt`, `Total` or `Id`; anything else → error), `@SortDescending BIT`, `@PageNumber`, `@PageSize`, and `@TotalCount INT OUTPUT`. Build it with `sp_executesql`.
- [ ] Write the same search as a catch-all query with `OPTION (RECOMPILE)` and compare both plans for "only `@CustomerId`" and "no filters". Write what you saw in a comment.
- [ ] Prove it's safe: call it with `@Status = N''' OR 1=1 --'` and show it returns nothing instead of every order.

### E3 — Reading JSON: place an order from a JSON document (`08_search_orders.sql`)

**Learn**

```sql
DECLARE @json NVARCHAR(MAX) = N'{"customerId": 3, "items": [{"sku": "A-1", "qty": 2}]}';
SELECT JSON_VALUE(@json, '$.customerId') AS CustomerId;            -- one scalar
SELECT i.Sku, i.Qty
FROM OPENJSON(@json, '$.items')
     WITH (Sku VARCHAR(30) '$.sku', Qty INT '$.qty') AS i;          -- an array as rows
```

**Tasks**
- [ ] `dbo.usp_PlaceOrderFromJson @Json NVARCHAR(MAX), @OrderId INT OUTPUT`: validate with `ISJSON`, read the customer and items with `OPENJSON … WITH`, look up product names and prices in a values list of the shared products (a CTE), fill a `dbo.OrderItemInput` variable, and call `usp_PlaceOrder`. A support tool or an integration could use it.
- [ ] Invalid JSON → `THROW 50030`; an unknown SKU → `THROW 50031` with the SKU in the message.

### E4 — APPLY, STRING_AGG, ROLLUP, PIVOT and a recursive calendar (`09_reports_extras.sql`)

**Learn**

```sql
-- CROSS APPLY runs a subquery once per outer row (a "for each"); OUTER APPLY keeps rows with no match
SELECT a.Name, last3.*
FROM dbo.Authors AS a
CROSS APPLY (SELECT TOP 3 b.Title, b.Year FROM dbo.Books AS b
             WHERE b.AuthorId = a.Id ORDER BY b.Year DESC) AS last3;

SELECT AuthorId, STRING_AGG(Title, ', ') WITHIN GROUP (ORDER BY Title) AS Titles
FROM dbo.Books GROUP BY AuthorId;

SELECT Country, City, SUM(Sales) AS Sales, GROUPING(City) AS IsSubtotal
FROM dbo.Stores GROUP BY ROLLUP (Country, City);          -- subtotals per country + grand total

SELECT * FROM (SELECT Category, MONTH(SoldAt) AS M, Amount FROM dbo.Sales) AS s
PIVOT (SUM(Amount) FOR M IN ([1], [2], [3])) AS p;         -- rows → columns

WITH Days AS (                                             -- recursive CTE: a calendar
    SELECT CAST('2026-10-01' AS DATE) AS D
    UNION ALL
    SELECT DATEADD(DAY, 1, D) FROM Days WHERE D < '2026-10-31'
)
SELECT D FROM Days OPTION (MAXRECURSION 400);
```

**Tasks**
- [ ] An inline table-valued function `dbo.fn_CustomerOrders(@CustomerId)`. Use it with `CROSS APPLY` to list each customer's **3 latest orders**, then with `OUTER APPLY` so customers without orders appear too.
- [ ] One row per order with all its SKUs in one column, comma-separated (`STRING_AGG`).
- [ ] Revenue by city and status with subtotals per city and a grand total (`ROLLUP`), labeling subtotal rows with `GROUPING()`. Then the same with `GROUPING SETS ((City), (Status), ())`.
- [ ] Revenue per customer with one column per month of 2026 (`PIVOT`), and turn it back into rows with `UNPIVOT`.
- [ ] Rewrite the first result set of `usp_GetSalesReport` so it returns **every day** in the range, with zeros on days without sales, using a recursive CTE calendar and a `LEFT JOIN`.

### E5 — Temp tables, table variables and a cursor lab (`98_labs.sql`)

**Learn**

| | `#Temp` table | `@Table` variable |
| --- | --- | --- |
| Scope | The session or procedure (and procedures it calls) | The batch or procedure only |
| Statistics | Yes: good plans for many rows | Limited: fine for small sets |
| Indexes | Any, created after | Only inline (PK, UNIQUE, inline index) |
| Affected by `ROLLBACK` | Yes | **No**: its rows survive a rollback |

```sql
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT Id FROM dbo.Items;
DECLARE @id INT;
OPEN c;
FETCH NEXT FROM c INTO @id;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- row-by-row work
    FETCH NEXT FROM c INTO @id;
END
CLOSE c; DEALLOCATE c;
```

Cursors process one row at a time; SQL Server is built for sets. Use them only when each row really needs procedural logic (calling a procedure per row, for example).

**Tasks**
- [ ] Copy `Orders` and `OrderItems` into `#temp` tables multiplied to ~50,000 orders (`CROSS JOIN` with a numbers CTE). Recalculate every `Subtotal` and `Total` **with a cursor**, then **with one set-based `UPDATE`**. Compare with `SET STATISTICS TIME ON` and write the numbers in a comment.
- [ ] Load the same 50,000 rows into a `#temp` table and a `@table` variable, run the same `JOIN` + `GROUP BY` on both, and compare the estimated vs actual rows in each plan.
- [ ] Prove the rollback difference: insert into both inside a transaction, `ROLLBACK`, and `SELECT` from both.

### E6 — Logging errors that survive a rollback (`04_procedures.sql`)

SQL Server has no autonomous transactions (Oracle does: topic 03 extras). If you insert into an error log inside a transaction that then rolls back, the log row disappears too.

- [ ] Create `dbo.ErrorLog` (`Id`, `ProcedureName`, `ErrorNumber`, `ErrorMessage`, `ErrorLine`, `Parameters` as JSON, `LoggedAt`).
- [ ] Change `usp_PlaceOrder`'s `CATCH` block: **first** `ROLLBACK`, **then** insert into `dbo.ErrorLog` using `ERROR_PROCEDURE()`, `ERROR_NUMBER()`, `ERROR_MESSAGE()`, `ERROR_LINE()` and the parameters as JSON, **then** `THROW`.
- [ ] Explain in a comment how a table variable could keep the error details if you had to log *before* the rollback.

### E7 — Savepoints and `XACT_STATE()` (`04_procedures.sql`)

- [ ] `dbo.usp_CancelStalePendingOrders @OlderThanHours INT`: cancel every `Pending` order older than the limit, in **one** transaction, with `SAVE TRANSACTION` before each order so one failure is rolled back alone and the rest still commit. Return how many were cancelled and how many failed.
  - Hint: this needs `SET XACT_ABORT OFF`, and in the `CATCH` you must check `XACT_STATE()`: `1` = you can roll back to the savepoint and continue; `-1` = the transaction is doomed and must be fully rolled back. Write why `XACT_ABORT ON` and savepoints don't mix.

### E8 — Isolation levels and a deadlock (`98_labs.sql`)

**Learn**

| Level | Dirty reads | Non-repeatable reads | Phantoms | Notes |
| --- | --- | --- | --- | --- |
| READ UNCOMMITTED | Yes | Yes | Yes | Same as `NOLOCK` |
| READ COMMITTED (default) | No | Yes | Yes | Readers wait for writers' locks |
| REPEATABLE READ | No | No | Yes | Keeps read locks until the end |
| SERIALIZABLE | No | No | No | Range locks: most blocking |
| SNAPSHOT | No | No | No | Reads a version of the data; needs `ALLOW_SNAPSHOT_ISOLATION ON` |

`READ_COMMITTED_SNAPSHOT ON` makes the default level read row versions instead of waiting, like Oracle does.

**Tasks** (open **two** query editors on `ShopFlowOrders`)
- [ ] Window 1: `BEGIN TRAN; UPDATE` an order's total, don't commit. Window 2: read it under `READ COMMITTED` (it waits), then under `READ UNCOMMITTED` (dirty read). Roll back window 1 and write what window 2 saw.
- [ ] Turn on `ALLOW_SNAPSHOT_ISOLATION` and repeat with `SNAPSHOT` in window 2: no waiting, old value.
- [ ] Cause a **deadlock**: window 1 updates order A then B; window 2 updates B then A. Read error 1205 in the victim window and write how you'd prevent it (same order of access, short transactions, retry the victim).

### E9 — Computed columns, sequences, temporal tables

- [ ] Add `OrderNumber AS ('SF-' + RIGHT('000000' + CAST(Id AS VARCHAR(10)), 6)) PERSISTED` to `dbo.Orders` and a unique index on it. (Map it in topic 09 with `HasComputedColumnSql`, or ignore it in EF and read it only in queries.)
- [ ] In a scratch table, compare `IDENTITY` with a `SEQUENCE` (`CREATE SEQUENCE … START WITH 1000 INCREMENT BY 1`, `NEXT VALUE FOR`): which one can you get **before** inserting? Which one can several tables share?
- [ ] Make `dbo.Customers` a **system-versioned temporal table**, change a customer's city twice, and query it with `FOR SYSTEM_TIME AS OF` and `FOR SYSTEM_TIME ALL`. (EF Core supports these with `IsTemporal()`.)

### E10 — Security: schemas, roles and least privilege (`10_security.sql`)

- [ ] Create a schema `reporting` and move (or recreate) `vw_OrderSummary` there.
- [ ] Create a role `ShopFlowReporting` with `EXECUTE` on `usp_GetSalesReport` and `SELECT` on schema `reporting` only, and `DENY SELECT` on `dbo.Customers`.
- [ ] Create a login + user `shopflow_reports` in that role and prove, connected as it, that it can run the report but can't read customers' emails. Explain `GRANT` vs `DENY` vs `REVOKE`.
- [ ] Create a separate login for the Orders API with only what it needs (read/write data, execute procedures, no DDL), and note which login runs EF migrations instead.

### Extra interview questions

1. How do `inserted` and `deleted` work in a trigger? What breaks when a trigger assumes one row?
2. `EXEC(@sql)` vs `sp_executesql`? How do you build a dynamic `ORDER BY` safely?
3. `CROSS APPLY` vs `OUTER APPLY` vs a `JOIN`?
4. Temp table vs table variable?
5. Why are cursors slow, and when are they acceptable?
6. Explain the isolation levels. What does `READ_COMMITTED_SNAPSHOT` change?
7. How do you log an error if the transaction rolls back?
8. `IDENTITY` vs `SEQUENCE`?
9. `GRANT` vs `DENY` vs `REVOKE`; what is least privilege?

Answers: [interview question bank](99-interview-questions.md#02-extras--t-sql).

### Extras done when

- [ ] Scripts 07–10 and 98 run twice without errors, and every check above behaves as described.
- [ ] Pull request `feature/02b-tsql-extras` merged into `develop`.
