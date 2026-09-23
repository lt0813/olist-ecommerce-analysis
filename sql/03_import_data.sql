-- Olist CSV import script
-- Replace the local file paths only if the dataset directory is moved.
-- This script replaces the contents of the nine Olist tables.

USE olist;

SET FOREIGN_KEY_CHECKS = 0;

TRUNCATE TABLE order_reviews;
TRUNCATE TABLE order_payments;
TRUNCATE TABLE order_items;
TRUNCATE TABLE orders;
TRUNCATE TABLE products;
TRUNCATE TABLE sellers;
TRUNCATE TABLE geolocation;
TRUNCATE TABLE customers;
TRUNCATE TABLE product_category_translation;

SET FOREIGN_KEY_CHECKS = 1;

-- Product category translation
LOAD DATA LOCAL INFILE 'D:/Olist 电商经营诊断/Olist的巴西电子商务公共数据集/product_category_name_translation.csv'
INTO TABLE product_category_translation
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(product_category_name, product_category_name_english);

-- Customers
LOAD DATA LOCAL INFILE 'D:/Olist 电商经营诊断/Olist的巴西电子商务公共数据集/olist_customers_dataset.csv'
INTO TABLE customers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(customer_id, customer_unique_id, customer_zip_code_prefix,
 customer_city, customer_state);

-- Geolocation
LOAD DATA LOCAL INFILE 'D:/Olist 电商经营诊断/Olist的巴西电子商务公共数据集/olist_geolocation_dataset.csv'
INTO TABLE geolocation
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(geolocation_zip_code_prefix, geolocation_lat, geolocation_lng,
 geolocation_city, geolocation_state);

-- Sellers
LOAD DATA LOCAL INFILE 'D:/Olist 电商经营诊断/Olist的巴西电子商务公共数据集/olist_sellers_dataset.csv'
INTO TABLE sellers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(seller_id, seller_zip_code_prefix, seller_city, seller_state);

-- Products
LOAD DATA LOCAL INFILE 'D:/Olist 电商经营诊断/Olist的巴西电子商务公共数据集/olist_products_dataset.csv'
INTO TABLE products
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(@product_id, @product_category_name, @product_name_lenght,
 @product_description_lenght, @product_photos_qty, @product_weight_g,
 @product_length_cm, @product_height_cm, @product_width_cm)
SET
  product_id = @product_id,
  product_category_name = NULLIF(@product_category_name, ''),
  product_name_lenght = NULLIF(@product_name_lenght, ''),
  product_description_lenght = NULLIF(@product_description_lenght, ''),
  product_photos_qty = NULLIF(@product_photos_qty, ''),
  product_weight_g = NULLIF(@product_weight_g, ''),
  product_length_cm = NULLIF(@product_length_cm, ''),
  product_height_cm = NULLIF(@product_height_cm, ''),
  product_width_cm = NULLIF(@product_width_cm, '');

-- Orders
LOAD DATA LOCAL INFILE 'D:/Olist 电商经营诊断/Olist的巴西电子商务公共数据集/olist_orders_dataset.csv'
INTO TABLE orders
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(@order_id, @customer_id, @order_status, @order_purchase_timestamp,
 @order_approved_at, @order_delivered_carrier_date,
 @order_delivered_customer_date, @order_estimated_delivery_date)
SET
  order_id = @order_id,
  customer_id = @customer_id,
  order_status = @order_status,
  order_purchase_timestamp = NULLIF(@order_purchase_timestamp, ''),
  order_approved_at = NULLIF(@order_approved_at, ''),
  order_delivered_carrier_date = NULLIF(@order_delivered_carrier_date, ''),
  order_delivered_customer_date = NULLIF(@order_delivered_customer_date, ''),
  order_estimated_delivery_date = NULLIF(@order_estimated_delivery_date, '');

-- Order items
LOAD DATA LOCAL INFILE 'D:/Olist 电商经营诊断/Olist的巴西电子商务公共数据集/olist_order_items_dataset.csv'
INTO TABLE order_items
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(@order_id, @order_item_id, @product_id, @seller_id,
 @shipping_limit_date, @price, @freight_value)
SET
  order_id = @order_id,
  order_item_id = @order_item_id,
  product_id = @product_id,
  seller_id = @seller_id,
  shipping_limit_date = NULLIF(@shipping_limit_date, ''),
  price = @price,
  freight_value = @freight_value;

-- Order payments
LOAD DATA LOCAL INFILE 'D:/Olist 电商经营诊断/Olist的巴西电子商务公共数据集/olist_order_payments_dataset.csv'
INTO TABLE order_payments
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, payment_sequential, payment_type, payment_installments, payment_value);

-- Order reviews
LOAD DATA LOCAL INFILE 'D:/Olist 电商经营诊断/Olist的巴西电子商务公共数据集/olist_order_reviews_dataset.csv'
INTO TABLE order_reviews
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(@review_id, @order_id, @review_score, @review_comment_title,
 @review_comment_message, @review_creation_date, @review_answer_timestamp)
SET
  review_id = @review_id,
  order_id = @order_id,
  review_score = @review_score,
  review_comment_title = NULLIF(@review_comment_title, ''),
  review_comment_message = NULLIF(@review_comment_message, ''),
  review_creation_date = NULLIF(@review_creation_date, ''),
  review_answer_timestamp = NULLIF(@review_answer_timestamp, '');

SELECT 'product_category_translation' AS table_name, COUNT(*) AS row_count
FROM product_category_translation
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