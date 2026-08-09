-- PostgreSQL schema
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id          INTEGER PRIMARY KEY,
    first_name           VARCHAR(50) NOT NULL,
    last_name            VARCHAR(50) NOT NULL,
    age                  INTEGER CHECK (age BETWEEN 18 AND 100),
    gender               VARCHAR(20),
    signup_date          DATE NOT NULL,
    loyalty_tier         VARCHAR(20) CHECK (loyalty_tier IN ('Bronze','Silver','Gold')),
    city                 VARCHAR(80),
    state                VARCHAR(100),
    country              VARCHAR(80),
    acquisition_channel  VARCHAR(40),
    preferred_device     VARCHAR(20),
    marketing_opt_in     VARCHAR(3)
);

CREATE TABLE orders (
    order_id             INTEGER PRIMARY KEY,
    customer_id          INTEGER NOT NULL REFERENCES customers(customer_id),
    order_date           DATE NOT NULL,
    product_category     VARCHAR(50) NOT NULL,
    product_name         VARCHAR(100) NOT NULL,
    quantity             INTEGER NOT NULL CHECK (quantity > 0),
    unit_price           NUMERIC(10,2) NOT NULL,
    discount_percent     NUMERIC(5,2) DEFAULT 0,
    subtotal             NUMERIC(12,2) NOT NULL,
    shipping_cost        NUMERIC(10,2) NOT NULL,
    tax_amount           NUMERIC(10,2) NOT NULL,
    total_amount         NUMERIC(12,2) NOT NULL,
    payment_method       VARCHAR(30),
    order_status         VARCHAR(20),
    shipping_method      VARCHAR(20),
    sales_channel        VARCHAR(20),
    coupon_code          VARCHAR(30),
    delivery_days        INTEGER,
    customer_rating      INTEGER CHECK (customer_rating BETWEEN 1 AND 5)
);

CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_order_date ON orders(order_date);
CREATE INDEX idx_orders_category ON orders(product_category);
CREATE INDEX idx_orders_status ON orders(order_status);

-- In psql, import with:
-- \copy customers FROM 'customers.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
-- \copy orders FROM 'orders.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
