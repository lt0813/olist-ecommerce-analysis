-- Olist e-commerce analysis
-- Read-only business metric queries based on the frozen metric definitions.
-- Run 04_create_analysis_views.sql before this script.

USE olist;

-- 1. Overall KPIs.
-- GMV is based on payment value for delivered orders.
-- Item value includes product price and freight value and is used for
-- category and region slices where payment cannot be allocated directly.
SELECT
  COUNT(*) AS delivered_orders,
  COUNT(DISTINCT customer_unique_id) AS delivered_customers,
  ROUND(SUM(recognized_gmv), 2) AS gmv,
  ROUND(SUM(item_total), 2) AS item_value_with_freight,
  ROUND(SUM(freight_total), 2) AS freight_value,
  ROUND(
    SUM(recognized_gmv) / NULLIF(COUNT(*), 0),
    2
  ) AS average_order_value,
  ROUND(
    SUM(item_total) - SUM(recognized_gmv),
    2
  ) AS payment_vs_item_difference,
  SUM(
    CASE WHEN review_count > 0 THEN 1 ELSE 0 END
  ) AS reviewed_orders,
  ROUND(
    AVG(
      CASE
        WHEN review_count > 0 THEN avg_review_score
      END
    ),
    2
  ) AS average_review_score,
  ROUND(
    100.0 * SUM(is_bad_review)
      / NULLIF(
        SUM(CASE WHEN review_count > 0 THEN 1 ELSE 0 END),
        0
      ),
    2
  ) AS bad_review_rate_pct,
  ROUND(
    AVG(
      CASE
        WHEN has_delivery_dates = 1 THEN total_delivery_days
      END
    ),
    2
  ) AS average_delivery_days,
  SUM(is_late) AS late_orders,
  ROUND(
    100.0 * SUM(is_late)
      / NULLIF(SUM(has_delivery_dates), 0),
    2
  ) AS late_order_rate_pct
FROM v_order_analytics
WHERE is_delivered = 1;

-- 2. Monthly business trend.
-- Orders are grouped by purchase month, not delivery month.
WITH monthly_metrics AS (
  SELECT
    purchase_month,
    COUNT(*) AS delivered_orders,
    COUNT(DISTINCT customer_unique_id) AS active_customers,
    ROUND(SUM(recognized_gmv), 2) AS gmv,
    ROUND(SUM(item_total), 2) AS item_value_with_freight,
    ROUND(
      SUM(recognized_gmv) / NULLIF(COUNT(*), 0),
      2
    ) AS average_order_value
  FROM v_order_analytics
  WHERE is_delivered = 1
  GROUP BY purchase_month
),
monthly_comparison AS (
  SELECT
    monthly_metrics.*,
    LAG(gmv) OVER (ORDER BY purchase_month) AS previous_month_gmv,
    LAG(delivered_orders) OVER (
      ORDER BY purchase_month
    ) AS previous_month_orders
  FROM monthly_metrics
)
SELECT
  purchase_month,
  delivered_orders,
  active_customers,
  gmv,
  item_value_with_freight,
  average_order_value,
  ROUND(
    100.0 * (gmv - previous_month_gmv)
      / NULLIF(previous_month_gmv, 0),
    2
  ) AS gmv_mom_pct,
  ROUND(
    100.0 * (delivered_orders - previous_month_orders)
      / NULLIF(previous_month_orders, 0),
    2
  ) AS order_count_mom_pct
FROM monthly_comparison
ORDER BY purchase_month;

-- 3. Category sales structure.
-- Category value uses item price plus freight value for delivered orders.
SELECT
  COALESCE(
    t.product_category_name_english,
    p.product_category_name,
    'unknown'
  ) AS category_name,
  COUNT(DISTINCT oa.order_id) AS delivered_orders,
  COUNT(*) AS item_rows,
  COUNT(DISTINCT p.product_id) AS product_count,
  ROUND(SUM(oi.price + oi.freight_value), 2) AS category_gmv,
  ROUND(SUM(oi.price), 2) AS product_value,
  ROUND(SUM(oi.freight_value), 2) AS freight_value,
  ROUND(AVG(oi.price), 2) AS average_item_price,
  ROUND(
    100.0 * SUM(oi.price + oi.freight_value)
      / NULLIF(
        SUM(SUM(oi.price + oi.freight_value)) OVER (),
        0
      ),
    2
  ) AS gmv_share_pct
FROM v_order_analytics oa
JOIN order_items oi
  ON oi.order_id = oa.order_id
JOIN products p
  ON p.product_id = oi.product_id
LEFT JOIN product_category_translation t
  ON t.product_category_name = p.product_category_name
WHERE oa.is_delivered = 1
GROUP BY
  COALESCE(
    t.product_category_name_english,
    p.product_category_name,
    'unknown'
  )
ORDER BY category_gmv DESC;

-- 12. Fulfillment stage comparison for on-time and late orders.
SELECT
  CASE
    WHEN is_late = 1 THEN 'late'
    ELSE 'on_time'
  END AS delivery_status,
  COUNT(*) AS orders_count,
  ROUND(AVG(approval_days), 2) AS average_approval_days,
  ROUND(
    AVG(seller_handling_days),
    2
  ) AS average_seller_handling_days,
  ROUND(
    AVG(carrier_delivery_days),
    2
  ) AS average_carrier_delivery_days,
  ROUND(
    AVG(total_delivery_days),
    2
  ) AS average_total_delivery_days
FROM v_order_analytics
WHERE is_delivered = 1
  AND has_delivery_dates = 1
GROUP BY is_late
ORDER BY is_late DESC;

-- 13. Seller risk candidates with at least 200 delivered orders.
-- The thresholds are empirical screening rules, not causal conclusions.
WITH seller_orders AS (
  SELECT
    oi.seller_id,
    oi.order_id,
    SUM(oi.price + oi.freight_value) AS seller_order_gmv
  FROM order_items oi
  GROUP BY oi.seller_id, oi.order_id
),
seller_metrics AS (
  SELECT
    so.seller_id,
    COUNT(*) AS delivered_orders,
    ROUND(SUM(so.seller_order_gmv), 2) AS seller_gmv,
    ROUND(
      100.0 * SUM(
        CASE
          WHEN oa.has_delivery_dates = 1 THEN oa.is_late
          ELSE 0
        END
      ) / NULLIF(SUM(oa.has_delivery_dates), 0),
      2
    ) AS late_order_rate_pct,
    ROUND(
      100.0 * SUM(
        CASE
          WHEN oa.review_count > 0 THEN oa.is_bad_review
          ELSE 0
        END
      ) / NULLIF(
        SUM(CASE WHEN oa.review_count > 0 THEN 1 ELSE 0 END),
        0
      ),
      2
    ) AS bad_review_rate_pct
  FROM seller_orders so
  JOIN v_order_analytics oa
    ON oa.order_id = so.order_id
  WHERE oa.is_delivered = 1
  GROUP BY so.seller_id
)
SELECT
  seller_id,
  delivered_orders,
  seller_gmv,
  late_order_rate_pct,
  bad_review_rate_pct
FROM seller_metrics
WHERE delivered_orders >= 200
  AND (
    late_order_rate_pct >= 12
    OR bad_review_rate_pct >= 18
  )
ORDER BY seller_gmv DESC;

-- 4. Region sales structure by customer state.
SELECT
  customer_state,
  COUNT(*) AS delivered_orders,
  COUNT(DISTINCT customer_unique_id) AS delivered_customers,
  ROUND(SUM(recognized_gmv), 2) AS gmv,
  ROUND(SUM(item_total), 2) AS item_value_with_freight,
  ROUND(SUM(freight_total), 2) AS freight_value,
  ROUND(
    SUM(recognized_gmv) / NULLIF(COUNT(*), 0),
    2
  ) AS average_order_value,
  ROUND(
    100.0 * SUM(freight_total)
      / NULLIF(SUM(item_total), 0),
    2
  ) AS freight_share_pct,
  ROUND(
    100.0 * SUM(recognized_gmv)
      / NULLIF(SUM(SUM(recognized_gmv)) OVER (), 0),
    2
  ) AS gmv_share_pct,
  ROUND(
    100.0 * SUM(is_late)
      / NULLIF(SUM(has_delivery_dates), 0),
    2
  ) AS late_order_rate_pct,
  ROUND(
    100.0 * SUM(is_bad_review)
      / NULLIF(
        SUM(CASE WHEN review_count > 0 THEN 1 ELSE 0 END),
        0
      ),
    2
  ) AS bad_review_rate_pct
FROM v_order_analytics
WHERE is_delivered = 1
GROUP BY customer_state
ORDER BY gmv DESC;

-- 5. Repeat purchase summary.
-- A repeat customer has at least two delivered orders under one
-- customer_unique_id.
SELECT
  COUNT(*) AS delivered_customers,
  SUM(
    CASE WHEN delivered_orders = 1 THEN 1 ELSE 0 END
  ) AS one_time_customers,
  SUM(
    CASE WHEN delivered_orders >= 2 THEN 1 ELSE 0 END
  ) AS repeat_customers,
  ROUND(
    100.0 * SUM(
      CASE WHEN delivered_orders >= 2 THEN 1 ELSE 0 END
    ) / NULLIF(COUNT(*), 0),
    2
  ) AS repeat_customer_rate_pct,
  ROUND(SUM(customer_gmv), 2) AS total_customer_gmv,
  ROUND(
    SUM(
      CASE WHEN delivered_orders >= 2 THEN customer_gmv ELSE 0 END
    ),
    2
  ) AS repeat_customer_gmv,
  ROUND(
    100.0 * SUM(
      CASE WHEN delivered_orders >= 2 THEN customer_gmv ELSE 0 END
    ) / NULLIF(SUM(customer_gmv), 0),
    2
  ) AS repeat_customer_gmv_share_pct,
  ROUND(
    AVG(
      CASE
        WHEN delivered_orders = 1 THEN customer_gmv
      END
    ),
    2
  ) AS one_time_customer_average_gmv,
  ROUND(
    AVG(
      CASE
        WHEN delivered_orders >= 2 THEN customer_gmv
      END
    ),
    2
  ) AS repeat_customer_average_gmv
FROM v_customer_analytics;

-- 6. First-to-second order interval for repeat customers.
WITH ordered_purchases AS (
  SELECT
    customer_unique_id,
    order_id,
    order_purchase_timestamp,
    ROW_NUMBER() OVER (
      PARTITION BY customer_unique_id
      ORDER BY order_purchase_timestamp, order_id
    ) AS purchase_sequence
  FROM v_order_analytics
  WHERE is_delivered = 1
),
first_two_orders AS (
  SELECT
    customer_unique_id,
    MAX(
      CASE
        WHEN purchase_sequence = 1 THEN order_purchase_timestamp
      END
    ) AS first_order_at,
    MAX(
      CASE
        WHEN purchase_sequence = 2 THEN order_purchase_timestamp
      END
    ) AS second_order_at
  FROM ordered_purchases
  WHERE purchase_sequence <= 2
  GROUP BY customer_unique_id
)
SELECT
  COUNT(*) AS repeat_customers,
  ROUND(
    AVG(
      TIMESTAMPDIFF(DAY, first_order_at, second_order_at)
    ),
    1
  ) AS average_days_to_second_order,
  ROUND(
    AVG(
      TIMESTAMPDIFF(DAY, first_order_at, second_order_at) / 7.0
    ),
    1
  ) AS average_weeks_to_second_order
FROM first_two_orders
WHERE second_order_at IS NOT NULL;

-- 7. Fulfillment stage summary for delivered orders.
SELECT
  COUNT(*) AS delivered_orders,
  SUM(has_delivery_dates) AS orders_with_delivery_dates,
  ROUND(AVG(approval_days), 2) AS average_approval_days,
  ROUND(
    AVG(seller_handling_days),
    2
  ) AS average_seller_handling_days,
  ROUND(
    AVG(carrier_delivery_days),
    2
  ) AS average_carrier_delivery_days,
  ROUND(
    AVG(total_delivery_days),
    2
  ) AS average_total_delivery_days,
  ROUND(
    AVG(estimated_delay_days),
    2
  ) AS average_estimated_delay_days,
  SUM(is_late) AS late_orders,
  ROUND(
    100.0 * SUM(is_late)
      / NULLIF(SUM(has_delivery_dates), 0),
    2
  ) AS late_order_rate_pct
FROM v_order_analytics
WHERE is_delivered = 1;

-- 8. Review outcome by delay bucket.
WITH delay_buckets AS (
  SELECT
    CASE
      WHEN is_late = 0
        THEN 'on_time'
      WHEN estimated_delay_days <= 3
        THEN 'late_1_3_days'
      WHEN estimated_delay_days <= 7
        THEN 'late_4_7_days'
      ELSE 'late_8_days_or_more'
    END AS delay_bucket,
    review_count,
    avg_review_score,
    is_bad_review
  FROM v_order_analytics
  WHERE is_delivered = 1
    AND has_delivery_dates = 1
)
SELECT
  delay_bucket,
  COUNT(*) AS orders_count,
  SUM(
    CASE WHEN review_count > 0 THEN 1 ELSE 0 END
  ) AS reviewed_orders,
  ROUND(
    AVG(
      CASE
        WHEN review_count > 0 THEN avg_review_score
      END
    ),
    2
  ) AS average_review_score,
  ROUND(
    100.0 * SUM(is_bad_review)
      / NULLIF(
        SUM(CASE WHEN review_count > 0 THEN 1 ELSE 0 END),
        0
      ),
    2
  ) AS bad_review_rate_pct
FROM delay_buckets
GROUP BY delay_bucket
ORDER BY FIELD(
  delay_bucket,
  'on_time',
  'late_1_3_days',
  'late_4_7_days',
  'late_8_days_or_more'
);

-- 9. Seller GMV concentration.
WITH seller_metrics AS (
  SELECT
    oi.seller_id,
    COUNT(DISTINCT oi.order_id) AS delivered_orders,
    SUM(oi.price + oi.freight_value) AS seller_gmv
  FROM v_order_analytics oa
  JOIN order_items oi
    ON oi.order_id = oa.order_id
  WHERE oa.is_delivered = 1
  GROUP BY oi.seller_id
),
ranked_sellers AS (
  SELECT
    seller_id,
    delivered_orders,
    seller_gmv,
    ROW_NUMBER() OVER (
      ORDER BY seller_gmv DESC, seller_id
    ) AS seller_rank,
    COUNT(*) OVER () AS total_sellers,
    SUM(seller_gmv) OVER () AS total_gmv
  FROM seller_metrics
)
SELECT
  COUNT(*) AS sellers_with_delivered_orders,
  ROUND(MAX(total_gmv), 2) AS total_seller_gmv,
  ROUND(
    100.0 * SUM(
      CASE
        WHEN seller_rank <= CEIL(total_sellers * 0.01)
        THEN seller_gmv
        ELSE 0
      END
    ) / NULLIF(MAX(total_gmv), 0),
    2
  ) AS top_1pct_seller_gmv_share_pct,
  ROUND(
    100.0 * SUM(
      CASE
        WHEN seller_rank <= CEIL(total_sellers * 0.05)
        THEN seller_gmv
        ELSE 0
      END
    ) / NULLIF(MAX(total_gmv), 0),
    2
  ) AS top_5pct_seller_gmv_share_pct,
  ROUND(
    100.0 * SUM(
      CASE
        WHEN seller_rank <= CEIL(total_sellers * 0.10)
        THEN seller_gmv
        ELSE 0
      END
    ) / NULLIF(MAX(total_gmv), 0),
    2
  ) AS top_10pct_seller_gmv_share_pct
FROM ranked_sellers;

-- 10. Top 10 sellers, including service quality indicators.
WITH seller_order_metrics AS (
  SELECT
    oi.seller_id,
    oi.order_id,
    SUM(oi.price + oi.freight_value) AS seller_order_gmv
  FROM order_items oi
  GROUP BY oi.seller_id, oi.order_id
),
seller_metrics AS (
  SELECT
    som.seller_id,
    COUNT(*) AS delivered_orders,
    SUM(som.seller_order_gmv) AS seller_gmv,
    SUM(
      CASE
        WHEN oa.has_delivery_dates = 1 THEN oa.is_late
        ELSE 0
      END
    ) AS late_orders,
    SUM(
      CASE
        WHEN oa.has_delivery_dates = 1 THEN 1
        ELSE 0
      END
    ) AS orders_with_delivery_dates,
    SUM(
      CASE
        WHEN oa.review_count > 0 THEN oa.is_bad_review
        ELSE 0
      END
    ) AS bad_review_orders,
    SUM(
      CASE
        WHEN oa.review_count > 0 THEN 1
        ELSE 0
      END
    ) AS reviewed_orders
  FROM seller_order_metrics som
  JOIN v_order_analytics oa
    ON oa.order_id = som.order_id
  WHERE oa.is_delivered = 1
  GROUP BY som.seller_id
)
SELECT
  seller_id,
  delivered_orders,
  ROUND(seller_gmv, 2) AS seller_gmv,
  ROUND(
    100.0 * late_orders
      / NULLIF(orders_with_delivery_dates, 0),
    2
  ) AS late_order_rate_pct,
  ROUND(
    100.0 * bad_review_orders
      / NULLIF(reviewed_orders, 0),
    2
  ) AS bad_review_rate_pct
FROM seller_metrics
ORDER BY seller_gmv DESC
LIMIT 10;

-- 11. Category revenue and service quality matrix.
-- Rates are calculated at order level before items are aggregated into
-- categories, so multi-item orders do not inflate the denominators.
WITH category_orders AS (
  SELECT
    COALESCE(
      t.product_category_name_english,
      p.product_category_name,
      'unknown'
    ) AS category_name,
    oa.order_id,
    oa.has_delivery_dates,
    oa.is_late,
    oa.review_count,
    oa.is_bad_review,
    oa.avg_review_score,
    SUM(oi.price + oi.freight_value) AS category_order_gmv
  FROM v_order_analytics oa
  JOIN order_items oi
    ON oi.order_id = oa.order_id
  JOIN products p
    ON p.product_id = oi.product_id
  LEFT JOIN product_category_translation t
    ON t.product_category_name = p.product_category_name
  WHERE oa.is_delivered = 1
  GROUP BY
    COALESCE(
      t.product_category_name_english,
      p.product_category_name,
      'unknown'
    ),
    oa.order_id,
    oa.has_delivery_dates,
    oa.is_late,
    oa.review_count,
    oa.is_bad_review,
    oa.avg_review_score
)
SELECT
  category_name,
  COUNT(*) AS delivered_orders,
  ROUND(SUM(category_order_gmv), 2) AS category_gmv,
  ROUND(
    100.0 * SUM(
      CASE
        WHEN has_delivery_dates = 1 THEN is_late
        ELSE 0
      END
    ) / NULLIF(SUM(has_delivery_dates), 0),
    2
  ) AS late_order_rate_pct,
  ROUND(
    100.0 * SUM(
      CASE
        WHEN review_count > 0 THEN is_bad_review
        ELSE 0
      END
    ) / NULLIF(
      SUM(CASE WHEN review_count > 0 THEN 1 ELSE 0 END),
      0
    ),
    2
  ) AS bad_review_rate_pct,
  ROUND(
    AVG(
      CASE
        WHEN review_count > 0 THEN avg_review_score
      END
    ),
    2
  ) AS average_review_score
FROM category_orders
GROUP BY category_name
HAVING COUNT(*) >= 100
ORDER BY category_gmv DESC;
