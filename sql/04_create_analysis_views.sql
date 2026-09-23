-- Olist e-commerce analysis
-- Create reusable order-level and customer-level analysis views.
-- This script does not modify source tables or reload any data.

USE olist;

CREATE OR REPLACE VIEW v_order_analytics AS
SELECT
  o.order_id,
  o.customer_id,
  c.customer_unique_id,
  c.customer_state,
  o.order_status,
  DATE(o.order_purchase_timestamp) AS purchase_date,
  DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS purchase_month,
  o.order_purchase_timestamp,
  o.order_approved_at,
  o.order_delivered_carrier_date,
  o.order_delivered_customer_date,
  o.order_estimated_delivery_date,
  COALESCE(p.payment_count, 0) AS payment_count,
  COALESCE(p.payment_total, 0.00) AS payment_total,
  COALESCE(p.payment_type_count, 0) AS payment_type_count,
  COALESCE(i.item_count, 0) AS item_count,
  COALESCE(i.item_total, 0.00) AS item_total,
  COALESCE(i.freight_total, 0.00) AS freight_total,
  COALESCE(i.seller_count, 0) AS seller_count,
  CASE
    WHEN COALESCE(p.payment_count, 0) > 0
      THEN COALESCE(p.payment_total, 0.00)
    ELSE COALESCE(i.item_total, 0.00)
  END AS recognized_gmv,
  COALESCE(r.review_count, 0) AS review_count,
  r.avg_review_score,
  r.min_review_score,
  CASE
    WHEN o.order_status = 'delivered' THEN 1
    ELSE 0
  END AS is_delivered,
  CASE
    WHEN o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
    THEN 1
    ELSE 0
  END AS has_delivery_dates,
  CASE
    WHEN o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
      AND o.order_delivered_customer_date > o.order_estimated_delivery_date
    THEN 1
    ELSE 0
  END AS is_late,
  CASE
    WHEN r.min_review_score IS NOT NULL
      AND r.min_review_score <= 2
    THEN 1
    ELSE 0
  END AS is_bad_review,
  TIMESTAMPDIFF(
    SECOND,
    o.order_purchase_timestamp,
    o.order_approved_at
  ) / 86400.0 AS approval_days,
  TIMESTAMPDIFF(
    SECOND,
    o.order_approved_at,
    o.order_delivered_carrier_date
  ) / 86400.0 AS seller_handling_days,
  TIMESTAMPDIFF(
    SECOND,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date
  ) / 86400.0 AS carrier_delivery_days,
  TIMESTAMPDIFF(
    SECOND,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date
  ) / 86400.0 AS total_delivery_days,
  TIMESTAMPDIFF(
    SECOND,
    o.order_estimated_delivery_date,
    o.order_delivered_customer_date
  ) / 86400.0 AS estimated_delay_days
FROM orders o
JOIN customers c
  ON c.customer_id = o.customer_id
LEFT JOIN (
  SELECT
    order_id,
    COUNT(*) AS payment_count,
    SUM(payment_value) AS payment_total,
    COUNT(DISTINCT payment_type) AS payment_type_count
  FROM order_payments
  GROUP BY order_id
) p
  ON p.order_id = o.order_id
LEFT JOIN (
  SELECT
    order_id,
    COUNT(*) AS item_count,
    SUM(price + freight_value) AS item_total,
    SUM(freight_value) AS freight_total,
    COUNT(DISTINCT seller_id) AS seller_count
  FROM order_items
  GROUP BY order_id
) i
  ON i.order_id = o.order_id
LEFT JOIN (
  SELECT
    order_id,
    COUNT(*) AS review_count,
    AVG(review_score) AS avg_review_score,
    MIN(review_score) AS min_review_score
  FROM order_reviews
  GROUP BY order_id
) r
  ON r.order_id = o.order_id;

CREATE OR REPLACE VIEW v_customer_analytics AS
SELECT
  customer_unique_id,
  COUNT(*) AS delivered_orders,
  SUM(recognized_gmv) AS customer_gmv,
  MIN(order_purchase_timestamp) AS first_order_at,
  MAX(order_purchase_timestamp) AS last_order_at,
  SUM(
    CASE WHEN review_count > 0 THEN 1 ELSE 0 END
  ) AS reviewed_orders,
  SUM(is_bad_review) AS bad_review_orders,
  SUM(
    CASE WHEN has_delivery_dates = 1 THEN 1 ELSE 0 END
  ) AS orders_with_delivery_dates,
  SUM(is_late) AS late_orders,
  AVG(
    CASE
      WHEN review_count > 0 THEN avg_review_score
    END
  ) AS avg_review_score,
  CASE
    WHEN COUNT(*) >= 2 THEN 1
    ELSE 0
  END AS is_repeat_customer
FROM v_order_analytics
WHERE is_delivered = 1
GROUP BY customer_unique_id;
