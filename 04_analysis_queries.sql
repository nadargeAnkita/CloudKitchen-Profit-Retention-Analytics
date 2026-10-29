-- =====================================================================
-- 04_analysis_queries.sql : 10 business questions, answered in plain SQL
-- Techniques: JOINs, CTEs, window functions, CASE, views, self-joins
-- =====================================================================
USE cloudkitchen;

-- Q1. Monthly net sales and month-over-month growth  [LAG]
WITH monthly AS (
    SELECT DATE_FORMAT(order_ts, '%Y-%m') AS month,
           COUNT(*) AS orders, ROUND(SUM(net_sales), 0) AS net_sales
    FROM v_order_profit
    GROUP BY DATE_FORMAT(order_ts, '%Y-%m')
)
SELECT month, orders, net_sales,
       ROUND(100 * (net_sales - LAG(net_sales) OVER (ORDER BY month))
             / LAG(net_sales) OVER (ORDER BY month), 1) AS mom_growth_pct
FROM monthly
ORDER BY month;

-- Q2. Brand P&L: which virtual brand actually makes money?
SELECT b.brand_name,
       COUNT(*)                          AS orders,
       ROUND(SUM(p.gross_sales), 0)      AS gross_sales,
       ROUND(SUM(p.discount_amt), 0)     AS discounts,
       ROUND(SUM(p.food_cost), 0)        AS food_cost,
       ROUND(SUM(p.commission_amt), 0)   AS commission,
       ROUND(SUM(p.contribution), 0)     AS contribution,
       ROUND(100 * SUM(p.contribution) / SUM(p.gross_sales), 1) AS contribution_pct
FROM v_order_profit p
JOIN brands b ON b.brand_id = p.brand_id
GROUP BY b.brand_name
ORDER BY contribution DESC;

-- Q3. Kitchen profitability AFTER fixed costs (rent + staff for the period)
WITH months AS (
    SELECT COUNT(DISTINCT DATE_FORMAT(order_ts, '%Y-%m')) AS n FROM orders
)
SELECT k.kitchen_name,
       ROUND(SUM(p.contribution), 0)                                   AS contribution,
       (k.monthly_rent + k.monthly_staff) * m.n                        AS fixed_costs,
       ROUND(SUM(p.contribution) - (k.monthly_rent + k.monthly_staff) * m.n, 0) AS operating_profit
FROM v_order_profit p
JOIN kitchens k ON k.kitchen_id = p.kitchen_id
CROSS JOIN months m
GROUP BY k.kitchen_id, k.kitchen_name, k.monthly_rent, k.monthly_staff, m.n
ORDER BY operating_profit DESC;

-- Q4. Channel truth: aggregator sales look big, but what is the margin?
SELECT ch.channel_name,
       COUNT(*) AS orders,
       ROUND(AVG(p.net_sales), 0)    AS avg_order_value,
       ROUND(SUM(p.contribution), 0) AS contribution,
       ROUND(100 * SUM(p.contribution) / SUM(p.net_sales), 1) AS margin_pct
FROM v_order_profit p
JOIN channels ch ON ch.channel_id = p.channel_id
GROUP BY ch.channel_name
ORDER BY margin_pct DESC;

-- Q5. Cohort retention: % of customers still ordering N months after first order
WITH first_order AS (
    SELECT customer_id, DATE_FORMAT(MIN(order_ts), '%Y-%m-01') AS cohort_month
    FROM orders GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT o.customer_id, f.cohort_month,
           TIMESTAMPDIFF(MONTH, f.cohort_month, o.order_ts) AS month_no
    FROM orders o JOIN first_order f ON f.customer_id = o.customer_id
)
SELECT cohort_month,
       COUNT(DISTINCT CASE WHEN month_no = 0 THEN customer_id END) AS cohort_size,
       ROUND(100 * COUNT(DISTINCT CASE WHEN month_no = 1 THEN customer_id END)
             / COUNT(DISTINCT CASE WHEN month_no = 0 THEN customer_id END), 1) AS m1_pct,
       ROUND(100 * COUNT(DISTINCT CASE WHEN month_no = 2 THEN customer_id END)
             / COUNT(DISTINCT CASE WHEN month_no = 0 THEN customer_id END), 1) AS m2_pct
FROM activity
GROUP BY cohort_month
ORDER BY cohort_month;

-- Q6. RFM customer segments  [NTILE]
WITH rfm_raw AS (
    SELECT customer_id,
           DATEDIFF((SELECT MAX(order_ts) FROM orders), MAX(order_ts)) AS recency_days,
           COUNT(*)                AS frequency,
           ROUND(SUM(net_sales),0) AS monetary
    FROM v_order_profit GROUP BY customer_id
),
scored AS (
    SELECT *,
           NTILE(4) OVER (ORDER BY recency_days DESC) AS r,
           NTILE(4) OVER (ORDER BY frequency)         AS f,
           NTILE(4) OVER (ORDER BY monetary)          AS m
    FROM rfm_raw
)
SELECT CASE WHEN r >= 3 AND f >= 3 THEN 'Champions'
            WHEN r >= 3              THEN 'Recent / Promising'
            WHEN f >= 3              THEN 'At Risk (loyal but quiet)'
            ELSE 'Lost / Low value' END AS segment,
       COUNT(*)                AS customers,
       ROUND(AVG(monetary), 0) AS avg_spend
FROM scored
GROUP BY segment
ORDER BY avg_spend DESC;

-- Q7. Peak hours and delivery SLA: do late orders hurt ratings?
SELECT HOUR(order_ts) AS hour_of_day,
       COUNT(*) AS orders,
       ROUND(AVG(delivery_minutes), 1) AS avg_delivery_min,
       ROUND(100 * AVG(delivery_minutes > 40), 1) AS late_pct,
       ROUND(AVG(rating), 2) AS avg_rating
FROM orders
GROUP BY HOUR(order_ts)
ORDER BY hour_of_day;

SELECT CASE WHEN delivery_minutes > 40 THEN 'Late (>40 min)' ELSE 'On time' END AS sla,
       COUNT(*) AS orders, ROUND(AVG(rating), 2) AS avg_rating
FROM orders WHERE rating IS NOT NULL
GROUP BY sla;

-- Q8. Menu engineering: Stars / Plowhorses / Puzzles / Dogs
WITH item_stats AS (
    SELECT m.item_id, m.item_name, b.brand_name,
           SUM(oi.qty)                           AS units_sold,
           ROUND(AVG(m.price - m.food_cost), 1)  AS unit_margin
    FROM order_items oi
    JOIN menu_items m ON m.item_id = oi.item_id
    JOIN brands b     ON b.brand_id = m.brand_id
    GROUP BY m.item_id, m.item_name, b.brand_name
)
SELECT item_name, brand_name, units_sold, unit_margin,
       CASE WHEN units_sold >= AVG(units_sold) OVER () AND unit_margin >= AVG(unit_margin) OVER () THEN 'Star'
            WHEN units_sold >= AVG(units_sold) OVER ()                                           THEN 'Plowhorse'
            WHEN unit_margin >= AVG(unit_margin) OVER ()                                         THEN 'Puzzle'
            ELSE 'Dog' END AS category
FROM item_stats
ORDER BY category, units_sold DESC;

-- Q9. Market-basket: item pairs most often bought together  [self-join]
SELECT m1.item_name AS item_a, m2.item_name AS item_b, COUNT(*) AS times_together
FROM order_items a
JOIN order_items b  ON a.order_id = b.order_id AND a.item_id < b.item_id
JOIN menu_items m1  ON m1.item_id = a.item_id
JOIN menu_items m2  ON m2.item_id = b.item_id
GROUP BY m1.item_name, m2.item_name
ORDER BY times_together DESC
LIMIT 10;

-- Q10. Do discounts buy loyalty? Repeat-order rate within 30 days of a customer's FIRST order
WITH ranked AS (
    SELECT customer_id, order_ts, discount_pct,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_ts) AS rn
    FROM orders
),
first_o AS (SELECT * FROM ranked WHERE rn = 1),
second_o AS (SELECT * FROM ranked WHERE rn = 2)
SELECT CASE WHEN f.discount_pct > 0 THEN 'First order discounted' ELSE 'First order full price' END AS first_order_type,
       COUNT(*) AS customers,
       ROUND(100 * AVG(s.order_ts IS NOT NULL AND DATEDIFF(s.order_ts, f.order_ts) <= 30), 1) AS repeat_30d_pct
FROM first_o f
LEFT JOIN second_o s ON s.customer_id = f.customer_id
GROUP BY first_order_type;
