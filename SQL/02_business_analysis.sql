/* ============================================================
   E-COMMERCE DATA ANALYTICS PROJECT — SQL SOLUTION (PostgreSQL)
   ============================================================ */

SELECT current_database();


-- 0. DATA QUALITY CHECKS
SELECT COUNT(*) AS customers_count FROM customers;
SELECT COUNT(*) AS orders_count FROM orders;

SELECT
    COUNT(*) FILTER (WHERE payment_method IS NULL) AS missing_payment_method,
    COUNT(*) FILTER (WHERE customer_rating IS NULL) AS missing_rating,
    COUNT(*) FILTER (WHERE total_amount < 0) AS negative_totals
FROM orders;

-- Verify financial consistency (allowing 0.02 rounding tolerance).
SELECT COUNT(*) AS inconsistent_rows
FROM orders
WHERE order_status <> 'Cancelled'
  AND ABS(total_amount - ((subtotal * (1 - discount_percent / 100.0))
      + shipping_cost + tax_amount)) > 0.02;

-- 1. EXECUTIVE KPIs
SELECT
    COUNT(*) AS total_orders,
    COUNT(DISTINCT customer_id) AS purchasing_customers,
    ROUND(SUM(total_amount), 2) AS net_revenue,
    ROUND(AVG(NULLIF(total_amount, 0)), 2) AS average_order_value,
    ROUND(100.0 * COUNT(*) FILTER (WHERE order_status = 'Returned') / COUNT(*), 2) AS return_rate_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE order_status = 'Cancelled') / COUNT(*), 2) AS cancellation_rate_pct
FROM orders;

-- 2. MONTHLY REVENUE, GROWTH AND 3-MONTH MOVING AVERAGE
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', order_date)::date AS month,
        SUM(total_amount) AS revenue,
        COUNT(*) AS orders
    FROM orders
    GROUP BY 1
)
SELECT
    month,
    ROUND(revenue, 2) AS revenue,
    orders,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
          / NULLIF(LAG(revenue) OVER (ORDER BY month), 0), 2) AS mom_growth_pct,
    ROUND(AVG(revenue) OVER (
        ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS revenue_3m_moving_avg
FROM monthly
ORDER BY month;

-- BUSINESS QUESTION 1:

-- Which categories and products drive the most profitable growth?

WITH product_perf AS (
    SELECT
        product_category,
        product_name,
        SUM(total_amount) AS revenue,
        SUM(quantity) AS units_sold,
        AVG(NULLIF(total_amount, 0)) AS avg_order_value,
        AVG(discount_percent) AS avg_discount_pct,
        SUM(shipping_cost) AS shipping_cost,
        COUNT(*) FILTER (WHERE order_status = 'Returned') AS returns,
        COUNT(*) AS orders
    FROM orders
    GROUP BY 1,2
)
SELECT
    *,
    ROUND(100.0 * returns / NULLIF(orders,0), 2) AS return_rate_pct,
    DENSE_RANK() OVER (ORDER BY revenue DESC) AS revenue_rank
FROM product_perf
ORDER BY revenue DESC;

-- Category-level year-over-year growth.
WITH yearly_category AS (
    SELECT
        EXTRACT(YEAR FROM order_date)::int AS year,
        product_category,
        SUM(total_amount) AS revenue
    FROM orders
    GROUP BY 1,2
)
SELECT
    year,
    product_category,
    ROUND(revenue,2) AS revenue,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (
        PARTITION BY product_category ORDER BY year
    )) / NULLIF(LAG(revenue) OVER (
        PARTITION BY product_category ORDER BY year
    ),0), 2) AS yoy_growth_pct
FROM yearly_category
ORDER BY product_category, year;



-- BUSINESS QUESTION 2:

-- Which behaviors predict retention and repeat purchasing?

WITH customer_metrics AS (
    SELECT
        c.customer_id,
        c.loyalty_tier,
        c.acquisition_channel,
        c.preferred_device,
        COUNT(o.order_id) AS order_count,
        COALESCE(SUM(o.total_amount),0) AS lifetime_value,
        COUNT(DISTINCT o.product_category) AS category_diversity,
        MIN(o.order_date) AS first_order_date,
        MAX(o.order_date) AS last_order_date,
        CASE WHEN COUNT(o.order_id) >= 2 THEN 1 ELSE 0 END AS repeat_customer
    FROM customers c
    LEFT JOIN orders o ON c.customer_id = o.customer_id
    GROUP BY 1,2,3,4
)
SELECT
    loyalty_tier,
    acquisition_channel,
    COUNT(*) AS customers,
    ROUND(AVG(order_count),2) AS avg_orders,
    ROUND(AVG(lifetime_value),2) AS avg_ltv,
    ROUND(AVG(category_diversity),2) AS avg_category_diversity,
    ROUND(100.0 * AVG(repeat_customer),2) AS repeat_customer_rate_pct
FROM customer_metrics
GROUP BY 1,2
ORDER BY repeat_customer_rate_pct DESC, avg_ltv DESC;


-- RFM-style segmentation.
WITH rfm_base AS (
    SELECT
        c.customer_id,
        (DATE '2026-01-01' - MAX(o.order_date)) AS recency_days,
        COUNT(o.order_id) AS frequency,
        SUM(o.total_amount) AS monetary
    FROM customers c
    LEFT JOIN orders o ON c.customer_id = o.customer_id
    GROUP BY c.customer_id
),
rfm_scores AS (
    SELECT *,
        NTILE(4) OVER (ORDER BY recency_days DESC NULLS FIRST) AS r_score,
        NTILE(4) OVER (ORDER BY frequency) AS f_score,
        NTILE(4) OVER (ORDER BY monetary) AS m_score
    FROM rfm_base
)
SELECT
    customer_id, recency_days, frequency, ROUND(monetary,2) AS monetary,
    r_score, f_score, m_score,
    CASE
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 2 THEN 'Loyal'
        WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk'
        WHEN frequency = 0 THEN 'Inactive'
        ELSE 'Developing'
    END AS rfm_segment
FROM rfm_scores
ORDER BY monetary DESC NULLS LAST;



-- BUSINESS QUESTION 3:

-- Where does the order experience break down?
SELECT
    product_category,
    shipping_method,
    COUNT(*) AS orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE order_status='Cancelled') / COUNT(*),2) AS cancellation_rate_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE order_status='Returned') / COUNT(*),2) AS return_rate_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE order_status='Delayed') / COUNT(*),2) AS delayed_rate_pct,
    ROUND(AVG(delivery_days),2) AS avg_delivery_days,
    ROUND(AVG(customer_rating),2) AS avg_rating,
    ROUND(SUM(total_amount) FILTER (WHERE order_status IN ('Cancelled','Returned')),2) AS revenue_at_risk
FROM orders
GROUP BY 1,2
ORDER BY revenue_at_risk DESC NULLS LAST;



-- BUSINESS QUESTION 4:

-- Which promotions increase order value without over-discounting?
SELECT
    CASE
        WHEN discount_percent = 0 THEN '0%'
        WHEN discount_percent <= 10 THEN '1-10%'
        WHEN discount_percent <= 20 THEN '11-20%'
        ELSE '21%+'
    END AS discount_band,
    COUNT(*) AS orders,
    ROUND(AVG(subtotal),2) AS avg_gross_basket,
    ROUND(AVG(total_amount),2) AS avg_net_order_value,
    ROUND(AVG(quantity),2) AS avg_units,
    ROUND(SUM(total_amount),2) AS net_revenue,
    ROUND(100.0 * COUNT(*) FILTER (WHERE order_status='Returned') / COUNT(*),2) AS return_rate_pct
FROM orders
GROUP BY 1
ORDER BY 1;

-- Coupon performance.
SELECT
    COALESCE(coupon_code,'No coupon') AS coupon_code,
    COUNT(*) AS orders,
    ROUND(AVG(discount_percent),2) AS avg_discount_pct,
    ROUND(AVG(total_amount),2) AS avg_order_value,
    ROUND(SUM(total_amount),2) AS revenue,
    ROUND(100.0 * COUNT(*) FILTER (WHERE order_status='Returned') / COUNT(*),2) AS return_rate_pct
FROM orders
GROUP BY 1
ORDER BY revenue DESC;



-- BUSINESS QUESTION 5:

-- How do seasonality and customer segments affect product demand?

SELECT
    EXTRACT(YEAR FROM order_date)::int AS year,
    EXTRACT(MONTH FROM order_date)::int AS month,
    product_category,
    c.loyalty_tier,
    c.age / 10 * 10 AS age_band_start,
    c.country,
    SUM(quantity) AS units,
    ROUND(SUM(total_amount),2) AS revenue
FROM orders o
JOIN customers c USING (customer_id)
GROUP BY 1,2,3,4,5,6
ORDER BY year, month, revenue DESC;


-- Market-basket style category affinity by customer.
WITH customer_categories AS (
    SELECT DISTINCT customer_id, product_category
    FROM orders
),
pairs AS (
    SELECT
        a.product_category AS category_a,
        b.product_category AS category_b,
        COUNT(DISTINCT a.customer_id) AS customers_buying_both
    FROM customer_categories a
    JOIN customer_categories b
      ON a.customer_id = b.customer_id
     AND a.product_category < b.product_category
    GROUP BY 1,2
)
SELECT *
FROM pairs
ORDER BY customers_buying_both DESC;

-- Pareto analysis: what percentage of customers generate 80% of revenue?

WITH customer_revenue AS (
    SELECT customer_id, SUM(total_amount) AS revenue
    FROM orders
    GROUP BY customer_id
),
ranked AS (
    SELECT *,
        SUM(revenue) OVER (ORDER BY revenue DESC) AS cumulative_revenue,
        SUM(revenue) OVER () AS total_revenue,
        ROW_NUMBER() OVER (ORDER BY revenue DESC) AS customer_rank,
        COUNT(*) OVER () AS customer_count
    FROM customer_revenue
)
SELECT
    MIN(100.0 * customer_rank / customer_count) AS pct_customers_to_reach_80pct_revenue
FROM ranked
WHERE cumulative_revenue / total_revenue >= 0.80;
