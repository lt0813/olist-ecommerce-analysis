-- Run after all nine CSV files have been imported.
-- This script only reads data.

USE olist;

-- 1. Row counts
SELECT 'product_category_translation' AS table_name, COUNT(*) AS row_count FROM product_category_translation
UNION ALL
SELECT 'customers', COUNT(*) FROM customers
UNION ALL
SELECT 'geolocation', COUNT(*) FROM geolocation
UNION ALL
SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL
SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL
SELECT 'order_reviews', COUNT(*) FROM order_reviews;

-- 2. Primary-key duplicate checks. All results should be zero.
SELECT 'orders' AS table_name, COUNT(*) AS duplicate_count
FROM (
  SELECT order_id
  FROM orders
  GROUP BY order_id
  HAVING COUNT(*) > 1
) d
UNION ALL
SELECT 'customers', COUNT(*)
FROM (
  SELECT customer_id
  FROM customers
  GROUP BY customer_id
  HAVING COUNT(*) > 1
) d
UNION ALL
SELECT 'products', COUNT(*)
FROM (
  SELECT product_id
  FROM products
  GROUP BY product_id
  HAVING COUNT(*) > 1
) d
UNION ALL
SELECT 'sellers', COUNT(*)
FROM (
  SELECT seller_id
  FROM sellers
  GROUP BY seller_id
  HAVING COUNT(*) > 1
) d;

-- 3. Orders missing delivery dates by status
SELECT
  order_status,
  COUNT(*) AS orders_count,
  SUM(order_delivered_customer_date IS NULL) AS missing_delivered_date,
  SUM(order_estimated_delivery_date IS NULL) AS missing_estimated_date
FROM orders
GROUP BY order_status
ORDER BY orders_count DESC;

-- 4. Invalid timestamp order
SELECT COUNT(*) AS delivered_before_purchase_count
FROM orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_delivered_customer_date < order_purchase_timestamp;

-- 5. Orphan records between child and parent tables
SELECT 'order_items_without_order' AS check_name, COUNT(*) AS bad_rows
FROM order_items oi
LEFT JOIN orders o ON o.order_id = oi.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'order_items_without_product', COUNT(*)
FROM order_items oi
LEFT JOIN products p ON p.product_id = oi.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'order_items_without_seller', COUNT(*)
FROM order_items oi
LEFT JOIN sellers s ON s.seller_id = oi.seller_id
WHERE s.seller_id IS NULL
UNION ALL
SELECT 'orders_without_customer', COUNT(*)
FROM orders o
LEFT JOIN customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL
UNION ALL
SELECT 'payments_without_order', COUNT(*)
FROM order_payments p
LEFT JOIN orders o ON o.order_id = p.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'reviews_without_order', COUNT(*)
FROM order_reviews r
LEFT JOIN orders o ON o.order_id = r.order_id
WHERE o.order_id IS NULL;

-- 6. Payment amount versus item amount plus freight.
-- Differences are expected for some orders because payment may be split
-- across installments, while this dataset has no refund/reversal table.
SELECT
  COUNT(*) AS compared_orders,
  SUM(ABS(payment_total - item_total) > 0.01) AS amount_mismatch_orders,
  ROUND(SUM(ABS(payment_total - item_total)), 2) AS total_absolute_difference
FROM (
  SELECT
    p.order_id,
    SUM(p.payment_value) AS payment_total,
    i.item_total
  FROM order_payments p
  JOIN (
    SELECT
      order_id,
      SUM(price + freight_value) AS item_total
    FROM order_items
    GROUP BY order_id
  ) i ON i.order_id = p.order_id
  GROUP BY p.order_id, i.item_total
) comparison;

-- 7. Product category translation coverage
SELECT
  COUNT(*) AS products_with_category,
  SUM(t.product_category_name IS NULL) AS missing_translation
FROM products p
LEFT JOIN product_category_translation t
  ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL;
