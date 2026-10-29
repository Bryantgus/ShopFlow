# Interview question bank

Every question from the topic files, with a short model answer. Use it this way:

1. Read the question, **cover the answer**, and answer out loud in English (under a minute).
2. Compare. Did you say the key idea? Did you give an example?
3. Add **one sentence from ShopFlow** ("In my project, …"). That sentence is what makes an interviewer believe you.

The answers are short on purpose: they're the skeleton of what to say, not a script to memorize.

---

## Start here: the two answers you'll always need

**"Tell me about yourself"** (60–90 seconds)
1. Who you are: *"I'm a full stack developer with [X] years of experience, focused on .NET and Angular/React."* Use your real numbers and stack.
2. What you've done: one or two projects from work, with your role and the result.
3. What you've built to grow: *"To go deeper on the backend, I built ShopFlow, a microservices project with ASP.NET Core, SQL Server, Oracle and MongoDB connected through Azure Service Bus."*
4. Why this role: what attracts you to the company or the position.

**"Walk me through your project"** (2 minutes, practice with the architecture diagram)
1. The business: an online store backend with three services.
2. Why three databases: transactions for orders (SQL Server), stock rules in PL/SQL packages (Oracle), flexible product attributes (MongoDB).
3. How they talk: HTTP for prices, events on Service Bus for everything that *happened*; the outbox pattern and idempotent consumers.
4. The order saga: placed → stock reserved or failed → confirmed or rejected → invoice by an Azure Function → email by a Logic App.
5. Quality: unit tests, integration tests with Testcontainers against the three databases, CI pipeline, Docker Compose, Kubernetes, Azure.
6. One thing you'd improve: e.g. *"I'd add an outbox in Inventory too; right now it publishes after committing, and I rely on redelivery plus idempotency."*

---

## 01 — Setup, Git and Git Flow

1. **Explain Git Flow.** `main` holds production releases (tagged). `develop` collects finished work. `feature/*` branches come from `develop` and return through pull requests. `release/*` comes from `develop` to prepare a version and merges into `main` and back into `develop`. `hotfix/*` comes from `main` for urgent fixes and merges into both.
2. **Git Flow vs trunk-based development?** Git Flow uses long-lived branches and planned releases. Trunk-based means everyone merges small changes into `main` at least daily, hiding unfinished work behind feature flags; it fits continuous deployment and causes fewer merge conflicts.
3. **Merge vs rebase?** Merge keeps the real history and adds a merge commit. Rebase replays your commits on top of the target for a linear history, rewriting them. Never rebase a branch others have pulled.
4. **`git revert` vs `git reset`?** Revert creates a new commit that undoes an old one: safe on shared branches. Reset moves the branch pointer back, rewriting history: only on your own branch.
5. **How do you resolve a merge conflict?** Open the files with conflict markers, decide what the code should be, remove the markers, build and run tests, then `git add` and commit (or `rebase --continue`).
6. **What makes a good pull request?** Small and focused on one thing, a clear description of what and why, tests included, passing pipeline, easy to review.

---

## 02 — SQL Server and T-SQL

1. **`WHERE` vs `HAVING`?** `WHERE` filters rows before grouping; `HAVING` filters groups after `GROUP BY`, so it can use aggregates like `COUNT(*) > 5`.
2. **`INNER` vs `LEFT JOIN`; `EXISTS` vs `IN`?** INNER returns only rows with a match on both sides; LEFT returns every row from the left table, with NULLs when there's no match. `EXISTS` stops at the first match and handles NULLs safely; `NOT IN` with a NULL in the list returns nothing, so prefer `NOT EXISTS`.
3. **Clustered vs non-clustered index; covering index?** The clustered index *is* the table, ordered by its key (one per table, usually the PK). A non-clustered index is a separate structure that points to the rows (many allowed). A covering index contains every column a query needs (key + `INCLUDE` columns), so SQL Server never touches the table.
4. **Procedure vs function vs view?** A procedure runs logic, can change data, return several result sets and use OUTPUT parameters; you call it with `EXEC`. A function returns a value or a table and is used inside queries; it shouldn't change data. A view is a saved `SELECT`.
5. **`DELETE` vs `TRUNCATE` vs `DROP`?** DELETE removes selected rows, row by row, fires triggers and can be filtered. TRUNCATE removes all rows quickly and resets identity. DROP removes the whole table. In SQL Server, both DELETE and TRUNCATE can be rolled back inside a transaction.
6. **`SET XACT_ABORT ON` with `TRY…CATCH`?** With it on, any run-time error marks the whole transaction for rollback, so you never commit half the work. In `CATCH`, you check `@@TRANCOUNT`, roll back, and `THROW` again.
7. **`ROW_NUMBER` vs `RANK` vs `DENSE_RANK`?** For ties (100, 100, 90): ROW_NUMBER gives 1, 2, 3; RANK gives 1, 1, 3; DENSE_RANK gives 1, 1, 2.
8. **What is a SARGable query?** One whose filter can use an index seek. `WHERE CreatedAt >= '2026-01-01'` is SARGable; `WHERE YEAR(CreatedAt) = 2026` isn't, because the function hides the column.
9. **How do you find out why a query is slow?** Look at the actual execution plan (scans instead of seeks, key lookups, expensive operators, bad estimates), check logical reads with `SET STATISTICS IO ON`, check indexes and statistics, and rule out N+1 calls from the application.
10. **What is a table-valued parameter?** A user-defined table type you pass as a read-only parameter, so a procedure receives many rows in one call. *In ShopFlow, `usp_PlaceOrder` receives all order lines as a TVP from EF Core.*

---

## 02 extras — T-SQL

1. **`inserted` and `deleted` in a trigger; the one-row assumption?** They're virtual tables with the new and old versions of **every** row the statement changed (UPDATE fills both, INSERT only `inserted`, DELETE only `deleted`). A trigger fires once per statement, so code like `SELECT @id = Id FROM inserted` silently handles only one row of a multi-row update. Always join them set-based.
2. **`EXEC(@sql)` vs `sp_executesql`; dynamic `ORDER BY`?** `EXEC` runs a concatenated string, which invites SQL injection and gets a new plan for every value. `sp_executesql` takes typed parameters, so values are never part of the SQL text and plans are reused. Column names can't be parameters: check them against a whitelist and wrap them with `QUOTENAME`.
3. **`CROSS APPLY` vs `OUTER APPLY` vs a `JOIN`?** APPLY evaluates a table expression once per outer row and can reference that row's columns (e.g. top 3 orders per customer, or a table-valued function with a column as argument). CROSS APPLY drops outer rows with no result, like an inner join; OUTER APPLY keeps them with NULLs, like a left join.
4. **Temp table vs table variable?** Temp tables have statistics and any indexes, so they're better for larger sets; they're visible to called procedures and take part in transactions. Table variables are scoped to the batch, have limited statistics (fine for small sets) and their rows survive a rollback.
5. **Why are cursors slow; when are they OK?** They process one row at a time with overhead per fetch, while the engine is optimized for set-based operations. Acceptable for genuinely row-by-row work, such as calling a procedure per row or administrative scripts; use `LOCAL FAST_FORWARD`.
6. **Isolation levels; `READ_COMMITTED_SNAPSHOT`?** READ UNCOMMITTED allows dirty reads; READ COMMITTED (default) prevents them; REPEATABLE READ also prevents values changing under you; SERIALIZABLE also prevents phantoms; SNAPSHOT reads a consistent version without blocking. `READ_COMMITTED_SNAPSHOT ON` makes the default level read row versions, so readers don't wait for writers.
7. **Logging an error when the transaction rolls back?** SQL Server has no autonomous transactions, so a log insert inside the transaction is rolled back too. Roll back first, then log in the `CATCH` block, then re-throw; or keep the details in a table variable (which survives the rollback) and insert them afterwards.
8. **`IDENTITY` vs `SEQUENCE`?** IDENTITY belongs to one column of one table and gives the value only after the insert. A SEQUENCE is an independent object: you can get the next value before inserting, share it across tables, and control caching and cycling.
9. **`GRANT` / `DENY` / `REVOKE`; least privilege?** GRANT gives a permission; DENY explicitly forbids it and wins over grants from roles; REVOKE removes a previous GRANT or DENY. Least privilege: each login gets only what its job needs, e.g. the reporting user can execute the report procedure but can't read customer emails.

---

## 03 — Oracle and PL/SQL

1. **T-SQL vs PL/SQL?** Most query syntax is the same. The differences are in procedural code: variable syntax (`@x` vs `v_x :=`), `SELECT … INTO`, error handling (`TRY…CATCH` vs an `EXCEPTION` section), packages, types like `%TYPE`, and transactions (Oracle changes wait for an explicit `COMMIT`).
2. **What is a package, and why spec + body?** A container for related procedures, functions, types and constants. The spec is the public contract; the body holds the code and private helpers. You can change the body without breaking callers, and the package loads into memory once.
3. **Implicit vs explicit cursor; `SYS_REFCURSOR`?** Implicit cursors are created by Oracle for every SQL statement (`SQL%ROWCOUNT`). Explicit cursors you declare and open, fetch and close (or use a cursor FOR loop). A `SYS_REFCURSOR` is a pointer to a result set you return to the caller; .NET reads it like a data reader.
4. **`BULK COLLECT` and `FORALL`?** They reduce context switches between the PL/SQL and SQL engines: BULK COLLECT reads many rows into a collection in one go; FORALL sends a DML statement for a whole collection at once. Much faster than row-by-row loops.
5. **Transactions in Oracle vs SQL Server's default?** SQL Server auto-commits each statement unless you open a transaction. Oracle starts a transaction with the first change and keeps it open until `COMMIT` or `ROLLBACK`. Readers never block writers in Oracle because of multi-version reads.
6. **Why `SELECT … FOR UPDATE` when reserving stock?** It locks the rows you read, so two sessions can't both see "1 available" and both reserve it. The second waits for the first to commit.
7. **DDL in the middle of a transaction?** Oracle commits implicitly before and after DDL, so your pending changes are committed too.
8. **A custom error .NET can read?** `RAISE_APPLICATION_ERROR(-20001, 'message')` with a code between -20000 and -20999. ODP.NET throws an `OracleException` whose `Number` is 20001.

---

## 03 extras — PL/SQL

1. **Autonomous transaction: good and bad uses?** `PRAGMA AUTONOMOUS_TRANSACTION` gives a subprogram its own transaction that commits independently of the caller. Good for error logs and audit trails that must survive a rollback. Bad for business data: it can't see the caller's uncommitted changes and breaks all-or-nothing behavior.
2. **Mutating table error; how to avoid it?** `ORA-04091`: a row-level trigger tried to read or change the table that's being modified, which is in an inconsistent state. Avoid it with a compound trigger (collect keys per row, query in the after-statement section), a statement-level trigger, or by moving the logic into the procedure that does the change.
3. **Associative array vs nested table vs VARRAY?** Associative arrays are PL/SQL-only, sparse and indexed by number or string; they're what ODP.NET binds arrays to. Nested tables are unbounded and can be SQL types used with `TABLE()` in queries. VARRAYs have a fixed maximum size and keep their order.
4. **Pipelined function?** A table function that returns rows one by one with `PIPE ROW`, so callers can `SELECT` from it like a table and start receiving rows before it finishes; good for transformations and reports with procedural logic.
5. **Safe dynamic SQL; DDL in `EXECUTE IMMEDIATE`?** Build the statement with bind variables (`:name` + `USING`) for every value, and validate any object names (`DBMS_ASSERT` or a whitelist). DDL run through `EXECUTE IMMEDIATE` commits implicitly, including the caller's pending changes.
6. **`PRAGMA EXCEPTION_INIT`?** It associates a named exception with an Oracle error number (e.g. `-2290` check constraint violated), so you can handle it with `WHEN e_name THEN` instead of inspecting `SQLCODE` in `WHEN OTHERS`.
7. **View vs materialized view; refresh?** A view stores only the query and always shows current data. A materialized view stores the result; it's refreshed on demand, on commit, or on a schedule, completely or incrementally (fast refresh with materialized view logs).
8. **`CONNECT BY` vs recursive `WITH`?** Both walk hierarchies. `CONNECT BY` is Oracle-specific and offers `LEVEL`, `SYS_CONNECT_BY_PATH` and `CONNECT_BY_ISLEAF`; recursive `WITH` is standard SQL and works in SQL Server too.
9. **Scheduling work inside Oracle?** `DBMS_SCHEDULER` jobs run procedures or blocks on a calendar expression (`FREQ=DAILY;BYHOUR=2`), with run history in `USER_SCHEDULER_JOB_RUN_DETAILS`. Good for data-centric maintenance close to the data; application-level schedules (calling APIs, sending files) fit better in something like Azure Functions.

---

## 04 — MongoDB

1. **MongoDB vs SQL Server?** MongoDB fits flexible or varying schemas, data read as whole documents, high write volumes and catalogs, events or logs. SQL fits strongly related data, complex joins, reporting and strict multi-row transactions. *In ShopFlow, products have different attributes per category, so Catalog uses MongoDB; orders and money use SQL Server.*
2. **Embed vs reference?** Embed data that's read together, belongs to one parent and is bounded. Reference data that's shared, grows without limit or changes independently. *Reviews are referenced because they grow without limit; the product keeps a rating summary.*
3. **Joins in MongoDB?** `$lookup` in an aggregation pipeline. You rarely need it if you model documents around how the app reads them.
4. **Aggregation pipeline?** A list of stages where each transforms the documents from the previous one: `$match`, `$group`, `$project`, `$sort`, `$unwind`, `$lookup`, `$facet`, `$limit`.
5. **Does a query use an index?** Run `.explain("executionStats")`: `IXSCAN` means index scan, `COLLSCAN` means it read the whole collection; compare documents examined vs returned.
6. **Atomic writes and transactions?** A write to a single document is always atomic, including its embedded arrays. Multi-document ACID transactions exist but require a replica set or sharded cluster and cost more.
7. **Why Decimal128 for prices?** Doubles can't represent many decimal values exactly (0.1 + 0.2 ≠ 0.3). Decimal128 stores exact decimals, like `decimal` in C#.

---

## 05 — C# fundamentals and OOP

1. **Value vs reference types; boxing?** Value types hold the data and are copied on assignment; reference types hold a reference to a heap object, so copies share the object. Boxing wraps a value type in an object on the heap, which costs an allocation; generics avoid it.
2. **class vs struct vs record?** Class: reference type with identity, for entities and services. Struct: small value type copied by value. Record: concise type with value equality and `with` copies, great for DTOs and value objects (`record struct` for the value-type version).
3. **The four pillars with an example?** Encapsulation: `Order` only changes status through `Confirm()` and others. Abstraction: handlers depend on `IOrderRepository`. Inheritance: `Order : AggregateRoot<int>`. Polymorphism: different `IDiscountPolicy` implementations behind one call.
4. **Abstract class vs interface?** A class can inherit one abstract class but implement many interfaces. Abstract classes can have fields, constructors and shared code for related types; interfaces define a contract and are easy to mock.
5. **`virtual`, `abstract`, `override`, `sealed`, `new`?** Virtual may be overridden; abstract must be; override replaces the base implementation; sealed stops further overriding or inheritance; new hides a member without polymorphism.
6. **Protecting invariants?** Private setters, validation in constructors or factories, behavior methods that check rules before changing state, and exposing read-only views of collections.
7. **Why `IReadOnlyCollection<T>`?** Callers can read the items but not add or remove them, so every change goes through the aggregate's methods and its rules.
8. **Entity vs value object?** An entity has an identity that lasts while its data changes (an order). A value object is defined only by its values and is immutable (money, an email).

---

## 06 — Generics, delegates, LINQ and async

1. **Why generics; constraints?** Type-safe reusable code without casting or boxing. Constraints: `class`, `struct`, `notnull`, `new()`, a base class, an interface.
2. **`Func` vs `Action` vs `Predicate`; `Func<T,bool>` vs `Expression<Func<T,bool>>`?** Func returns a value, Action returns nothing, Predicate returns bool. A `Func` is compiled code that runs in memory; an `Expression` is a data structure describing the code, which providers like EF Core translate into SQL.
3. **Deferred execution and a bug it causes?** A LINQ query runs when you iterate it, every time you iterate it. Bugs: running an expensive or database query twice, or getting different results because the source changed between iterations. Call `ToList()` once when you need a snapshot.
4. **`IEnumerable` vs `IQueryable`?** IEnumerable executes in memory; IQueryable builds an expression tree that a provider translates and runs in the data source. Calling `AsEnumerable()` too early loads everything and filters in memory.
5. **`First` / `FirstOrDefault` / `Single`; `Select` / `SelectMany`?** First throws if empty; FirstOrDefault returns default; Single throws if there isn't exactly one. Select maps each element; SelectMany maps each to a sequence and flattens them.
6. **What async/await does and doesn't do?** It releases the thread while waiting for I/O, so the server handles more requests. It doesn't create threads or make a single operation faster.
7. **Avoid `.Result` and `async void`?** `.Result`/`.Wait()` block a thread and can deadlock or starve the thread pool. Exceptions in `async void` can't be awaited or caught by the caller and can crash the process.
8. **`Task.WhenAll` vs `Parallel.ForEachAsync`; limiting concurrency?** WhenAll awaits tasks you already started, all at once. Parallel.ForEachAsync processes a collection with a maximum degree of parallelism. Limit concurrency to protect a downstream service, a connection pool or rate limits.
9. **Exceptions vs a `Result` type?** Exceptions for unexpected failures and broken invariants; `Result` for expected outcomes the caller must handle (not found, validation). Results make failure paths explicit and avoid using exceptions for control flow.
10. **Domain event vs integration event?** A domain event happens inside one service, in memory, in the same transaction (`OrderConfirmedDomainEvent`). An integration event is a public message to other services, published after the transaction (`OrderConfirmed` on Service Bus) and versioned as a contract.

---

## 07 — SOLID and design patterns

1. **SOLID with ShopFlow examples?** S: `PlaceOrderHandler` only places orders; validation and logging are separate decorators. O: a new discount is a new `IDiscountPolicy` class. L: every `IDiscountPolicy` can replace another without surprises. I: `IOrderRepository` (writes) is separate from `IOrderReadService` (reads). D: Application defines `ICatalogClient`; Infrastructure implements it with `HttpClient`.
2. **Dependency Inversion vs Dependency Injection?** Inversion is the principle: high-level code and low-level details both depend on abstractions owned by the high level. Injection is the technique: you receive dependencies (usually through the constructor) instead of creating them.
3. **Clean Architecture; why inward?** Layers: Domain, Application, Infrastructure, Presentation. Dependencies point inward so business rules don't depend on frameworks or databases; you can swap infrastructure and test the core in isolation.
4. **Repository on top of EF Core?** For: hides EF from the Application layer, gives aggregate-shaped methods, easier to fake. Against: `DbContext` already is a repository and unit of work; extra layers can add code without value. *In ShopFlow I use repositories for aggregates and query services with projections for reads.*
5. **Strategy vs Factory here?** Strategy makes the discount rule interchangeable behind `IDiscountPolicy`. The Factory decides which strategy applies to a customer, so the handler doesn't know the concrete classes.
6. **Decorator and how you used it?** A class that implements the same interface and wraps another to add behavior. *Validation and logging decorators around command handlers, and a caching decorator around the catalog client.*
7. **What is CQRS; two databases?** Separating commands (change state, return little) from queries (read, no side effects), each optimized for its job. It doesn't require two databases; ShopFlow uses the same database with different models for reads and writes.
8. **Why prices from Catalog?** The client can't be trusted: anyone can send any price. The server takes names and prices from the source of truth at the moment of the order and stores a copy on the order line.

---

## 08 — ASP.NET Core Web API

1. **Middleware and order?** Components in the request pipeline; each can act on the request, call the next one, and act on the response. Order matters: the exception handler must come first to catch everything, and authentication must run before authorization.
2. **Lifetimes; captive dependency?** Singleton: one per app. Scoped: one per request. Transient: new every time. A captive dependency is a longer-lived service holding a shorter-lived one (a singleton holding a `DbContext`), which leads to stale data and threading bugs.
3. **Controllers vs minimal APIs?** Controllers: classes, attributes, filters, conventions; common in existing code. Minimal APIs: lambdas or methods with route groups and endpoint filters; less code, the default in new templates. Both run on the same pipeline.
4. **Global errors; ProblemDetails?** `UseExceptionHandler` with an `IExceptionHandler` catches unhandled exceptions, logs them and returns ProblemDetails (RFC 9457): a standard JSON error with `type`, `title`, `status`, `detail` and extensions such as an error code and trace Id.
5. **`IOptions` vs `IOptionsSnapshot` vs `IOptionsMonitor`?** Read once and cached; re-read per request (scoped); singleton with change notifications.
6. **Which configuration wins; env var mapping?** Later sources override earlier: appsettings → appsettings.{Environment} → user secrets → environment variables → command line. A double underscore maps to a colon: `Jwt__Issuer` → `Jwt:Issuer`.
7. **Idempotent methods?** Repeating the request leaves the same state: GET, PUT, DELETE (and HEAD, OPTIONS). POST isn't; PATCH may not be.
8. **401/403, 400/422, 409?** 401 not authenticated; 403 authenticated but not allowed. 400 malformed or invalid input; 422 well-formed but semantically invalid. 409 conflict with the current state (an invalid status transition, a concurrency conflict, a duplicate key).
9. **Why not expose entities or commands?** You'd leak internal fields, allow over-posting, couple clients to your internal model and break them when it changes. Request/response DTOs are a stable contract.

---

## 09 — EF Core with SQL Server

1. **`DbContext`; why scoped?** A unit of work that tracks entities and saves changes in one transaction. It isn't thread-safe and its tracked state belongs to one operation, so one instance per request.
2. **Tracking vs `AsNoTracking`?** Tracking keeps snapshots to detect changes for `SaveChanges`. AsNoTracking skips that for read-only queries: faster and less memory.
3. **`Include` vs projection vs split queries?** Include loads full related entities (for changing them). Projection with `Select` loads only the needed columns into DTOs (best for reads). Split queries run one SQL per included collection to avoid huge joined result sets.
4. **N+1 and detecting it?** One query for a list, then one more per item. Detect it by logging SQL (many similar statements) or with an APM tool; fix with Include, a projection or a single query with `Contains`.
5. **Procedure with a TVP and output from EF Core?** Build a `DataTable` matching the table type, pass it as a `SqlParameter` with `SqlDbType.Structured` and `TypeName`, add an output `SqlParameter`, and run `Database.ExecuteSqlRawAsync("EXEC … @Items, @OrderId OUTPUT", …)`.
6. **EF Core vs Dapper vs procedures?** EF Core for most CRUD and aggregates, with change tracking and migrations. Dapper for fast read models, complex SQL or multiple result sets. Procedures for heavy set-based work, logic shared with other systems, or when the DBA owns the SQL.
7. **Code First vs Database First; migrations on an existing database?** Code First: the model generates the schema through migrations. Database First: scaffold the model from the database. On an existing database: map the model to match the schema, create an initial migration, and mark it as applied (or recreate the database) so future changes go through migrations.
8. **Optimistic concurrency with `rowversion`?** EF includes the original rowversion in the UPDATE's WHERE. If another user changed the row, nothing is updated, EF throws `DbUpdateConcurrencyException`, and you return 409 or retry.
9. **`SaveChangesInterceptor` uses?** Running code inside the same save: auditing fields, soft delete, and converting domain events into outbox rows in the same transaction.
10. **What do you lose with `ExecuteUpdateAsync`?** Change tracking, domain logic and domain events: it goes straight to SQL. Great for bulk updates, but it bypasses your aggregate's rules.

---

## 10 — Oracle and MongoDB from .NET

1. **PL/SQL with array parameters from .NET?** With ODP.NET, an `OracleParameter` with `CollectionType = PLSQLAssociativeArray`, the array as `Value`, `Size` = number of elements and `ArrayBindSize` for string lengths, matching a `TABLE OF … INDEX BY PLS_INTEGER` type in the package.
2. **Reading a `SYS_REFCURSOR`?** Add an output parameter of type `OracleDbType.RefCursor` and call `ExecuteReader`; read it like any data reader.
3. **Why `BindByName`?** ODP.NET binds parameters by position by default; if you add them in a different order than the procedure declares them, values go to the wrong parameters silently.
4. **Who commits?** Usually the caller: the application knows the business transaction's boundaries and may combine several calls. A package that commits internally takes that control away.
5. **Why is `MongoClient` a singleton?** It's thread-safe and manages its own connection pool; creating many clients wastes connections and resources.
6. **Builders vs LINQ in the MongoDB driver?** Builders map one-to-one to MongoDB's query language and support every feature. LINQ is more natural C# and type-safe but may not support every operator. Use LINQ for simple queries and Builders when you need full control.
7. **Out-of-order events on a read copy?** Store the timestamp (or a version) of the last applied change and only apply events newer than it, with the condition in the update filter.
8. **MongoDB multi-document transactions require?** A replica set (even a single-node one) or a sharded cluster.

---

## 11 — Security: JWT, policies, CORS

1. **Authentication vs authorization; 401 vs 403?** Who you are vs what you may do. 401: no valid identity. 403: identified, but not allowed.
2. **How does JWT work; is the payload secret?** A signed token with header, payload (claims) and signature. The API verifies signature, issuer, audience and expiry; no server session needed. The payload is only encoded, not encrypted: anyone can read it.
3. **Symmetric vs asymmetric signing?** Symmetric uses one shared secret to sign and verify (every verifier could also create tokens). Asymmetric signs with a private key and verifies with a public key, so APIs can verify without being able to issue tokens.
4. **Roles vs claims vs policies vs resource-based?** Roles are a kind of claim. Policies combine requirements (roles, claims, custom logic) under a name. Resource-based authorization checks the user against a specific object (is this my order?), so it runs after loading it.
5. **OAuth flow for a SPA; a background service?** Authorization Code with PKCE for a SPA; Client Credentials for service-to-service without a user.
6. **CORS and what it doesn't protect?** A browser mechanism that controls which origins may call your API from JavaScript. It doesn't stop non-browser clients; it isn't authentication.
7. **Broken object-level authorization?** Users accessing other users' objects by changing an Id. *I take the customer Id from the token and check ownership with a resource-based requirement, returning 404 so I don't reveal that the order exists.*
8. **Limiting abusive clients?** Rate limiting (built-in middleware in the API, policies in API Management), request size limits, timeouts.
9. **Secrets in dev and production?** Dev: user secrets or a local `.env` that's git-ignored. Production: Key Vault (or another secret store) read with Managed Identity. Never in the repository.

---

## 12 — SOA and microservices

1. **Monolith vs SOA vs microservices; when not microservices?** (See the topic table.) Avoid microservices with a small team, an unclear domain, or without automated deployment and monitoring; a modular monolith gives most of the structure without the distributed-system cost.
2. **Sync vs async?** Synchronous calls when you need an answer right now (prices). Asynchronous messages to announce facts and decouple availability (order placed, stock reserved).
3. **Queue vs topic with subscriptions?** A queue delivers each message to one consumer. A topic delivers a copy to every subscription, each with its own filters: publish/subscribe.
4. **At-least-once for your code?** The same message can arrive more than once, so every handler must be idempotent.
5. **Transactional outbox?** Writing the business change and the outgoing event in the same local transaction (an outbox table), then publishing asynchronously. It removes the dual-write problem: saved but not published, or published but not saved.
6. **Idempotent consumers, two ways?** An inbox table of processed message Ids checked and written in the same transaction as the change; or operations that are naturally safe to repeat (setting a value, state checks, unique constraints such as one reservation per order).
7. **Saga; choreography vs orchestration?** A long business process across services as local transactions with compensating actions. Choreography: services react to each other's events (simple, but the flow is spread out). Orchestration: a coordinator drives the steps (easier to see and change, one more component).
8. **Dead-letter queue?** A sub-queue for messages that can't be processed (too many delivery attempts, expired, or rejected on purpose) so they don't block others and can be inspected and replayed.
9. **Timeout, retry, circuit breaker?** Timeout bounds waiting. Retry repeats transient failures with exponential backoff and jitter. A circuit breaker stops calls to a failing dependency for a while, failing fast and giving it time to recover.
10. **Tracing across services?** A correlation or trace Id passed in HTTP headers and message properties, with OpenTelemetry collecting distributed traces into a tool such as Application Insights.

---

## 13 — Unit and integration testing

1. **Unit vs integration vs end-to-end?** Unit: one unit in isolation, fast. Integration: real components together (API + database). End-to-end: the whole system through its external interface.
2. **Mock vs stub vs fake?** A stub returns canned data; a mock also verifies interactions; a fake is a working simplified implementation.
3. **What to mock?** Boundaries you don't own or that are slow or nondeterministic: databases behind repositories, HTTP clients, the clock, message buses. Don't mock the domain model or simple value objects.
4. **Real database vs InMemory provider?** InMemory doesn't run SQL, constraints, procedures or real transactions, so tests can pass while production fails. A container runs the real engine.
5. **`WebApplicationFactory`; replacing a service?** It starts your real app in memory with a test HTTP client. You override configuration and services in `ConfigureWebHost` / `ConfigureTestServices`.
6. **Testing time-dependent code?** Inject `TimeProvider` and use `FakeTimeProvider` in tests to set and advance time.
7. **Contract tests between microservices?** Tests that check the shape of messages or APIs other services depend on, so a rename fails your build instead of breaking a consumer in production.
8. **Is 100 % coverage a good goal?** No. Coverage shows what isn't tested; aim for strong tests of business rules and failure paths. 100 % often means low-value tests.
9. **What is TDD?** Write a failing test, write the minimum code to pass, refactor; repeat. It drives design toward testable code.

---

## 14 — Docker and Docker Compose

1. **Image vs container; container vs VM?** An image is a read-only template; a container is a running instance. Containers share the host kernel and start in seconds; VMs include a full OS.
2. **Why multi-stage builds?** Build with the SDK image and copy only the output into the small runtime image: smaller, faster to pull, fewer vulnerabilities.
3. **Layer cache and ordering?** Each instruction creates a cached layer; if nothing it depends on changed, it's reused. Copy the project files and restore first, then the source, so code changes don't trigger a new restore.
4. **How containers find each other in Compose?** Compose creates a network where each service is reachable by its service name through internal DNS.
5. **Volumes?** Persistent storage outside the container's writable layer. Without one, data disappears when the container is removed.
6. **`depends_on` vs health checks?** Plain `depends_on` only orders startup. With `condition: service_healthy` it waits until the dependency's health check passes.
7. **Configuration and secrets?** Environment variables (from an untracked `.env` file locally), mounted files, or a secret store in the platform; never baked into the image.
8. **Why non-root?** If the app is compromised, the attacker has fewer privileges inside the container and on the host.

---

## 15 — Continuous Integration

1. **CI vs Continuous Delivery vs Continuous Deployment?** CI builds and tests every change. Delivery keeps every passing version ready, with a manual release. Deployment releases every passing version automatically.
2. **Your pipeline, stage by stage?** Build (restore, build, format check) → unit tests with coverage → integration tests with containers → build and push images tagged with the build number and commit, only on `develop` and `main`.
3. **Keeping it fast?** Run fast tests first, cache packages, run independent jobs in parallel, run expensive suites only where needed.
4. **Image tags?** A unique, traceable tag (build number, commit SHA, version) so you know exactly what's deployed and can roll back. `latest` changes under you.
5. **Secrets in a pipeline?** Secret variables, variable groups linked to Key Vault, service connections; never echo them; least privilege.
6. **Branch policy?** Rules on a branch: required reviewers, a passing build, linked work items, before a pull request can merge.
7. **Your Git Flow release?** `release/x.y.z` from `develop`, bump the version, last fixes, merge into `main`, tag `vx.y.z`, merge back into `develop`.

---

## 16 — Azure Functions

1. **Triggers and bindings?** A trigger starts the function (HTTP, timer, Service Bus, blob, queue…); bindings read or write data declaratively (blob output, queue output) without connection code.
2. **Isolated vs in-process; why now?** In-process ran inside the Functions host and was tied to its .NET version. Isolated runs in its own process with full control over .NET version, dependencies and middleware. In-process support ends on November 10, 2026.
3. **Consumption / Flex vs Premium vs Dedicated?** Consumption plans scale to zero and bill per use, with cold starts. Premium keeps pre-warmed instances and adds VNet features. Dedicated runs on an App Service plan you already pay for.
4. **Cold start and reducing it?** The delay when a new instance starts after idle. Reduce it with always-ready or pre-warmed instances (Flex Consumption, Premium), smaller apps and fast startup code.
5. **Idempotent Service Bus function?** Deterministic outputs (the blob name is the order Id), upserts, or a processed-message check; a poison message ends in the dead-letter queue after max deliveries.
6. **Durable Functions?** Stateful orchestrations in code for chaining, fan-out/fan-in, waiting for external events or approvals, and long-running workflows.
7. **Functions vs a `BackgroundService` in the API?** Functions scale and bill independently and fit event-driven or scheduled work. A BackgroundService lives with the API (simple, shares its code and lifetime), like ShopFlow's outbox publisher.
8. **Running locally?** Core Tools (`func start`), Azurite for storage, emulators or a dev namespace for Service Bus, `local.settings.json` for settings.

---

## 17 — App Service, API Management, Logic Apps

1. **App Service vs Functions vs Container Apps vs AKS?** App Service: always-on web apps and APIs with little operations work. Functions: event-driven pieces, pay per use. Container Apps: containers and microservices with autoscaling on events, without managing Kubernetes. AKS: full Kubernetes control, for large platforms and teams that can operate it.
2. **Deployment slots?** Extra live environments of the same app. Deploy to staging, warm it up, swap with production for zero downtime and swap back to roll back. They need the Standard tier or higher.
3. **Managed Identity?** An identity Azure creates and rotates for your resource. The app gets tokens for other Azure services without storing any password or key.
4. **Key Vault without code changes?** App settings with Key Vault references; App Service resolves them with the app's Managed Identity and exposes them as normal settings.
5. **What APIM adds?** One entry point, subscription keys and products, JWT validation, rate limits and quotas, caching, request/response transformation, versioning, a developer portal and analytics, all without changing the APIs.
6. **Four policies and where?** Inbound: `validate-jwt`, `rate-limit`, `set-header`, `cors`, `cache-lookup`. Backend: `set-backend-service`, `retry`. Outbound: `cache-store`, removing headers, transforming the body. On-error: custom error responses.
7. **Logic Apps vs Functions?** Logic Apps for integration workflows with connectors and little code; Functions for custom code. Combine them.
8. **Keeping costs down?** One resource group, smallest tiers and free offers, budgets and alerts, scale to zero where possible, delete resources after practicing.
9. **Infrastructure as Code; Bicep vs ARM vs Terraform?** Resources described in versioned files and deployed repeatably. ARM is Azure's JSON format; Bicep is a cleaner language that compiles to ARM; Terraform is multi-cloud with its own state.

---

## 18 — Kubernetes

1. **Why Kubernetes if you have Docker?** Docker runs containers; Kubernetes orchestrates them across machines: desired state, self-healing, scaling, service discovery, rolling updates.
2. **Pod vs Deployment vs Service vs Ingress?** Pod runs containers. Deployment manages replicas and updates of pods. Service gives pods a stable address and load balancing. Ingress routes external HTTP traffic to services.
3. **Liveness vs readiness vs startup; liveness checking the database?** Liveness restarts a stuck container; readiness removes a pod from traffic; startup protects slow starts. If liveness checks the database, a database outage restarts every pod in a loop, making things worse.
4. **ConfigMap vs Secret; encrypted?** Both inject configuration. Secrets are for sensitive values but are only base64-encoded by default; enable encryption at rest and RBAC, or use an external secret store such as Key Vault.
5. **Rolling update and rollback?** New pods start and become ready before old ones stop, a few at a time. `kubectl rollout undo` returns to the previous ReplicaSet.
6. **Requests vs limits; `OOMKilled`?** Requests are what the scheduler reserves; limits cap usage. A container exceeding its memory limit is killed: `OOMKilled`.
7. **Deployment vs StatefulSet?** Deployments run interchangeable pods. StatefulSets give each pod a stable name and its own persistent storage, which databases need.
8. **AKS vs Container Apps vs App Service?** (See question 1 of topic 17.) AKS for full control; Container Apps for managed containers with event-based scaling; App Service for straightforward web apps.

---

## Questions to ask the interviewer

- "What does a typical sprint look like for the team, and how are tasks assigned?"
- "Which part of the stack would I work on first: the APIs, the databases or the Azure services?"
- "How do you handle code reviews, testing and deployments?"
- "Since the client is international, how does the team communicate with them day to day?"
- "What would make someone successful in this role in the first three months?"
