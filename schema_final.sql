SELECT 
    table_schema,
    table_name
FROM information_schema.tables
WHERE table_type = 'BASE TABLE'
  AND table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY table_schema, table_name;


SELECT
    table_schema,
    table_name,
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'coffee'
ORDER BY table_name, ordinal_position;

SELECT
    tc.table_schema,
    tc.table_name,
    tc.constraint_name,
    tc.constraint_type
FROM information_schema.table_constraints tc
WHERE tc.table_schema = 'coffee'
ORDER BY tc.table_name, tc.constraint_type;


/* ============================================================
   CoffeeClub Capstone Project II
   Post-Migration Optimization & Analytics
   File: schema_final.sql
   Database: PostgreSQL
   Schema: coffee
   ============================================================ */


/* ============================================================
   TASK 1: OPTIMIZATION & CONSTRAINTS
   Focus: SQL relational enforcement and indexing
   ============================================================ */


/* ------------------------------------------------------------
   1.1 Add primary key constraints
   ------------------------------------------------------------ */

ALTER TABLE coffee.customers
ADD CONSTRAINT customers_pkey
PRIMARY KEY (customer_id);

ALTER TABLE coffee.offers
ADD CONSTRAINT offers_pkey
PRIMARY KEY (offer_id);

ALTER TABLE coffee.events
ADD CONSTRAINT events_pkey
PRIMARY KEY (event_id);

ALTER TABLE coffee.offer_channels
ADD CONSTRAINT offer_channels_pkey
PRIMARY KEY (offer_id, channel_name);


/* ------------------------------------------------------------
   1.2 Add foreign key constraints
   ------------------------------------------------------------ */

ALTER TABLE coffee.events
ADD CONSTRAINT events_customer_id_fkey
FOREIGN KEY (customer_id)
REFERENCES coffee.customers(customer_id);

ALTER TABLE coffee.events
ADD CONSTRAINT events_offer_id_fkey
FOREIGN KEY (offer_id)
REFERENCES coffee.offers(offer_id);

ALTER TABLE coffee.offer_channels
ADD CONSTRAINT offer_channels_offer_id_fkey
FOREIGN KEY (offer_id)
REFERENCES coffee.offers(offer_id);


/* ------------------------------------------------------------
   1.3 Create B-Tree indexes for high-traffic columns
   ------------------------------------------------------------ */

CREATE INDEX IF NOT EXISTS idx_events_customer_id
ON coffee.events USING btree (customer_id);

CREATE INDEX IF NOT EXISTS idx_events_offer_id
ON coffee.events USING btree (offer_id);

CREATE INDEX IF NOT EXISTS idx_events_event
ON coffee.events USING btree (event);

CREATE INDEX IF NOT EXISTS idx_events_time
ON coffee.events USING btree (time);

CREATE INDEX IF NOT EXISTS idx_events_customer_time
ON coffee.events USING btree (customer_id, time);

CREATE INDEX IF NOT EXISTS idx_events_offer_event
ON coffee.events USING btree (offer_id, event);

CREATE INDEX IF NOT EXISTS idx_customers_gender
ON coffee.customers USING btree (gender);

CREATE INDEX IF NOT EXISTS idx_customers_age
ON coffee.customers USING btree (age);

CREATE INDEX IF NOT EXISTS idx_customers_income
ON coffee.customers USING btree (income);

CREATE INDEX IF NOT EXISTS idx_offers_offer_type
ON coffee.offers USING btree (offer_type);

CREATE INDEX IF NOT EXISTS idx_offer_channels_offer_id
ON coffee.offer_channels USING btree (offer_id);


/* ============================================================
   TASK 2: FEATURE ENGINEERING & INTEGRITY
   Focus: Time transformation and data cleaning
   ============================================================ */


/* ------------------------------------------------------------
   2.1 Add readable time feature columns
   ------------------------------------------------------------ */

ALTER TABLE coffee.events
ADD COLUMN IF NOT EXISTS day INTEGER;

ALTER TABLE coffee.events
ADD COLUMN IF NOT EXISTS hour_of_day INTEGER;

ALTER TABLE coffee.events
ADD COLUMN IF NOT EXISTS time_interval INTERVAL;


/* ------------------------------------------------------------
   2.2 Populate readable time features
   ------------------------------------------------------------ */

UPDATE coffee.events
SET
    day = time / 24,
    hour_of_day = time % 24,
    time_interval = time * INTERVAL '1 hour';


/* ------------------------------------------------------------
   2.3 Data quality audit: handle placeholder age 118
   ------------------------------------------------------------ */

/*
   Age 118 is treated as a placeholder for missing or unknown age.
   It is converted to NULL so that it does not distort demographic
   reporting.
*/

UPDATE coffee.customers
SET age = NULL
WHERE age = 118;


/* ------------------------------------------------------------
   2.4 Audit checks
   ------------------------------------------------------------ */

SELECT COUNT(*) AS remaining_age_118_records
FROM coffee.customers
WHERE age = 118;

SELECT COUNT(*) AS customers_with_missing_age
FROM coffee.customers
WHERE age IS NULL;


/* ============================================================
   TASK 3: ANALYTICS - OFFER AGGREGATIONS
   Focus: Summary tables/views
   ============================================================ */


/* ------------------------------------------------------------
   3.1 Offer event summary view
   ------------------------------------------------------------ */

/*
   This view counts how many times each offer was received, viewed,
   and completed. It also calculates view rate and completion rate.
*/

CREATE OR REPLACE VIEW coffee.vw_offer_event_summary AS
SELECT
    o.offer_id,
    o.offer_type,
    o.difficulty,
    o.reward,
    o.duration,

    COUNT(CASE WHEN e.event = 'offer received' THEN 1 END) AS total_received,
    COUNT(CASE WHEN e.event = 'offer viewed' THEN 1 END) AS total_viewed,
    COUNT(CASE WHEN e.event = 'offer completed' THEN 1 END) AS total_completed,

    ROUND(
        COUNT(CASE WHEN e.event = 'offer viewed' THEN 1 END)::NUMERIC
        / NULLIF(COUNT(CASE WHEN e.event = 'offer received' THEN 1 END), 0),
        4
    ) AS view_rate,

    ROUND(
        COUNT(CASE WHEN e.event = 'offer completed' THEN 1 END)::NUMERIC
        / NULLIF(COUNT(CASE WHEN e.event = 'offer received' THEN 1 END), 0),
        4
    ) AS completion_rate

FROM coffee.offers o
LEFT JOIN coffee.events e
    ON o.offer_id = e.offer_id
GROUP BY
    o.offer_id,
    o.offer_type,
    o.difficulty,
    o.reward,
    o.duration;


/* ------------------------------------------------------------
   3.2 Offer completion ranking view
   ------------------------------------------------------------ */

/*
   This view ranks offers by completion rate so that the strongest
   performing offers are easy to identify.
*/

CREATE OR REPLACE VIEW coffee.vw_offer_completion_ranking AS
SELECT
    offer_id,
    offer_type,
    difficulty,
    reward,
    duration,
    total_received,
    total_viewed,
    total_completed,
    view_rate,
    completion_rate,
    RANK() OVER (
        ORDER BY completion_rate DESC NULLS LAST
    ) AS completion_rank
FROM coffee.vw_offer_event_summary;


/* ------------------------------------------------------------
   3.3 Informational offers followed by transactions
   ------------------------------------------------------------ */

/*
   Informational offers do not receive "offer completed" events.

   A transaction is counted as influenced by an informational offer if:
   1. The customer viewed the informational offer.
   2. The transaction happened after the offer was viewed.
   3. The transaction happened before the viewed time plus the offer
      duration.

   The duration column is treated as days, so it is converted to hours
   using duration * 24.
*/

CREATE OR REPLACE VIEW coffee.vw_informational_offer_transaction_influence AS
SELECT
    viewed.offer_id,
    o.offer_type,
    COUNT(*) AS influenced_transaction_count,
    COUNT(DISTINCT viewed.customer_id) AS influenced_customer_count
FROM coffee.events viewed
JOIN coffee.offers o
    ON viewed.offer_id = o.offer_id
JOIN coffee.events txn
    ON viewed.customer_id = txn.customer_id
WHERE o.offer_type = 'informational'
  AND viewed.event = 'offer viewed'
  AND txn.event = 'transaction'
  AND txn.time BETWEEN viewed.time AND viewed.time + (o.duration * 24)
GROUP BY
    viewed.offer_id,
    o.offer_type;


/* ============================================================
   TASK 4: DEMOGRAPHIC FEATURE SCALING
   Focus: Income buckets and age groups
   ============================================================ */


/* ------------------------------------------------------------
   4.1 Add income bucket column
   ------------------------------------------------------------ */

ALTER TABLE coffee.customers
ADD COLUMN IF NOT EXISTS income_bucket TEXT;


/* ------------------------------------------------------------
   4.2 Populate income buckets
   ------------------------------------------------------------ */

UPDATE coffee.customers
SET income_bucket =
    CASE
        WHEN income IS NULL THEN 'Unknown Income'
        WHEN income < 40000 THEN 'Low Income'
        WHEN income >= 40000 AND income < 80000 THEN 'Middle Income'
        WHEN income >= 80000 THEN 'High Income'
    END;


/* ------------------------------------------------------------
   4.3 Add age group column
   ------------------------------------------------------------ */

ALTER TABLE coffee.customers
ADD COLUMN IF NOT EXISTS age_group TEXT;


/* ------------------------------------------------------------
   4.4 Populate age groups
   ------------------------------------------------------------ */

UPDATE coffee.customers
SET age_group =
    CASE
        WHEN age IS NULL THEN 'Unknown Age'
        WHEN age < 18 THEN 'Under 18'
        WHEN age BETWEEN 18 AND 24 THEN '18-24'
        WHEN age BETWEEN 25 AND 34 THEN '25-34'
        WHEN age BETWEEN 35 AND 44 THEN '35-44'
        WHEN age BETWEEN 45 AND 54 THEN '45-54'
        WHEN age BETWEEN 55 AND 64 THEN '55-64'
        WHEN age >= 65 THEN '65+'
    END;


/* ------------------------------------------------------------
   4.5 Customer demographic summary view
   ------------------------------------------------------------ */

CREATE OR REPLACE VIEW coffee.vw_customer_demographic_summary AS
SELECT
    gender,
    age_group,
    income_bucket,
    COUNT(*) AS customer_count,
    ROUND(AVG(income)::NUMERIC, 2) AS average_income
FROM coffee.customers
GROUP BY
    gender,
    age_group,
    income_bucket
ORDER BY
    gender,
    age_group,
    income_bucket;


/* ============================================================
   FINAL EVIDENCE QUERIES
   Run these after executing the full script.
   Take screenshots of the results for your submission.
   ============================================================ */


/* Task 3 Evidence: Offer summary */
SELECT *
FROM coffee.vw_offer_event_summary
ORDER BY completion_rate DESC NULLS LAST;


/* Task 3 Evidence: Offer completion ranking */
SELECT *
FROM coffee.vw_offer_completion_ranking
ORDER BY completion_rank, total_received DESC;


/* Task 3 Evidence: Informational offer influence */
SELECT *
FROM coffee.vw_informational_offer_transaction_influence
ORDER BY influenced_transaction_count DESC;


/* Task 4 Evidence: Demographic summary */
SELECT *
FROM coffee.vw_customer_demographic_summary;

SELECT *
FROM coffee.vw_offer_event_summary
ORDER BY completion_rate DESC NULLS LAST;
