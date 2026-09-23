-- Olist e-commerce analysis
-- Run this script in DataGrip while connected to the local MySQL server.

CREATE DATABASE IF NOT EXISTS olist
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

USE olist;

CREATE TABLE IF NOT EXISTS product_category_translation (
  product_category_name VARCHAR(100) NOT NULL,
  product_category_name_english VARCHAR(100) NOT NULL,
  PRIMARY KEY (product_category_name)
) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS customers (
  customer_id CHAR(32) NOT NULL,
  customer_unique_id CHAR(32) NOT NULL,
  customer_zip_code_prefix VARCHAR(10) NOT NULL,
  customer_city VARCHAR(100) NOT NULL,
  customer_state CHAR(2) NOT NULL,
  PRIMARY KEY (customer_id),
  KEY idx_customers_unique_id (customer_unique_id),
  KEY idx_customers_zip_code (customer_zip_code_prefix),
  KEY idx_customers_state (customer_state)
) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS geolocation (
  geolocation_zip_code_prefix VARCHAR(10) NOT NULL,
  geolocation_lat DOUBLE NOT NULL,
  geolocation_lng DOUBLE NOT NULL,
  geolocation_city VARCHAR(100) NOT NULL,
  geolocation_state CHAR(2) NOT NULL,
  KEY idx_geolocation_zip_code (geolocation_zip_code_prefix),
  KEY idx_geolocation_state (geolocation_state)
) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS sellers (
  seller_id CHAR(32) NOT NULL,
  seller_zip_code_prefix VARCHAR(10) NOT NULL,
  seller_city VARCHAR(100) NOT NULL,
  seller_state CHAR(2) NOT NULL,
  PRIMARY KEY (seller_id),
  KEY idx_sellers_zip_code (seller_zip_code_prefix),
  KEY idx_sellers_state (seller_state)
) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS products (
  product_id CHAR(32) NOT NULL,
  product_category_name VARCHAR(100) NULL,
  product_name_lenght INT NULL,
  product_description_lenght INT NULL,
  product_photos_qty INT NULL,
  product_weight_g INT NULL,
  product_length_cm INT NULL,
  product_height_cm INT NULL,
  product_width_cm INT NULL,
  PRIMARY KEY (product_id),
  KEY idx_products_category (product_category_name)
) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS orders (
  order_id CHAR(32) NOT NULL,
  customer_id CHAR(32) NOT NULL,
  order_status VARCHAR(20) NOT NULL,
  order_purchase_timestamp DATETIME NULL,
  order_approved_at DATETIME NULL,
  order_delivered_carrier_date DATETIME NULL,
  order_delivered_customer_date DATETIME NULL,
  order_estimated_delivery_date DATETIME NULL,
  PRIMARY KEY (order_id),
  KEY idx_orders_customer_id (customer_id),
  KEY idx_orders_status (order_status),
  KEY idx_orders_purchase_ts (order_purchase_timestamp)
) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS order_items (
  order_id CHAR(32) NOT NULL,
  order_item_id INT NOT NULL,
  product_id CHAR(32) NOT NULL,
  seller_id CHAR(32) NOT NULL,
  shipping_limit_date DATETIME NULL,
  price DECIMAL(12, 2) NOT NULL,
  freight_value DECIMAL(12, 2) NOT NULL,
  PRIMARY KEY (order_id, order_item_id),
  KEY idx_order_items_product_id (product_id),
  KEY idx_order_items_seller_id (seller_id),
  KEY idx_order_items_shipping_limit (shipping_limit_date)
) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS order_payments (
  order_id CHAR(32) NOT NULL,
  payment_sequential INT NOT NULL,
  payment_type VARCHAR(30) NOT NULL,
  payment_installments INT NOT NULL,
  payment_value DECIMAL(12, 2) NOT NULL,
  PRIMARY KEY (order_id, payment_sequential),
  KEY idx_order_payments_type (payment_type)
) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS order_reviews (
  review_id CHAR(32) NOT NULL,
  order_id CHAR(32) NOT NULL,
  review_score TINYINT UNSIGNED NOT NULL,
  review_comment_title TEXT NULL,
  review_comment_message TEXT NULL,
  review_creation_date DATETIME NULL,
  review_answer_timestamp DATETIME NULL,
  PRIMARY KEY (review_id, order_id),
  KEY idx_order_reviews_order_id (order_id),
  KEY idx_order_reviews_score (review_score)
) ENGINE = InnoDB
  DEFAULT CHARACTER SET = utf8mb4
  COLLATE = utf8mb4_0900_ai_ci;
