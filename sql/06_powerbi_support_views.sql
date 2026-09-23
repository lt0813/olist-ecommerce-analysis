-- Olist e-commerce analysis
-- Supporting views for category and seller report pages.
-- These views are read-only and do not modify source tables or reload data.

USE olist;

CREATE OR REPLACE VIEW v_order_item_analytics AS
SELECT
  oa.order_id,
  oa.customer_unique_id,
  oa.customer_state,
  oa.purchase_date,
  oa.purchase_month,
  oi.order_item_id,
  oi.product_id,
  p.product_category_name,
  COALESCE(
    t.product_category_name_english,
    p.product_category_name,
    'unknown'
  ) AS category_name,
  oi.seller_id,
  s.seller_state,
  s.seller_city,
  oi.price,
  oi.freight_value,
  oi.price + oi.freight_value AS item_total,
  oa.review_count,
  oa.avg_review_score,
  oa.has_delivery_dates,
  oa.is_late,
  oa.is_bad_review,
  oa.seller_handling_days,
  oa.carrier_delivery_days,
  oa.total_delivery_days
FROM v_order_analytics oa
JOIN order_items oi
  ON oi.order_id = oa.order_id
JOIN products p
  ON p.product_id = oi.product_id
LEFT JOIN product_category_translation t
  ON t.product_category_name = p.product_category_name
LEFT JOIN sellers s
  ON s.seller_id = oi.seller_id
WHERE oa.is_delivered = 1;

CREATE OR REPLACE VIEW v_category_analytics AS
WITH category_orders AS (
  SELECT
    category_name,
    order_id,
    SUM(price + freight_value) AS category_order_gmv
  FROM v_order_item_analytics
  GROUP BY category_name, order_id
),
category_items AS (
  SELECT
    category_name,
    COUNT(*) AS item_rows,
    COUNT(DISTINCT product_id) AS product_count,
    SUM(price + freight_value) AS category_gmv,
    SUM(price) AS product_value,
    SUM(freight_value) AS freight_value,
    AVG(price) AS average_item_price
  FROM v_order_item_analytics
  GROUP BY category_name
),
category_metrics AS (
  SELECT
    co.category_name,
    COUNT(*) AS delivered_orders,
    SUM(
      CASE
        WHEN oa.has_delivery_dates = 1 THEN oa.is_late
        ELSE 0
      END
    ) AS late_orders,
    SUM(oa.has_delivery_dates) AS orders_with_delivery_dates,
    SUM(
      CASE
        WHEN oa.review_count > 0 THEN 1
        ELSE 0
      END
    ) AS reviewed_orders,
    SUM(
      CASE
        WHEN oa.review_count > 0 THEN oa.is_bad_review
        ELSE 0
      END
    ) AS bad_review_orders,
    AVG(
      CASE
        WHEN oa.review_count > 0 THEN oa.avg_review_score
      END
    ) AS average_review_score
  FROM category_orders co
  JOIN v_order_analytics oa
    ON oa.order_id = co.order_id
  GROUP BY co.category_name
)
SELECT
  ci.category_name,
  cm.delivered_orders,
  ci.item_rows,
  ci.product_count,
  ROUND(ci.category_gmv, 2) AS category_gmv,
  ROUND(ci.product_value, 2) AS product_value,
  ROUND(ci.freight_value, 2) AS freight_value,
  ROUND(ci.average_item_price, 2) AS average_item_price,
  ROUND(
    100.0 * ci.category_gmv
      / NULLIF(SUM(ci.category_gmv) OVER (), 0),
    2
  ) AS gmv_share_pct,
  ROUND(
    100.0 * cm.late_orders
      / NULLIF(cm.orders_with_delivery_dates, 0),
    2
  ) AS late_order_rate_pct,
  ROUND(
    100.0 * cm.bad_review_orders
      / NULLIF(cm.reviewed_orders, 0),
    2
  ) AS bad_review_rate_pct,
  ROUND(cm.average_review_score, 2) AS average_review_score
FROM category_items ci
JOIN category_metrics cm
  ON cm.category_name = ci.category_name;

CREATE OR REPLACE VIEW v_seller_risk_analytics AS
WITH seller_orders AS (
  SELECT
    seller_id,
    order_id,
    SUM(item_total) AS seller_order_gmv
  FROM v_order_item_analytics
  GROUP BY seller_id, order_id
),
seller_metrics AS (
  SELECT
    so.seller_id,
    COUNT(*) AS delivered_orders,
    SUM(so.seller_order_gmv) AS seller_gmv,
    SUM(oa.has_delivery_dates) AS orders_with_delivery_dates,
    SUM(
      CASE
        WHEN oa.has_delivery_dates = 1 THEN oa.is_late
        ELSE 0
      END
    ) AS late_orders,
    SUM(
      CASE
        WHEN oa.review_count > 0 THEN 1
        ELSE 0
      END
    ) AS reviewed_orders,
    SUM(
      CASE
        WHEN oa.review_count > 0 THEN oa.is_bad_review
        ELSE 0
      END
    ) AS bad_review_orders,
    AVG(
      CASE
        WHEN oa.has_delivery_dates = 1 THEN oa.seller_handling_days
      END
    ) AS average_seller_handling_days,
    AVG(
      CASE
        WHEN oa.has_delivery_dates = 1 THEN oa.carrier_delivery_days
      END
    ) AS average_carrier_delivery_days,
    AVG(
      CASE
        WHEN oa.review_count > 0 THEN oa.avg_review_score
      END
    ) AS average_review_score
  FROM seller_orders so
  JOIN v_order_analytics oa
    ON oa.order_id = so.order_id
  GROUP BY so.seller_id
),
seller_rates AS (
  SELECT
    sm.*,
    100.0 * sm.late_orders
      / NULLIF(sm.orders_with_delivery_dates, 0) AS late_order_rate_pct,
    100.0 * sm.bad_review_orders
      / NULLIF(sm.reviewed_orders, 0) AS bad_review_rate_pct
  FROM seller_metrics sm
)
SELECT
  sr.seller_id,
  LEFT(sr.seller_id, 8) AS seller_short_id,
  s.seller_state,
  s.seller_city,
  sr.delivered_orders,
  ROUND(sr.seller_gmv, 2) AS seller_gmv,
  sr.late_orders,
  sr.orders_with_delivery_dates,
  ROUND(sr.late_order_rate_pct, 2) AS late_order_rate_pct,
  sr.reviewed_orders,
  sr.bad_review_orders,
  ROUND(sr.bad_review_rate_pct, 2) AS bad_review_rate_pct,
  ROUND(sr.average_seller_handling_days, 2)
    AS average_seller_handling_days,
  ROUND(sr.average_carrier_delivery_days, 2)
    AS average_carrier_delivery_days,
  ROUND(sr.average_review_score, 2) AS average_review_score,
  ROUND(
    100.0 * sr.seller_gmv
      / NULLIF(SUM(sr.seller_gmv) OVER (), 0),
    2
  ) AS seller_gmv_share_pct,
  CASE
    WHEN sr.delivered_orders >= 200
      AND sr.late_order_rate_pct >= 12
      AND sr.bad_review_rate_pct >= 18
    THEN 'high_risk'
    WHEN sr.delivered_orders >= 200
      AND (
        sr.late_order_rate_pct >= 12
        OR sr.bad_review_rate_pct >= 18
      )
    THEN 'watchlist'
    ELSE 'normal'
  END AS risk_tier,
  CASE
    WHEN sr.delivered_orders >= 200
      AND sr.late_order_rate_pct >= 12
      AND sr.bad_review_rate_pct >= 18
    THEN '延迟与差评双高'
    WHEN sr.delivered_orders >= 200
      AND sr.late_order_rate_pct >= 12
    THEN '延迟率偏高'
    WHEN sr.delivered_orders >= 200
      AND sr.bad_review_rate_pct >= 18
    THEN '差评率偏高'
    ELSE '正常'
  END AS risk_reason,
  CASE
    WHEN sr.delivered_orders >= 200
      AND (
        sr.late_order_rate_pct >= 12
        OR sr.bad_review_rate_pct >= 18
      )
    THEN 1
    ELSE 0
  END AS is_risk_candidate
FROM seller_rates sr
LEFT JOIN sellers s
  ON s.seller_id = sr.seller_id;
