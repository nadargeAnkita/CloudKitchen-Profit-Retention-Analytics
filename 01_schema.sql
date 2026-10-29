-- =====================================================================
-- CloudKitchen Profit & Retention Analytics  |  01_schema.sql
-- Pure standard SQL (MySQL 8+). No stored procedures, triggers or PL/SQL.
-- =====================================================================
DROP DATABASE IF EXISTS cloudkitchen;
CREATE DATABASE cloudkitchen;
USE cloudkitchen;

CREATE TABLE kitchens (
    kitchen_id      INT PRIMARY KEY,
    kitchen_name    VARCHAR(50) NOT NULL,
    area            VARCHAR(50) NOT NULL,
    monthly_rent    DECIMAL(10,2) NOT NULL,   -- fixed cost
    monthly_staff   DECIMAL(10,2) NOT NULL    -- fixed cost
);

CREATE TABLE brands (
    brand_id    INT PRIMARY KEY,
    brand_name  VARCHAR(50) NOT NULL,
    cuisine     VARCHAR(30) NOT NULL
);

CREATE TABLE menu_items (
    item_id     INT PRIMARY KEY,
    brand_id    INT NOT NULL,
    item_no     INT NOT NULL,                 -- 1..4 inside a brand
    item_name   VARCHAR(60) NOT NULL,
    price       DECIMAL(8,2) NOT NULL,
    food_cost   DECIMAL(8,2) NOT NULL,        -- ingredients + packaging
    FOREIGN KEY (brand_id) REFERENCES brands(brand_id),
    UNIQUE (brand_id, item_no)
);

CREATE TABLE channels (
    channel_id      INT PRIMARY KEY,
    channel_name    VARCHAR(30) NOT NULL,
    commission_pct  DECIMAL(5,2) NOT NULL     -- % of order value paid to platform
);

CREATE TABLE customers (
    customer_id  INT PRIMARY KEY,
    signup_date  DATE NOT NULL,
    locality     VARCHAR(40) NOT NULL
);

CREATE TABLE orders (
    order_id          INT PRIMARY KEY,
    customer_id       INT NOT NULL,
    kitchen_id        INT NOT NULL,
    brand_id          INT NOT NULL,
    channel_id        INT NOT NULL,
    order_ts          DATETIME NOT NULL,
    discount_pct      DECIMAL(5,2) NOT NULL DEFAULT 0,
    delivery_minutes  INT NOT NULL,
    rating            INT NULL,               -- 1..5, NULL = not rated
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (kitchen_id)  REFERENCES kitchens(kitchen_id),
    FOREIGN KEY (brand_id)    REFERENCES brands(brand_id),
    FOREIGN KEY (channel_id)  REFERENCES channels(channel_id)
);

CREATE TABLE order_items (
    order_id  INT NOT NULL,
    line_no   INT NOT NULL,
    item_id   INT NOT NULL,
    qty       INT NOT NULL,
    PRIMARY KEY (order_id, line_no),
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (item_id)  REFERENCES menu_items(item_id)
);
