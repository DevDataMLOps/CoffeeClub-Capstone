# CoffeeClub Post-Migration Optimization & Analytics

## Project Overview

This project focuses on optimizing the CoffeeClub database after migration into PostgreSQL. The goal is to improve database reliability, enforce relationships between tables, clean and transform raw data, and create SQL views that make offer performance easy to understand.

The project uses the following CoffeeClub tables in the `coffee` schema:

- `coffee.customers`
- `coffee.events`
- `coffee.offers`
- `coffee.offer_channels`

The final SQL script is saved as:

- `schema_final.sql`

---

## Task 1: Optimization and Constraints

### Objective

The goal of Task 1 was to improve the database structure by adding primary keys, foreign keys, and indexes.

### Primary Keys

Primary keys were added to uniquely identify rows in the main tables.

The expected primary key relationships are:

- `coffee.customers.customer_id`
- `coffee.offers.offer_id`
- `coffee.events.event_id`
- `coffee.offer_channels.offer_id` and channel column as a composite key

If the `events` table did not already contain an `event_id`, a surrogate `event_id` column was added so that every event row could be uniquely identified.

### Foreign Keys

Foreign keys were added to enforce relationships between the tables:

- `coffee.events.customer_id` references `coffee.customers.customer_id`
- `coffee.events.offer_id` references `coffee.offers.offer_id`
- `coffee.offer_channels.offer_id` references `coffee.offers.offer_id`

These constraints help prevent orphaned records. For example, an event cannot reference a customer that does not exist in the customers table.

### Indexes

Indexes were created on high-traffic columns used in joins, filtering, grouping, and analytics queries.

Important indexed columns include:

- `customer_id`
- `offer_id`
- `event`
- `time`
- `offer_type`
- `age`
- `income`

A composite index on `events(customer_id, time)` was also created to support time-window analysis, especially for identifying transactions that happened after informational offers were viewed.

---

## Task 2: Feature Engineering and Data Integrity

### Time Transformation

The original `time` column stores the number of hours since the campaign started. To make this more useful for analysis, new readable time columns were created.

The `day` column was created using integer division:

```sql
time / 24

