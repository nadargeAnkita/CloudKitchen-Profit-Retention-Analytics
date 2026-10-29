-- =====================================================================
-- 03_views_indexes.sql : reusable views + indexes (plain SQL only)
-- =====================================================================
USE cloudkitchen;

CREATE INDEX idx_orders_ts       ON orders (order_ts);
CREATE INDEX idx_orders_customer ON orders (customer_id, order_ts);
CREATE INDEX idx_orders_brand    ON orders (brand_id, kitchen_id);

-- One row per order with all money columns calculated
CREATE VIEW v_order_financials AS
SELECT o.order_id, o.customer_id, o.kitchen_id, o.brand_id, o.channel_id,
       o.order_ts, o.delivery_minutes, o.rating, o.discount_pct,
       SUM(oi.qty * m.price)                                   AS gross_sales,
       SUM(oi.qty * m.price) * o.discount_pct / 100            AS discount_amt,
       SUM(oi.qty * m.price) * (1 - o.discount_pct / 100)      AS net_sales,
       SUM(oi.qty * m.food_cost)                               AS food_cost,
       SUM(oi.qty * m.price) * (1 - o.discount_pct / 100)
            * ch.commission_pct / 100                          AS commission_amt
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN menu_items  m  ON m.item_id   = oi.item_id
JOIN channels    ch ON ch.channel_id = o.channel_id
GROUP BY o.order_id, o.customer_id, o.kitchen_id, o.brand_id, o.channel_id,
         o.order_ts, o.delivery_minutes, o.rating, o.discount_pct, ch.commission_pct;

-- Contribution = what is left after food cost and platform commission
CREATE VIEW v_order_profit AS
SELECT f.*, f.net_sales - f.food_cost - f.commission_amt AS contribution
FROM v_order_financials f;
