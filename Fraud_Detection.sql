-- ============================================================
-- FRAUD DETECTION DATABASE — PaySim Dataset
-- Author: Muhammad Ammar Saleem
-- Date: June 30 - July 1 2026
-- Dataset: 6,362,620 synthetic mobile money transactions
-- ============================================================


-- ============================================================
-- SECTION 1: DATABASE & RAW STAGING TABLE SETUP
-- ============================================================
-- Purpose: Load raw CSV data into a flat staging table
-- before any analysis or normalization

create database Fraud_Detection;
use Fraud_Detection;

CREATE TABLE paysim_raw (
    step INT,
    type VARCHAR(20),
    amount DECIMAL(12,2),
    nameOrig VARCHAR(20),
    oldbalanceOrg DECIMAL(12,2),
    newbalanceOrig DECIMAL(12,2),
    nameDest VARCHAR(20),
    oldbalanceDest DECIMAL(12,2),
    newbalanceDest DECIMAL(12,2),
    isFraud TINYINT,
    isFlaggedFraud TINYINT
);



-- ============================================================
-- SECTION 2: DATA LOADING
-- ============================================================
-- Purpose: Bulk load 6.3M rows using LOAD DATA LOCAL INFILE
-- Note: GUI import wizard failed — used Terminal + CLI
-- Note: Required SET GLOBAL local_infile = 1

SHOW VARIABLES LIKE 'max_allowed_packet';
SET GLOBAL max_allowed_packet = 1073741824; -- 1GB

SET GLOBAL local_infile = 1;

LOAD DATA LOCAL INFILE '/Users/muhammadumer/Documents/SQL/Fraud_Detection-mysql/PS_20174392719_1491204439457_log.csv'
INTO TABLE paysim_raw
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) FROM paysim_raw;
select * from paysim_raw;

-- ============================================================
-- SECTION 3: EXPLORATORY DATA ANALYSIS (EDA)
-- ============================================================
-- Purpose: Understand data before designing schema
-- Each query answers a specific design question

-- Q1: Are accounts unique or do they repeat?
-- Q2: Customer vs Merchant split (C/M prefix)
-- Q3: Account frequency — who appears most?
-- Q4: Fraud rate by transaction type

-- ======================================
-- Is nameOrig/nameDest a unique account, or does it repeat?
-- ======================================
select count(distinct nameOrig) from paysim_raw; 
select count(distinct nameDest) from paysim_raw; 


-- ========================================
-- Confirm the C/M prefix split on both sides
-- ========================================
Select
 count(case when nameOrig like 'C%' then 1 end ) as orig_cutomer, 
 count(case when nameOrig like 'M%' then 1 end ) as orig_merchant 
 from paysim_raw;

Select
 count(case when nameDest like 'C%' then 1 end ) as dest_cutomer, 
 count(case when nameDest like 'M%' then 1 end ) as dest_merchant 
 from paysim_raw;


-- ========================================
-- How many times does each account appear?
-- ========================================
select count(nameOrig) from paysim_raw group by nameOrig order by count(nameOrig) desc limit 20; 
select count(nameDest) from paysim_raw group by nameDest order by count(nameDest) desc limit 20; 


SET SESSION wait_timeout = 600;
SET SESSION interactive_timeout = 600;

-- ========================================
-- Which transaction type has the highest fraud rate?
-- ========================================
select type, sum(isFraud) as total_fraud, avg(isFraud)*100 as percent_fraud  from paysim_raw group by type order by percent_fraud desc; 


-- ============================================================
-- SECTION 4: SCHEMA DESIGN & NORMALIZED TABLES
-- ============================================================
-- Purpose: Based on EDA findings, normalize into 3 tables
-- Findings that drove design decisions:
-- - Receivers repeat heavily -> accounts table needed
-- - Only 5 transaction types -> lookup table
-- - Fraud only in TRANSFER/CASH_OUT -> isFraud critical column

-- =================================
-- creating table accounts
-- =================================
create table if not exists accounts(
account_id varchar(40) not null primary key,
account_type enum('customer', 'merchant')
);

-- =================================
-- creating table transaction_type
-- =================================
create table if not exists transaction_type(
type_id int auto_increment primary key,
type_name varchar(60)
);

-- =================================
-- creating table transactions
-- =================================
create table if not exists transactions(
transaction_id int auto_increment primary key,
step int,
amount decimal(12, 2),
orig_account_id varchar(40),
dest_account_id varchar(40),
type_id int,
oldbalanceOrg decimal(12,2),
newbalanceOrig decimal(12, 2),
oldbalanceDest decimal(12, 2),
newbalanceDest decimal(12, 2),
isFraud Tinyint,	
isFlaggedFraud tinyint,	
foreign key (orig_account_id) references accounts(account_id),
foreign key (dest_account_id) references accounts(account_id),
foreign key (type_id) references transaction_type(type_id)
);

SHOW TABLES;

-- ============================================================
-- SECTION 5: DATA POPULATION
-- ============================================================
-- Purpose: Split paysim_raw into normalized tables
-- Order matters: transaction_type -> accounts -> transactions

CREATE INDEX idx_nameOrig ON paysim_raw(nameOrig);
CREATE INDEX idx_nameDest ON paysim_raw(nameDest);

-- =================================
-- inserting in table accounts
-- =================================
INSERT INTO accounts (account_id, account_type)
SELECT DISTINCT nameOrig, 
    CASE WHEN LEFT(nameOrig, 1) = 'C' THEN 'customer' ELSE 'merchant' END
FROM paysim_raw
UNION
SELECT DISTINCT nameDest,
    CASE WHEN LEFT(nameDest, 1) = 'C' THEN 'customer' ELSE 'merchant' END
FROM paysim_raw;
SELECT * FROM accounts;
SELECT COUNT(*) FROM accounts; 
SELECT * FROM accounts LIMIT 10;

-- =================================
-- inserting in table transaction_type
-- =================================
INSERT INTO transaction_type (type_name)
SELECT DISTINCT type FROM paysim_raw;

SELECT * FROM transaction_type;

-- =================================
-- inserting in table transaction
-- =================================
INSERT INTO transactions (step, amount, orig_account_id, dest_account_id, type_id, oldbalanceOrg, newbalanceOrig, oldbalanceDest, newbalanceDest, isFraud, isFlaggedFraud)
SELECT 
    p.step,
    p.amount,
    p.nameOrig,
    p.nameDest,
    tt.type_id,
    p.oldbalanceOrg,
    p.newbalanceOrig,
    p.oldbalanceDest,
    p.newbalanceDest,
    p.isFraud,
    p.isFlaggedFraud
FROM paysim_raw p
JOIN transaction_type tt ON p.type = tt.type_name;
SELECT COUNT(*) FROM transactions; 
SELECT * FROM transactions;


-- ====================================
-- Query for verification if keys are correct
-- ====================================
SELECT 
    t.transaction_id,
    t.step,
    t.amount,
    a1.account_id AS sender,
    a1.account_type AS sender_type,
    a2.account_id AS receiver,
    a2.account_type AS receiver_type,
    tt.type_name,
    t.isFraud
FROM transactions t
JOIN accounts a1 ON t.orig_account_id = a1.account_id
JOIN accounts a2 ON t.dest_account_id = a2.account_id
JOIN transaction_type tt ON t.type_id = tt.type_id
LIMIT 10;

-- ============================================================
-- SECTION 6: FRAUD DETECTION QUERIES
-- ============================================================
-- Purpose: Answer the real question — who's the thief?
-- Finding 1: Top receiver accounts collecting fraud money
-- Finding 2: Fraud concentrated in TRANSFER and CASH_OUT only
-- Finding 3: 98% of fraud completely drains sender account
-- Finding 4: Built-in system catches only 0.2% of real fraud

-- =========================================
-- Actual queries to detect the fraud.
-- Which receiver accounts have the most fraud
-- transactions landing on them?
-- =========================================
Select a2.account_id, count(t.isFraud), a2.account_type , sum(t.amount) as total_amount from transactions as t
join accounts as a2 on a2.account_id = t.dest_account_id
where isFraud = 1
group by a2.account_id, a2.account_type 
order by total_amount desc
limit 10;

-- ===========================================
-- Which transaction types are fraud concentrated in?
-- ===========================================
select tt.type_name, sum(t.isFraud) as total_fraud, avg(t.isFraud)*100 as percent_fraud 
from transactions as t
join transaction_type as tt on tt.type_id = t.type_id
group by type_name 
order by percent_fraud desc; 

CREATE INDEX idx_isFraud ON transactions(isFraud);
CREATE INDEX idx_type_id ON transactions(type_id);
CREATE INDEX idx_dest ON transactions(dest_account_id);
CREATE INDEX idx_orig ON transactions(orig_account_id);

-- ===========================================
-- are fraud transactions draining accounts completely? 
-- ===========================================
select count(case when newbalanceOrig = 0 then 1 end) as drained, 
		count(case when newbalanceOrig != 0 then 1 end) as not_drained
from transactions
where isFraud = 1
limit 10;




-- =======================================
-- Compare isFraud vs isFlaggedFraud.
-- how much did the built-in system miss?
-- =======================================
select COUNT(*) AS total_fraud, count(case when isFraud = 1 and isFlaggedFraud = 1 then 1 end ) as detected, 
count(case when isFraud = 1 and isFlaggedFraud = 0 then 1 end) as not_detected
from transactions
where isFraud= 1;


-- =======================================
-- Verifying SQL Query  due to same results
-- =======================================
SELECT dest_account_id, SUM(amount) AS total_fraud_amount, COUNT(*) AS txn_count
FROM transactions
WHERE isFraud = 1
GROUP BY dest_account_id
ORDER BY total_fraud_amount DESC
LIMIT 10;



-- =============================
-- Exporting for Tableau Dashboard
-- =============================
SELECT 
    t.transaction_id, t.step, t.amount,
    t.orig_account_id, a1.account_type AS orig_type,
    t.dest_account_id, a2.account_type AS dest_type,
    tt.type_name, t.oldbalanceOrg, t.newbalanceOrig,
    t.isFraud, t.isFlaggedFraud
FROM transactions t
JOIN accounts a1 ON t.orig_account_id = a1.account_id
JOIN accounts a2 ON t.dest_account_id = a2.account_id
JOIN transaction_type tt ON t.type_id = tt.type_id;





