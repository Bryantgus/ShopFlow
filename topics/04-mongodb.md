# 04 — MongoDB

> **Time:** 3 h · **Job requirement:** MongoDB · **Builds on:** 02, 03 · **Branch:** `feature/04-catalog-database`

## Why it matters

The job lists MongoDB next to two relational databases, so expect the question *"When would you choose MongoDB over SQL?"*. ShopFlow answers it with a real case: the **Catalog**, where every product type has different attributes and reads are far more common than writes.

---

## Learn

### Run MongoDB locally

```bash
docker run -d --name mongo -p 27017:27017 mongo:8
docker exec -it mongo mongosh          # interactive shell
```

In VS Code, the MongoDB extension connects to `mongodb://localhost:27017` and runs `.mongodb.js` playground files.

### From SQL to MongoDB

| SQL | MongoDB |
| --- | --- |
| Database → table → row → column | Database → collection → document → field |
| Fixed schema | Flexible schema (you can still validate it) |
| Primary key | `_id` (ObjectId by default; you can use your own) |
| `JOIN` | Embed the data, or `$lookup` |
| `GROUP BY` | `$group` in an aggregation pipeline |
| Transaction | Single-document writes are always atomic; multi-document transactions exist but cost more |

### CRUD in mongosh

```javascript
use library

db.books.insertMany([
  { isbn: "978-0134", title: "Clean Code", year: 2008, tags: ["craft", "quality"], price: NumberDecimal("2450.00") },
  { isbn: "978-0201", title: "Refactoring", year: 1999, tags: ["craft"], edition: 2 }
])

db.books.find({ year: { $gte: 2000 } }, { title: 1, _id: 0 }).sort({ year: -1 }).limit(10)
db.books.find({ tags: "craft" })                       // matches inside arrays
db.books.find({ "author.country": "US" })              // dot notation into embedded documents

db.books.updateOne({ isbn: "978-0201" }, { $set: { price: NumberDecimal("2100.00") }, $push: { tags: "classic" } })
db.books.updateMany({}, { $inc: { views: 1 } })
db.books.deleteOne({ isbn: "978-0134" })
```

Use `NumberDecimal` (Decimal128) for money. A normal JavaScript number is a double, and doubles round (`0.1 + 0.2`).

### Operators

| For | Operators |
| --- | --- |
| Compare | `$eq`, `$ne`, `$gt`, `$gte`, `$lt`, `$lte`, `$in`, `$nin` |
| Combine | `$and`, `$or`, `$not`, `$nor` |
| Fields and arrays | `$exists`, `$type`, `$all`, `$elemMatch`, `$size`, `$regex` |
| Update | `$set`, `$unset`, `$inc`, `$push`, `$pull`, `$addToSet`, `$currentDate` |
| Aggregation | `$match`, `$group`, `$project`, `$sort`, `$limit`, `$skip`, `$unwind`, `$lookup`, `$facet`, `$addFields` |

### Aggregation pipeline

Each stage receives the documents from the previous one. Put `$match` early so later stages handle fewer documents and indexes can help.

```javascript
db.books.aggregate([
  { $match: { year: { $gte: 2000 } } },
  { $unwind: "$tags" },
  { $group: { _id: "$tags", books: { $sum: 1 }, avgPrice: { $avg: "$price" } } },
  { $sort: { books: -1 } },
  { $limit: 5 }
])
```

### Indexes

```javascript
db.books.createIndex({ isbn: 1 }, { unique: true })
db.books.createIndex({ tags: 1, year: -1 })            // compound; field order matters
db.books.createIndex({ title: "text" })               // full-text search with $text
db.books.find({ year: 2008 }).explain("executionStats") // IXSCAN good, COLLSCAN = no index used
```

### Data modeling: embed or reference?

| Embed when… | Reference when… |
| --- | --- |
| The data is read together with the parent | The data is shared by many parents |
| It belongs to one parent only | It grows without limit (reviews, logs) |
| It's small and bounded | It changes often on its own |

A document can be at most 16 MB. Model for **how the app reads**, not to avoid repetition: some duplication is normal in MongoDB.

### Schema validation

```javascript
db.createCollection("books", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["isbn", "title"],
    properties: { isbn: { bsonType: "string" }, year: { bsonType: "int", minimum: 1450 } }
  } }
})
```

---

## Build: the Catalog database (`shopflow_catalog`)

Files in `database/mongo/` (run them with `mongosh <file>` or from VS Code):

| File | Contents |
| --- | --- |
| `01_catalog.js` | Collections with validation, seed data |
| `02_indexes.js` | Indexes |
| `03_queries.js` | Your queries and aggregations |

### Document design

**`products`** — one document per SKU:

| Field | Type | Notes |
| --- | --- | --- |
| `_id` | ObjectId | |
| `sku` | string | Unique; same values as the shared product list |
| `name` | string | |
| `category` | string | |
| `brand` | string | |
| `price` | Decimal128 | |
| `currency` | string | `DOP` |
| `attributes` | object | **Different per category**: a laptop has `cpu`, `ramGb`, `storageGb`; a chair has `material`, `maxWeightKg`; a router has `wifiStandard` |
| `tags` | array of strings | |
| `isActive` | bool | Inactive products can't be ordered |
| `availability` | object | `{ available: int, updatedAt: date }` — a **copy** that Inventory events keep updated (topic 12) |
| `rating` | object | `{ average: double, count: int }` — summary kept on the product |
| `createdAt`, `updatedAt` | date | |

**`reviews`** — one document per review: `productSku`, `customerName`, `stars` (1–5), `comment`, `createdAt`. Reviews grow without limit, so they're **referenced** (by `productSku`), not embedded. The product only keeps the `rating` summary.

### Tasks

- [ ] ⭐ **01_catalog.js:** create `products` with a `$jsonSchema` validator (`sku`, `name`, `category`, `price`, `isActive` required; `price` must be `decimal`; `rating.average` between 0 and 5). Insert the 10 shared products with **realistic, different** `attributes` per category. Start every `availability.available` at 0: Inventory owns that number.
- [ ] **01_catalog.js:** create `reviews` and insert 20–30 reviews spread across products; then set each product's `rating` from them (do it with an aggregation, not by hand).
- [ ] ⭐ **02_indexes.js:** unique on `sku`; compound on `category` + `price`; a text index on `name` and `brand`; `reviews` on `productSku` + `createdAt` (descending). Explain each one in a comment.
- [ ] ⭐ **03_queries.js** — write each one and check it with `.explain("executionStats")` where it makes sense:
  1. Active products in a category under a price, cheapest first, page 2 with 3 per page.
  2. Text search for `"logitech"`, sorted by text score.
  3. Laptops with at least 16 GB of RAM (query inside `attributes`).
  4. Number of products and average price per category (`$group`).
  5. Top 3 products by rating with at least 3 reviews.
  6. Each product with its 2 most recent reviews (`$lookup` with a pipeline, `$sort`, `$limit`).
  7. One `$facet` query that returns, at once: count per category, price ranges (`$bucket`: under 2,000 / 2,000–15,000 / over 15,000), and the total number of active products.
  8. Add the tag `"office"` to every product in the Furniture category without duplicates (`$addToSet`).
- [ ] Write in a comment at the top of `01_catalog.js`, in 3–4 lines of English, why `reviews` is a separate collection and why `availability` is a copy.

---

## Check yourself

- Inserting a product without `price`, or with `price: 10` (a double instead of a decimal), is rejected by the validator.
- `db.products.find({ sku: "MON-LG-24" }).explain("executionStats")` shows `IXSCAN`, not `COLLSCAN`.
- Query 7 returns three sections in one document.

---

## Interview questions

1. When would you choose MongoDB instead of SQL Server? When not?
2. Embedding vs referencing: how do you decide?
3. How do you do a join in MongoDB, and why should you rarely need it?
4. What is the aggregation pipeline? Name five stages.
5. How do you check whether a query uses an index?
6. Are MongoDB writes atomic? Does it support transactions?
7. Why use Decimal128 for prices?

Answers: [interview question bank](99-interview-questions.md#04--mongodb).

---

## Done when

- [ ] Scripts 01–03 run on an empty database without errors.
- [ ] Every query in `03_queries.js` returns the expected result.
- [ ] Pull request into `develop` merged.
