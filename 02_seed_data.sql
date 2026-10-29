-- =====================================================================
-- 02_seed_data.sql : reference data + 3,000 customers + 3,000 orders
-- Data is generated with plain SQL (digit cross-join + seeded RAND),
-- so results are repeatable on every run.
-- =====================================================================
USE cloudkitchen;

INSERT INTO kitchens VALUES
 (1,'Hinjewadi Hub','Hinjewadi',45000,42000),
 (2,'Kothrud Kitchen','Kothrud',38000,40000),
 (3,'Viman Nagar Base','Viman Nagar',60000,48000),
 (4,'Baner Box','Baner',42000,41000);

INSERT INTO brands VALUES
 (1,'Biryani Junction','Hyderabadi'),
 (2,'Pizza Pronto','Italian'),
 (3,'Wrap Republic','Street Food'),
 (4,'Dosa Dhaba','South Indian'),
 (5,'Bowl Theory','Healthy');

INSERT INTO menu_items VALUES
 (1,1,1,'Chicken Dum Biryani',280,110),(2,1,2,'Veg Biryani',220,70),
 (3,1,3,'Mutton Biryani',380,210),(4,1,4,'Raita Combo',60,12),
 (5,2,1,'Margherita Pizza',240,75),(6,2,2,'Farmhouse Pizza',320,105),
 (7,2,3,'Garlic Bread',120,28),(8,2,4,'Pasta Alfredo',260,95),
 (9,3,1,'Paneer Tikka Wrap',150,48),(10,3,2,'Chicken Kathi Roll',170,62),
 (11,3,3,'Loaded Fries',110,30),(12,3,4,'Cold Coffee',90,22),
 (13,4,1,'Masala Dosa',110,28),(14,4,2,'Idli Vada Combo',90,22),
 (15,4,3,'Mysore Dosa',130,36),(16,4,4,'Filter Coffee',50,10),
 (17,5,1,'Quinoa Power Bowl',290,135),(18,5,2,'Grilled Chicken Bowl',310,140),
 (19,5,3,'Fruit Smoothie',140,52),(20,5,4,'Protein Salad',260,118);

INSERT INTO channels VALUES
 (1,'Own App',0),(2,'Swiggy',24),(3,'Zomato',26);

-- helper digits table (dropped at the end)
CREATE TABLE digits (d INT PRIMARY KEY);
INSERT INTO digits VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);

-- 3,000 customers
INSERT INTO customers (customer_id, signup_date, locality)
SELECT n, DATE_ADD('2025-12-01', INTERVAL FLOOR(RAND(n*5) * 200) DAY),
       ELT(1 + FLOOR(RAND(n*9) * 6),'Wakad','Baner','Aundh','Kothrud','Viman Nagar','Hinjewadi')
FROM (SELECT a.d*1000 + b.d*100 + c.d*10 + e.d + 1 AS n
      FROM digits a, digits b, digits c, digits e) x
WHERE n <= 3000;

-- 15,000 orders (customer ordering only after signup; skewed toward weekends/evenings)
INSERT INTO orders (order_id, customer_id, kitchen_id, brand_id, channel_id,
                    order_ts, discount_pct, delivery_minutes, rating)
SELECT o.n, c.customer_id,
       1 + FLOOR(RAND(o.n*3) * 4),
       1 + FLOOR(RAND(o.n*7) * 5),
       CASE WHEN RAND(o.n*13) < 0.30 THEN 1
            WHEN RAND(o.n*13) < 0.68 THEN 2 ELSE 3 END,
       DATE_ADD(
         -- orders cluster soon after signup and thin out (natural churn)
         DATE_ADD(c.signup_date,
                  INTERVAL FLOOR(POWER(RAND(o.n*17), 3) * DATEDIFF('2026-08-31', c.signup_date)) DAY),
         INTERVAL (CASE WHEN RAND(o.n*19) < 0.55 THEN 19 + FLOOR(RAND(o.n*23)*3)
                        ELSE 11 + FLOOR(RAND(o.n*29)*9) END) HOUR)
         + INTERVAL FLOOR(RAND(o.n*31)*60) MINUTE,
       CASE WHEN RAND(o.n*37) < 0.35 THEN 20 WHEN RAND(o.n*37) < 0.55 THEN 10 ELSE 0 END,
       22 + FLOOR(RAND(o.n*41) * 30),
       CASE WHEN RAND(o.n*43) < 0.35 THEN NULL ELSE 1 + FLOOR(RAND(o.n*47) * 5) END
FROM (SELECT a.d*10000 + b.d*1000 + c.d*100 + e.d*10 + f.d + 1 AS n
      FROM digits a, digits b, digits c, digits e, digits f) o
-- skewed pick: a few loyal customers order a lot, many order once or twice
JOIN customers c ON c.customer_id = 1 + FLOOR(POWER(RAND(o.n*2), 2) * 3000)
WHERE o.n <= 15000;

-- Late deliveries (>40 min) get lower ratings: realistic signal for analysis
UPDATE orders SET rating = GREATEST(1, rating - 2)
WHERE delivery_minutes > 40 AND rating IS NOT NULL;

-- order lines: 1 to 3 lines per order, items always from the order's brand
INSERT INTO order_items (order_id, line_no, item_id, qty)
SELECT o.order_id, k.line_no, m.item_id, 1 + FLOOR(RAND(o.order_id*53 + k.line_no) * 2)
FROM orders o
JOIN (SELECT 1 AS line_no UNION SELECT 2 UNION SELECT 3) k
  ON k.line_no = 1 OR RAND(o.order_id*59 + k.line_no) < 0.45
JOIN menu_items m
  ON m.brand_id = o.brand_id
 AND m.item_no  = 1 + FLOOR(POWER(RAND(o.order_id*61 + k.line_no), 1.4) * 4);

DROP TABLE digits;
