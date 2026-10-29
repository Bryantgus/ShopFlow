# 03 — Oracle and PL/SQL

> **Time:** 5 h · **Job requirement:** PL/SQL, Oracle · **Builds on:** 02 · **Branch:** `feature/03-inventory-database`

## Why it matters

The job asks for PL/SQL and Oracle next to T-SQL and SQL Server. Interviewers will check two things: that you can write a PL/SQL package, and that you know what changes when you move from SQL Server to Oracle. In ShopFlow, Oracle is the **Inventory** database, and all stock rules live in one PL/SQL package that the .NET code calls.

---

## Learn

### Run Oracle locally

```bash
docker run -d --name oracle -p 1521:1521 \
  -e ORACLE_PASSWORD=Oracle_Admin123 \
  -e APP_USER=shopflow_inv -e APP_USER_PASSWORD=Inventory123 \
  gvenzl/oracle-free
```

- The first start takes a few minutes; wait until `docker logs oracle` says `DATABASE IS READY TO USE!`.
- Connect with the Oracle SQL Developer extension: host `localhost`, port `1521`, service name `FREEPDB1`, user `shopflow_inv`.
- Keep your Oracle files in their own folder, so the SQL Server extension doesn't flag PL/SQL as errors (and the other way around).
- To see `DBMS_OUTPUT.PUT_LINE` results, enable DBMS output in your tool (`SET SERVEROUTPUT ON` in SQL*Plus-style tools).

### Anatomy of a PL/SQL block

```sql
DECLARE
    v_name   employees.name%TYPE;          -- same type as the column
    v_row    employees%ROWTYPE;            -- a whole row
    v_count  PLS_INTEGER := 0;
    e_too_many EXCEPTION;                  -- your own exception
BEGIN
    SELECT name INTO v_name FROM employees WHERE id = 10;   -- exactly one row or an exception

    FOR r IN (SELECT id, salary FROM employees WHERE dept = 'IT') LOOP
        v_count := v_count + 1;
        IF r.salary > 100000 THEN
            DBMS_OUTPUT.PUT_LINE('High: ' || r.id);
        ELSIF r.salary < 30000 THEN
            DBMS_OUTPUT.PUT_LINE('Low: ' || r.id);
        END IF;
    END LOOP;

    IF v_count > 50 THEN RAISE e_too_many; END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN DBMS_OUTPUT.PUT_LINE('No employee 10');
    WHEN TOO_MANY_ROWS THEN DBMS_OUTPUT.PUT_LINE('Duplicate id');
    WHEN e_too_many    THEN RAISE_APPLICATION_ERROR(-20050, 'Too many IT employees');
    WHEN OTHERS        THEN DBMS_OUTPUT.PUT_LINE(SQLERRM); RAISE;
END;
/
```

### Cursors

| Kind | When | Example |
| --- | --- | --- |
| Implicit | Every `SELECT INTO`, `INSERT`, `UPDATE`, `DELETE` | `SQL%ROWCOUNT` after an `UPDATE` |
| Cursor FOR loop | Read many rows, simplest form | `FOR r IN (SELECT …) LOOP … END LOOP;` |
| Explicit | You need `OPEN`, `FETCH`, `CLOSE` control | `CURSOR c IS SELECT …;` |
| `SYS_REFCURSOR` | Return a result set to the caller (.NET reads it) | `OPEN p_result FOR SELECT …;` |
| `SELECT … FOR UPDATE` | Lock the rows you read, before changing them | Prevents two orders taking the same last unit |

### Collections and bulk operations

```sql
DECLARE
    TYPE t_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;   -- associative array
    v_ids t_ids;
BEGIN
    SELECT id BULK COLLECT INTO v_ids FROM employees WHERE dept = 'IT';   -- one round trip
    FORALL i IN 1 .. v_ids.COUNT                                            -- one round trip
        UPDATE employees SET salary = salary * 1.05 WHERE id = v_ids(i);
END;
/
```

Associative arrays matter for ShopFlow: ODP.NET (topic 10) can send a C# array straight into one.

### Packages

A package groups related code. The **specification** is the public contract (like a C# interface); the **body** holds the code and any private helpers.

```sql
CREATE OR REPLACE PACKAGE payroll_pkg AS
    FUNCTION monthly_cost (p_dept VARCHAR2) RETURN NUMBER;
    PROCEDURE give_raise   (p_emp_id NUMBER, p_percent NUMBER);
END payroll_pkg;
/
CREATE OR REPLACE PACKAGE BODY payroll_pkg AS
    FUNCTION monthly_cost (p_dept VARCHAR2) RETURN NUMBER IS
        v_total NUMBER;
    BEGIN
        SELECT NVL(SUM(salary), 0) INTO v_total FROM employees WHERE dept = p_dept;
        RETURN v_total;
    END monthly_cost;

    PROCEDURE give_raise (p_emp_id NUMBER, p_percent NUMBER) IS
    BEGIN
        UPDATE employees SET salary = salary * (1 + p_percent / 100) WHERE id = p_emp_id;
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20001, 'Employee not found');
        END IF;
    END give_raise;
END payroll_pkg;
/
```

Why packages: one place for related logic, public vs private code, package-level types and constants, and better performance (the whole package loads into memory once).

### Transactions in Oracle

- There is **no auto-commit** inside the database: changes stay pending until `COMMIT`. A transaction starts with the first change.
- **DDL commits automatically** (`CREATE`, `ALTER`, `DROP`), even in the middle of your work.
- `SAVEPOINT before_items;` and `ROLLBACK TO before_items;` undo part of a transaction.
- Good practice for code called from an application: **the caller owns the transaction.** The package does not `COMMIT`; .NET commits or rolls back (topic 10).
- Readers never block writers: Oracle reads a consistent snapshot of the data.

### T-SQL → PL/SQL cheat sheet

| T-SQL | PL/SQL |
| --- | --- |
| `DECLARE @x INT = 1;` | `v_x NUMBER := 1;` in a `DECLARE` section |
| `SELECT @x = COUNT(*) FROM t;` | `SELECT COUNT(*) INTO v_x FROM t;` |
| `IDENTITY(1,1)` | `GENERATED ALWAYS AS IDENTITY` (or a `SEQUENCE`) |
| `ISNULL(x, 0)` | `NVL(x, 0)` |
| `GETDATE()` / `SYSUTCDATETIME()` | `SYSDATE` / `SYSTIMESTAMP` |
| `TOP 10` | `FETCH FIRST 10 ROWS ONLY` |
| `TRY…CATCH`, `THROW` | `EXCEPTION WHEN …`, `RAISE_APPLICATION_ERROR` |
| `@@ROWCOUNT` | `SQL%ROWCOUNT` |
| `OUTPUT inserted.Id` / `SCOPE_IDENTITY()` | `RETURNING id INTO v_id` |
| `VARCHAR`, `NVARCHAR`, `INT`, `DECIMAL` | `VARCHAR2`, `NVARCHAR2`, `NUMBER(p)`, `NUMBER(p,s)` |
| `''` is not `NULL` | `''` **is** `NULL` |
| Stored procedures in schemas | Packages (spec + body) |
| `EXCEPT` | `MINUS` |

Oracle 23ai (the version in the Free image) also accepts `DROP TABLE IF EXISTS`, `CREATE TABLE IF NOT EXISTS`, a `BOOLEAN` type and `SELECT` without `FROM DUAL`. Older versions don't, so say so if an interviewer asks.

---

## Build: the Inventory database (schema `SHOPFLOW_INV`)

Inventory only knows **quantities**, by SKU and warehouse. It never stores product names or prices: those belong to Catalog.

Files in `database/oracle/`:

| File | Contents |
| --- | --- |
| `01_schema.sql` | Tables, constraints, trigger |
| `02_seed.sql` | Warehouses and stock |
| `03_inventory_pkg_spec.sql` | Package specification |
| `04_inventory_pkg_body.sql` | Package body |
| `99_exercises.sql` | Your queries and anonymous blocks |

### Table specification

**`warehouses`** — `warehouse_id` (identity PK), `code` `VARCHAR2(10)` unique, `name` `VARCHAR2(100)`, `city` `VARCHAR2(80)`.

**`stock_items`**

| Column | Type | Rules |
| --- | --- | --- |
| `sku` | `VARCHAR2(30)` | Part of the PK |
| `warehouse_id` | `NUMBER` | Part of the PK; FK → `warehouses` |
| `on_hand` | `NUMBER(10)` | ≥ 0 |
| `reserved` | `NUMBER(10)` | ≥ 0 and ≤ `on_hand` |
| `reorder_level` | `NUMBER(10)` | Default 5 |
| `updated_at` | `TIMESTAMP` | Default `SYSTIMESTAMP` |

Available quantity = `on_hand - reserved`. Don't store it; calculate it.

**`reservations`**

| Column | Type | Rules |
| --- | --- | --- |
| `reservation_id` | identity | PK |
| `order_id` | `NUMBER` | The Orders service's order Id |
| `sku`, `warehouse_id` | as above | FK → `stock_items` |
| `quantity` | `NUMBER(10)` | > 0 |
| `status` | `VARCHAR2(10)` | `ACTIVE`, `RELEASED` or `SHIPPED` |
| `created_at`, `released_at` | `TIMESTAMP` | `released_at` nullable |
| — | — | Unique `(order_id, sku)` |

**`stock_movements`** — identity PK, `sku`, `warehouse_id`, `movement_type` (`RECEIPT`, `RESERVE`, `RELEASE`, `ADJUST`), `quantity`, `reference` `VARCHAR2(50)` (e.g. `ORDER-15`), `created_at`. An audit log: rows are only inserted, never updated.

### Tasks

- [ ] ⭐ **01_schema:** create the four tables with named constraints, plus a `BEFORE UPDATE … FOR EACH ROW` trigger on `stock_items` that sets `:NEW.updated_at := SYSTIMESTAMP`.
- [ ] ⭐ **02_seed:** two warehouses (`SDQ` Santo Domingo and `STI` Santiago) and stock for the 10 shared SKUs in both. Make it interesting: one SKU with 0 everywhere (`UPS-APC-1500`), two below their reorder level, and one that has enough only when you look at both warehouses together.
- [ ] ⭐ **03 + 04 — `inventory_pkg`** with this public contract:

| Member | What it does |
| --- | --- |
| `TYPE t_sku_tab IS TABLE OF VARCHAR2(30) INDEX BY PLS_INTEGER` | List of SKUs (ODP.NET sends a C# array here) |
| `TYPE t_qty_tab IS TABLE OF NUMBER INDEX BY PLS_INTEGER` | Quantities, same positions as the SKUs |
| `FUNCTION get_available (p_sku) RETURN NUMBER` | Total available across all warehouses |
| `PROCEDURE reserve_stock (p_order_id, p_skus, p_quantities, p_status OUT, p_message OUT)` | Reserve every line of an order, or none |
| `PROCEDURE release_reservation (p_order_id, p_released OUT)` | Release all `ACTIVE` reservations of an order; return how many lines |
| `PROCEDURE receive_stock (p_sku, p_warehouse_code, p_quantity)` | Add stock (creates the `stock_items` row if missing) |
| `PROCEDURE get_stock (p_sku, p_result OUT SYS_REFCURSOR)` | Stock per warehouse for one SKU |
| `PROCEDURE get_low_stock (p_result OUT SYS_REFCURSOR)` | SKUs at or below their reorder level, with total available |

Rules for `reserve_stock`:
- Both arrays must have the same number of elements, each quantity > 0; otherwise `RAISE_APPLICATION_ERROR(-20010, …)`.
- **Idempotent:** if the order already has `ACTIVE` reservations, do nothing and return `p_status = 'ALREADY_RESERVED'`. The same event can arrive twice (topic 12).
- For each line, choose **one** warehouse that has enough available, preferring the one with the most. Lock the candidate rows with `SELECT … FOR UPDATE` so two orders can't take the same last unit.
- Increase `reserved`, insert a `reservations` row and a `RESERVE` movement.
- If any line can't be reserved: undo the lines already done (`SAVEPOINT` / `ROLLBACK TO`), return `p_status = 'FAILED'` and a message such as `Not enough stock for UPS-APC-1500 (requested 2, available 0)`.
- On success: `p_status = 'RESERVED'`.
- **No `COMMIT`** in the package: the .NET caller decides.

Hints:
- Declare a private procedure in the body, `log_movement(…)`, and call it from every public procedure. Private = in the body, not in the spec.
- `release_reservation` must also be idempotent: releasing an order with nothing `ACTIVE` returns `p_released = 0`, not an error.
- `get_low_stock` is a `GROUP BY sku HAVING SUM(on_hand - reserved) <= …` query opened into the cursor.

- [ ] **99_exercises:**
  1. Available stock per SKU, with the warehouses listed in one column (`LISTAGG`).
  2. Rank warehouses by total units on hand (`RANK`).
  3. Movements per day and type for the last 7 days.
  4. A `MERGE` that loads a "stock count" staging table into `stock_items` (update existing rows, insert new ones).
  5. An anonymous block that calls `reserve_stock` for a fake order, prints `p_status` and `p_message`, then `ROLLBACK`.
  6. An anonymous block that reads `get_low_stock` with `FETCH … INTO` in a loop and prints each row.
  7. Raise every reorder level by 20 % in one statement using `BULK COLLECT` and `FORALL`.

---

## Check yourself

- Exercise 5 returns `RESERVED` for SKUs with stock and `FAILED` for `UPS-APC-1500`; after a `FAILED` call, `stock_items.reserved` is unchanged.
- Calling `reserve_stock` twice for the same order (with a `COMMIT` in between) returns `ALREADY_RESERVED` the second time.
- `release_reservation` brings `reserved` back to where it was and writes `RELEASE` movements.
- Recompiling the spec and body shows no errors: `SELECT * FROM user_errors;` is empty.

---

## Interview questions

1. What are the main differences between T-SQL and PL/SQL?
2. What is a package, and why split it into a spec and a body?
3. Implicit vs explicit cursor; what is a `SYS_REFCURSOR` for?
4. What do `BULK COLLECT` and `FORALL` solve?
5. How does Oracle handle transactions differently from SQL Server's default behavior?
6. Why use `SELECT … FOR UPDATE` when reserving stock?
7. What happens if you run DDL in the middle of a transaction?
8. How do you raise a custom error that a .NET application can read?

Answers: [interview question bank](99-interview-questions.md#03--oracle-and-plsql).

---

## Done when

- [ ] Scripts 01–04 run on a fresh container without errors; `user_errors` is empty.
- [ ] `reserve_stock` is all-or-nothing and idempotent.
- [ ] Pull request into `develop` merged.

---

## Extra tasks: the rest of PL/SQL

> **Optional, about 4–5 h · Branch:** `feature/03b-plsql-extras` · Do these after the main topic is merged. In interview mode, read each **Learn** snippet and its interview questions; build them later if you're short on time.

Each extra adds something useful to Inventory. Scripts go in `database/oracle/` with the numbers shown. If you change the package, update `03_inventory_pkg_spec.sql` and `04_inventory_pkg_body.sql` and keep `user_errors` empty.

Most asked in interviews: **autonomous transactions**, **the mutating table error**, **collection types**, **dynamic SQL with bind variables**, **view vs materialized view**, **`BULK COLLECT`/`FORALL`** (main topic).

> **Privileges:** the `shopflow_inv` user may not be allowed to create jobs or materialized views. If you get `ORA-01031: insufficient privileges`, connect as `SYSTEM` to `FREEPDB1` and grant only what's missing (for example `GRANT CREATE JOB TO shopflow_inv;`). Write down every grant you needed: that's a deployment script in real life.

### X1 — Records and a two-phase `reserve_stock` (package)

**Learn**

```sql
DECLARE
    TYPE t_line IS RECORD (
        emp_id  employees.id%TYPE,
        raise   NUMBER
    );
    TYPE t_lines IS TABLE OF t_line;          -- a collection of records
    v_lines t_lines := t_lines();
    v_emp   employees%ROWTYPE;                -- a record shaped like a whole row
BEGIN
    v_lines.EXTEND;
    v_lines(1).emp_id := 10;
    v_lines(1).raise  := 5;
    FORALL i IN 1 .. v_lines.COUNT
        UPDATE employees SET salary = salary * (1 + v_lines(i).raise / 100) WHERE id = v_lines(i).emp_id;
END;
/
```

**Tasks**
- [ ] Refactor `reserve_stock` into two phases with a private record type in the package body: **phase 1** chooses and locks a warehouse for every line, filling a collection of records (`sku`, `warehouse_id`, `quantity`); **phase 2** applies all the `reserved` updates and inserts with `FORALL`. If phase 1 fails for any line, nothing was changed yet, so you no longer need the savepoint. Keep the same public signature, so .NET doesn't notice.

### X2 — SQL collection types: nested tables and VARRAYs (`05_types.sql`)

**Learn**

| Type | Declared in | Size | Usable in SQL (`TABLE(...)`) | Typical use |
| --- | --- | --- | --- | --- |
| Associative array (`INDEX BY`) | PL/SQL only | Unbounded, sparse | No | Lookup tables in memory; arrays from ODP.NET |
| Nested table | SQL (`CREATE TYPE … AS TABLE OF`) or PL/SQL | Unbounded | Yes | Passing lists into queries |
| VARRAY | SQL or PL/SQL | **Fixed maximum**, ordered | Yes | Small, bounded lists |

```sql
CREATE OR REPLACE TYPE t_name_list AS TABLE OF VARCHAR2(100);
/
SELECT e.* FROM employees e
WHERE e.name IN (SELECT COLUMN_VALUE FROM TABLE(t_name_list('Ana', 'Luis')));
```

**Tasks**
- [ ] Create `t_sku_list AS TABLE OF VARCHAR2(30)` and `t_top_skus AS VARRAY(5) OF VARCHAR2(30)`.
- [ ] Add `get_available_many(p_skus IN t_sku_list, p_result OUT SYS_REFCURSOR)`: available stock for many SKUs in **one** query using `TABLE(p_skus)`.
- [ ] Add `FUNCTION top_moving_skus(p_days NUMBER) RETURN t_top_skus`: the 5 SKUs with the most `RESERVE` movements in the last N days.
- [ ] In an anonymous block, try `MULTISET UNION`, `MULTISET EXCEPT` and `MEMBER OF` on two `t_sku_list` values, and print the results.

### X3 — Pipelined function: movement summary you can query like a table (`05_types.sql` + package)

**Learn**

```sql
CREATE OR REPLACE TYPE t_day_row AS OBJECT (day DATE, total NUMBER);
/
CREATE OR REPLACE TYPE t_day_tab AS TABLE OF t_day_row;
/
CREATE OR REPLACE FUNCTION sales_by_day(p_days NUMBER) RETURN t_day_tab PIPELINED IS
BEGIN
    FOR r IN (SELECT TRUNC(sold_at) d, SUM(amount) t FROM sales
              WHERE sold_at >= SYSDATE - p_days GROUP BY TRUNC(sold_at)) LOOP
        PIPE ROW (t_day_row(r.d, r.t));          -- each row goes to the caller immediately
    END LOOP;
    RETURN;
END;
/
SELECT * FROM TABLE(sales_by_day(7));
```

**Tasks**
- [ ] Object type `t_movement_summary_row (movement_day DATE, movement_type VARCHAR2(10), total_qty NUMBER)` and its table type.
- [ ] `inventory_pkg.movements_summary(p_days NUMBER) RETURN t_movement_summary_tab PIPELINED`, so that `SELECT * FROM TABLE(inventory_pkg.movements_summary(7)) ORDER BY 1, 2;` works. Then join its output with `stock_items` in a normal query.

### X4 — Dynamic SQL: movement search with optional filters (package)

**Learn**

```sql
-- EXECUTE IMMEDIATE: one statement built at runtime
EXECUTE IMMEDIATE 'UPDATE ' || DBMS_ASSERT.SQL_OBJECT_NAME(p_table) || ' SET active = 0 WHERE id = :id'
    USING p_id;                                    -- values ALWAYS as bind variables

-- A ref cursor over a dynamic query
OPEN p_result FOR v_sql USING v_dept, v_min_salary;
```

- Bind variables (`:name` + `USING`) prevent SQL injection and let Oracle reuse the parsed statement.
- Object names can't be bound: validate them (`DBMS_ASSERT`) or check them against a fixed list.
- `OPEN … FOR … USING` needs the **same number of binds every time**. A common trick: for an unused filter, add `AND (1 = 1 OR :p_sku IS NULL)` so the bind still exists.
- **DDL through `EXECUTE IMMEDIATE` commits implicitly**, just like typing it.

**Tasks**
- [ ] `search_movements(p_sku, p_movement_type, p_from, p_to, p_reference_like, p_result OUT SYS_REFCURSOR)`: every parameter optional; build the `WHERE` with bind variables only; newest first, maximum 500 rows.
- [ ] Prove it's safe: pass `p_reference_like => ''' OR 1=1 --'` and show it returns nothing extra.
- [ ] In a lab block, run `EXECUTE IMMEDIATE 'TRUNCATE TABLE …'` on a scratch table **in the middle of** a pending `UPDATE`, then `ROLLBACK`, and write what happened to the `UPDATE` and why.

### X5 — Autonomous transaction: an error log that survives rollbacks (`06_error_log.sql`)

**Learn**

```sql
CREATE OR REPLACE PROCEDURE log_audit(p_text VARCHAR2) IS
    PRAGMA AUTONOMOUS_TRANSACTION;               -- its own, independent transaction
BEGIN
    INSERT INTO audit_log (text, logged_at) VALUES (p_text, SYSTIMESTAMP);
    COMMIT;                                      -- required: commits ONLY this insert
END;
/
```

The caller can roll back everything it did; the audit row stays. That's exactly what SQL Server can't do directly (see topic 02, extra E6). Use it for logging and auditing only: an autonomous transaction can't see the caller's uncommitted changes, and using it for business data breaks atomicity.

**Tasks**
- [ ] Table `error_log` (`error_id` identity, `source`, `error_code`, `message`, `backtrace` CLOB, `logged_at`) and a standalone procedure `log_error(p_source, p_code, p_message, p_backtrace)` with `PRAGMA AUTONOMOUS_TRANSACTION`.
- [ ] In every public procedure of `inventory_pkg`, add `WHEN OTHERS THEN log_error(…); RAISE;`. Capture `SQLCODE`, `SQLERRM` and `DBMS_UTILITY.FORMAT_ERROR_BACKTRACE` **inside the handler** and pass them as arguments.
- [ ] Prove it: call `reserve_stock` with arrays of different sizes, catch the error, `ROLLBACK`, then `SELECT * FROM error_log` → the row is there.

### X6 — `PRAGMA EXCEPTION_INIT`, cursors with parameters and `WHERE CURRENT OF` (package)

**Learn**

```sql
DECLARE
    e_child_exists EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_child_exists, -2292);          -- give an Oracle error number a name
    CURSOR c_emps (cp_dept VARCHAR2) IS                     -- a cursor with a parameter
        SELECT id, salary FROM employees WHERE dept = cp_dept FOR UPDATE;
BEGIN
    FOR r IN c_emps('IT') LOOP
        UPDATE employees SET salary = salary + 100 WHERE CURRENT OF c_emps;   -- the row just fetched
    END LOOP;
EXCEPTION
    WHEN e_child_exists THEN DBMS_OUTPUT.PUT_LINE('Has children');
END;
/
```

**Tasks**
- [ ] Table `stock_count_stage (warehouse_code, sku, counted_qty)`: the result of a physical stock count.
- [ ] `apply_stock_count(p_warehouse_code, p_adjusted OUT NUMBER, p_skipped OUT NUMBER)`:
  - A cursor **with a parameter** (the warehouse Id) over `stock_items … FOR UPDATE`.
  - For each item with a counted quantity, `UPDATE … WHERE CURRENT OF` to set `on_hand`, and log an `ADJUST` movement with the difference.
  - Use a `CASE` statement to label the difference (`'SHRINKAGE'`, `'EXCESS'`, `'OK'`) in the movement's `reference`.
  - Name the check-constraint error `-2290` with `PRAGMA EXCEPTION_INIT`: if a count would leave `on_hand` below `reserved`, skip that item, count it in `p_skipped`, and continue with the others.
  - Delete the processed staging rows with `DELETE`, not `TRUNCATE` (why? see X4).

### X7 — The mutating table error and a compound trigger (`07_reorder_alerts.sql`)

**Learn**

A **row-level** trigger can't query the table it's firing on: `ORA-04091: table … is mutating`. The table is half-updated, so Oracle won't let you read it. A **compound trigger** has sections for *before statement*, *before/after each row* and *after statement*, and shares variables between them: collect what you need per row, then query the table **after the statement**, when it's consistent.

```sql
CREATE OR REPLACE TRIGGER trg_salaries_check
FOR UPDATE OF salary ON employees
COMPOUND TRIGGER
    TYPE t_ids IS TABLE OF employees.dept%TYPE INDEX BY PLS_INTEGER;
    v_depts t_ids;

    AFTER EACH ROW IS
    BEGIN
        v_depts(v_depts.COUNT + 1) := :NEW.dept;     -- just remember it
    END AFTER EACH ROW;

    AFTER STATEMENT IS
    BEGIN
        FOR i IN 1 .. v_depts.COUNT LOOP              -- now it's safe to query employees
            NULL; -- check the department's total salary, insert an alert…
        END LOOP;
    END AFTER STATEMENT;
END;
/
```

**Tasks**
- [ ] Table `reorder_alerts` (`alert_id`, `sku`, `available`, `reorder_level`, `created_at`, `resolved_at`).
- [ ] First write a **plain row-level** `AFTER UPDATE` trigger on `stock_items` that sums the SKU's availability across warehouses. Run an update, read the `ORA-04091`, and keep the error text in a comment. Drop that trigger.
- [ ] Write a **compound trigger** that collects the changed SKUs per row and, after the statement, opens an alert for each SKU whose total available is at or below its reorder level and has no open alert, and resolves open alerts that are back above it.
- [ ] Check: reserving the last units of a SKU through `reserve_stock` opens an alert; `receive_stock` resolves it.

### X8 — Views, materialized views, PIVOT and hierarchies (`08_reporting.sql`)

**Learn**

| | View | Materialized view |
| --- | --- | --- |
| Stores data | No: runs the query each time | Yes: a stored result |
| Fresh | Always | As of the last refresh (`ON DEMAND`, `ON COMMIT`, scheduled) |
| Use for | Simplifying queries, security | Heavy aggregations read often |

```sql
SELECT * FROM (SELECT dept, job, salary FROM employees)
PIVOT (SUM(salary) FOR job IN ('DEV' AS dev, 'QA' AS qa));

SELECT LEVEL, LPAD(' ', 2 * (LEVEL - 1)) || name AS tree, SYS_CONNECT_BY_PATH(name, '/') AS path
FROM org_units
START WITH parent_id IS NULL
CONNECT BY PRIOR unit_id = parent_id;          -- Oracle's classic hierarchy syntax
```

**Tasks**
- [ ] A normal view `v_stock_by_sku` and a materialized view `mv_stock_summary` (per SKU: warehouses, on hand, reserved, available) with `REFRESH COMPLETE ON DEMAND`. Change some stock, compare both, refresh with `DBMS_MVIEW.REFRESH('MV_STOCK_SUMMARY')`, compare again.
- [ ] On-hand stock per SKU with **one column per warehouse** (`SDQ`, `STI`) using `PIVOT`, and back to rows with `UNPIVOT`.
- [ ] Table `storage_locations` (`location_id`, `warehouse_id`, `parent_id`, `code`, `kind`: `ZONE` / `AISLE` / `SHELF`) with a small tree for `SDQ`. Print the tree with `CONNECT BY` (`LEVEL`, `SYS_CONNECT_BY_PATH`, `CONNECT_BY_ISLEAF`), then the same with a recursive `WITH`.

### X9 — Sequences and JSON: supplier shipments (package)

**Learn**

```sql
CREATE SEQUENCE ticket_seq START WITH 1 INCREMENT BY 1 NOCACHE;
SELECT 'TCK-' || LPAD(ticket_seq.NEXTVAL, 6, '0') FROM DUAL;

SELECT jt.*
FROM JSON_TABLE(:payload, '$.lines[*]'
     COLUMNS (sku VARCHAR2(30) PATH '$.sku',
              qty NUMBER       PATH '$.qty')) jt;
```

**Tasks**
- [ ] Sequence `receipt_seq`; `receive_stock` now writes references like `REC-000123` in its movements.
- [ ] `receive_shipment(p_payload IN CLOB, p_receipt OUT VARCHAR2)` for a supplier document like `{ "warehouse": "STI", "supplier": "Tech Import SRL", "lines": [ { "sku": "MON-LG-24", "qty": 10 } ] }`: validate it (`p_payload IS JSON`), read the lines with `JSON_TABLE`, call `receive_stock` for each line with **one** receipt number, all or nothing (the caller commits).
- [ ] Invalid JSON or an unknown warehouse → a clear `RAISE_APPLICATION_ERROR` code.

### X10 — Scheduler jobs: daily stock snapshot (`09_jobs.sql`)

**Learn**

```sql
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'JOB_NIGHTLY_CLEANUP',
        job_type        => 'STORED_PROCEDURE',
        job_action      => 'cleanup_pkg.run',
        start_date      => SYSTIMESTAMP,
        repeat_interval => 'FREQ=DAILY;BYHOUR=2;BYMINUTE=0',
        enabled         => TRUE);
END;
/
-- Run it now, and see how it went
EXEC DBMS_SCHEDULER.RUN_JOB('JOB_NIGHTLY_CLEANUP');
SELECT * FROM user_scheduler_job_run_details ORDER BY log_date DESC;
```

**Tasks**
- [ ] Table `stock_snapshots (snapshot_date, sku, available)` with primary key `(snapshot_date, sku)`.
- [ ] `take_daily_snapshot`: refresh `mv_stock_summary`, then `MERGE` today's availability into `stock_snapshots` (running it twice in one day must not duplicate rows), then `COMMIT`. This one commits because a **job** is the caller.
- [ ] A job `JOB_DAILY_STOCK_SNAPSHOT` every day at 02:00; run it by hand once and check the run details.
- [ ] A second job, weekly, that deletes `stock_movements` older than two years in batches of 10,000 rows (loop with `ROWNUM` or `FETCH FIRST`, commit per batch). Explain why batches.
- [ ] Compare in a comment: Oracle jobs vs the Azure Function timer in topic 16. When would you put a scheduled task in each?

### X11 — Users, grants and synonyms (`10_security.sql`)

- [ ] As `SYSTEM`, create a user `shopflow_reports` with only `CREATE SESSION`.
- [ ] As `shopflow_inv`, grant it `SELECT` on `mv_stock_summary` and `stock_snapshots`, and `EXECUTE` on a small new package `inventory_reports_pkg` whose procedures call `inventory_pkg.get_low_stock` and `inventory_pkg.movements_summary` (keep the originals: Inventory.Api uses them). Nothing on the base tables. Why does this work even though the reports user can't read the tables? Look up *definer's rights* (`AUTHID DEFINER`, the default) and write one sentence.
- [ ] As `shopflow_reports`, create **synonyms** so it can write `SELECT * FROM mv_stock_summary` without the schema prefix, and prove it can't read `stock_items`.
- [ ] Compare with topic 02's extra E10: Oracle has no `DENY`; you simply don't grant.

### Extra interview questions

1. What is an autonomous transaction? When is it a good idea, and when a bad one?
2. What is the mutating table error, and how do you avoid it?
3. Associative array vs nested table vs VARRAY?
4. What is a pipelined function for?
5. How do you write dynamic SQL in PL/SQL safely? What happens with DDL inside `EXECUTE IMMEDIATE`?
6. What does `PRAGMA EXCEPTION_INIT` do?
7. View vs materialized view? How is a materialized view refreshed?
8. `CONNECT BY` vs a recursive `WITH`?
9. How do you schedule work inside Oracle?

Answers: [interview question bank](99-interview-questions.md#03-extras--plsql).

### Extras done when

- [ ] Scripts 05–10 run on a fresh container (after 01–04) and `user_errors` is empty.
- [ ] Every check above behaves as described.
- [ ] Pull request `feature/03b-plsql-extras` merged into `develop`.
