/* =========================================================
   ShopPractice — T-SQL practice database (Day 1)
   Run this whole file once: Ctrl+Shift+E (Cmd+Shift+E on Mac)
   ========================================================= */

-- 1. Create the database
IF DB_ID('ShopPractice') IS NULL
    CREATE DATABASE ShopPractice;
GO
USE ShopPractice;
GO

-- 2. Tables (dropped first so you can re-run this file any time)
DROP TABLE IF EXISTS OrderItems, Orders, Products, Customers, Employees;
GO

CREATE TABLE Employees (
    Id         INT IDENTITY(1,1) PRIMARY KEY,
    Name       NVARCHAR(100) NOT NULL,
    Department NVARCHAR(50)  NOT NULL,
    Salary     DECIMAL(10,2) NOT NULL,
    ManagerId  INT NULL REFERENCES Employees(Id),
    HireDate   DATE NOT NULL
);

CREATE TABLE Customers (
    Id        INT IDENTITY(1,1) PRIMARY KEY,
    Name      NVARCHAR(100) NOT NULL,
    City      NVARCHAR(60)  NOT NULL,
    Email     NVARCHAR(100) NOT NULL,
    CreatedAt DATE NOT NULL
);

CREATE TABLE Products (
    Id       INT IDENTITY(1,1) PRIMARY KEY,
    Name     NVARCHAR(100) NOT NULL,
    Category NVARCHAR(50)  NOT NULL,
    Price    DECIMAL(10,2) NOT NULL,
    Stock    INT NOT NULL
);

CREATE TABLE Orders (
    Id         INT IDENTITY(1,1) PRIMARY KEY,
    CustomerId INT NOT NULL REFERENCES Customers(Id),
    EmployeeId INT NOT NULL REFERENCES Employees(Id),
    OrderDate  DATE NOT NULL,
    Status     NVARCHAR(20) NOT NULL   -- Pending, Shipped, Delivered, Cancelled
);

CREATE TABLE OrderItems (
    Id        INT IDENTITY(1,1) PRIMARY KEY,
    OrderId   INT NOT NULL REFERENCES Orders(Id),
    ProductId INT NOT NULL REFERENCES Products(Id),
    Quantity  INT NOT NULL,
    UnitPrice DECIMAL(10,2) NOT NULL
);
GO

-- 3. Sample data
INSERT INTO Employees (Name, Department, Salary, ManagerId, HireDate) VALUES
(N'Laura Méndez',   N'Management', 180000, NULL, '2019-03-01'),  -- 1
(N'Carlos Peña',    N'Sales',       95000, 1,    '2020-06-15'),  -- 2
(N'Ana Rosario',    N'Sales',       70000, 2,    '2022-01-10'),  -- 3
(N'Pedro Guzmán',   N'Sales',       65000, 2,    '2023-04-03'),  -- 4
(N'María Santos',   N'IT',         120000, 1,    '2021-02-20'),  -- 5
(N'José Ramírez',   N'IT',          85000, 5,    '2023-09-11'),  -- 6
(N'Luisa Familia',  N'IT',          85000, 5,    '2024-05-06'),  -- 7
(N'Ramón Castillo', N'Warehouse',   50000, 1,    '2022-11-14');  -- 8

INSERT INTO Customers (Name, City, Email, CreatedAt) VALUES
(N'Constructora Bávaro',    N'Punta Cana',           'compras@cbavaro.do',     '2024-02-10'),
(N'Muebles del Cibao',      N'Santiago',             'info@mueblescibao.do',   '2024-05-22'),
(N'Hotel Costa Azul',       N'La Romana',            'it@costaazul.do',        '2024-08-01'),
(N'Farmacia San Rafael',    N'Santo Domingo',        'admin@sanrafael.do',     '2025-01-15'),
(N'Colmado El Progreso',    N'Santo Domingo Este',   'elprogreso@gmail.com',   '2025-03-03'),
(N'Taller Mecánico Díaz',   N'San Pedro de Macorís', 'tallerdiaz@gmail.com',   '2025-06-18'),
(N'Panadería La Espiga',    N'Santiago',             'laespiga@gmail.com',     '2025-09-09'),
(N'Oficina Legal Ruiz',     N'Santo Domingo',        'contacto@legalruiz.do',  '2026-01-20');  -- no orders yet

INSERT INTO Products (Name, Category, Price, Stock) VALUES
(N'Laptop Dell Latitude', N'Electronics', 55000, 12),  -- 1
(N'Monitor 24 in',        N'Electronics',  9500, 30),  -- 2
(N'Wireless Mouse',       N'Accessories',   850, 120), -- 3
(N'Mechanical Keyboard',  N'Accessories',  3200, 45),  -- 4
(N'Office Chair',         N'Furniture',   12500, 8),   -- 5
(N'Standing Desk',        N'Furniture',   24000, 5),   -- 6
(N'Printer HP LaserJet',  N'Electronics', 18000, 7),   -- 7
(N'USB-C Hub',            N'Accessories',  1900, 60),  -- 8
(N'Router WiFi 6',        N'Networking',   6500, 20),  -- 9
(N'UPS 1500VA',           N'Electronics', 11000, 0),   -- 10 (out of stock)
(N'Webcam HD',            N'Accessories',  2700, 25);  -- 11 (never sold)

INSERT INTO Orders (CustomerId, EmployeeId, OrderDate, Status) VALUES
(1, 3, '2026-01-12', 'Delivered'),  -- 1
(2, 3, '2026-01-25', 'Delivered'),  -- 2
(3, 4, '2026-02-03', 'Delivered'),  -- 3
(1, 3, '2026-02-18', 'Delivered'),  -- 4
(4, 4, '2026-03-07', 'Delivered'),  -- 5
(5, 3, '2026-03-21', 'Cancelled'),  -- 6
(2, 2, '2026-04-09', 'Delivered'),  -- 7
(6, 4, '2026-05-14', 'Delivered'),  -- 8
(7, 3, '2026-06-02', 'Delivered'),  -- 9
(3, 2, '2026-07-19', 'Delivered'),  -- 10
(1, 4, '2026-08-08', 'Shipped'),    -- 11
(4, 3, '2026-09-15', 'Shipped'),    -- 12
(2, 4, '2026-10-02', 'Pending'),    -- 13
(5, 3, '2026-10-20', 'Pending'),    -- 14
(6, 2, '2025-12-10', 'Delivered');  -- 15 (last year)

INSERT INTO OrderItems (OrderId, ProductId, Quantity, UnitPrice) VALUES
(1, 1, 3, 55000), (1, 3, 3, 850),
(2, 5, 4, 12500), (2, 6, 1, 24000),
(3, 2, 6, 9500),  (3, 4, 6, 3200),
(4, 1, 2, 55000), (4, 8, 2, 1900),
(5, 7, 1, 18000), (5, 9, 2, 6500),
(6, 3, 10, 850),
(7, 5, 2, 12500), (7, 4, 2, 3200),
(8, 9, 1, 6500),  (8, 3, 2, 850),
(9, 2, 2, 9500),  (9, 8, 4, 1900),
(10, 1, 5, 55000), (10, 10, 2, 11000),
(11, 6, 2, 24000), (11, 4, 3, 3200),
(12, 7, 2, 18000),
(13, 1, 1, 55000), (13, 3, 5, 850),
(14, 8, 3, 1900),
(15, 2, 3, 9500);
GO

/* =========================================================
   4. Your first queries — select one and run only that part
   ========================================================= */

-- All products
SELECT * FROM Products;

-- Some columns, filtered and sorted
SELECT Name, Price
FROM Products
WHERE Category = 'Accessories'
ORDER BY Price DESC;

-- JOIN: each order with its customer name
SELECT o.Id, c.Name AS Customer, o.OrderDate, o.Status
FROM Orders AS o
INNER JOIN Customers AS c ON c.Id = o.CustomerId
ORDER BY o.OrderDate;

-- GROUP BY: total sales per customer (cancelled orders excluded)
SELECT c.Name, SUM(oi.Quantity * oi.UnitPrice) AS TotalSales
FROM Customers AS c
JOIN Orders AS o      ON o.CustomerId = c.Id
JOIN OrderItems AS oi ON oi.OrderId  = o.Id
WHERE o.Status <> 'Cancelled'
GROUP BY c.Name
ORDER BY TotalSales DESC;

/* =========================================================
   5. Exercises — write your own answer under each one
   ========================================================= */

-- 1. Top 5 customers by total sales in 2026 (ignore cancelled orders).

-- 2. Number of orders and total sales per employee, only employees with more than 3 orders (HAVING).

-- 3. Customers who have never placed an order (LEFT JOIN + IS NULL).

-- 4. Products that were never sold.

-- 5. Each employee with their manager's name (self-join).

-- 6. Rank employees by salary inside each department; compare RANK and DENSE_RANK.

-- 7. The second-highest salary in each department (CTE + window function).

-- 8. Sales per month in 2026 with a running total (SUM() OVER (ORDER BY ...)).

-- 9. For each order, the days since the same customer's previous order (LAG).

-- 10. Write the PlaceOrder stored procedure from the learning path (Phase 1) and test it with EXEC.
