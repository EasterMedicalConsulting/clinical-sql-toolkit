/*
================================================================================
  CLINICAL DATE & AGE UTILITY FUNCTIONS
  Author:  Peter S. Easter, DO — Easter Medical Consulting, LLC
  Version: 1.0
  Dialect: T-SQL (SQL Server) — adaptation notes for major dialects included
================================================================================

OVERVIEW
--------
Date arithmetic is one of the most common sources of bugs in clinical SQL.
This file provides tested, documented patterns for the age and interval
calculations that appear repeatedly in clinical analytics:

  1. Accurate age in years (birthday-aware)
  2. Age in months (for pediatric growth, vaccination, and screening logic)
  3. Fiscal year / reporting period assignment
  4. Measurement year determination (HEDIS standard)
  5. Date range parameter templates

These are NOT stored procedures — they are inline patterns intended to be
copied into your queries. Each pattern is self-contained and annotated.

================================================================================
*/

-- ─── 1. ACCURATE AGE IN YEARS ─────────────────────────────────────────────────
-- The naive DATEDIFF(YEAR, dob, today) approach is wrong — it counts year
-- boundaries crossed, not actual birthdays. A patient born 12/31/2000 would
-- show as age 24 on 01/01/2024 using naive logic.

-- CORRECT: Birthday-aware age in years (T-SQL)
SELECT
    patient_id,
    date_of_birth,
    DATEDIFF(YEAR, date_of_birth, GETDATE())
        - CASE
            WHEN MONTH(date_of_birth) * 100 + DAY(date_of_birth)
                 > MONTH(GETDATE()) * 100 + DAY(GETDATE())
            THEN 1
            ELSE 0
          END AS age_years_correct

    -- WRONG (do not use):
    -- DATEDIFF(YEAR, date_of_birth, GETDATE()) AS age_years_wrong
FROM patients;

/*
PostgreSQL equivalent:
  DATE_PART('year', AGE(CURRENT_DATE, date_of_birth)) AS age_years

MySQL equivalent:
  TIMESTAMPDIFF(YEAR, date_of_birth, CURDATE()) AS age_years
  -- MySQL's TIMESTAMPDIFF handles the birthday correctly natively

Snowflake equivalent:
  DATEDIFF('year', date_of_birth, CURRENT_DATE()) -- WRONG in Snowflake too
  -- Use: FLOOR(DATEDIFF('day', date_of_birth, CURRENT_DATE()) / 365.25)
  -- Or:  YEAR(CURRENT_DATE()) - YEAR(date_of_birth)
  --      - CASE WHEN (MONTH(date_of_birth) * 100 + DAY(date_of_birth))
  --                  > (MONTH(CURRENT_DATE()) * 100 + DAY(CURRENT_DATE()))
  --             THEN 1 ELSE 0 END

BigQuery equivalent:
  DATE_DIFF(CURRENT_DATE(), date_of_birth, YEAR)
    - IF(FORMAT_DATE('%m%d', date_of_birth) > FORMAT_DATE('%m%d', CURRENT_DATE()), 1, 0)
*/


-- ─── 2. AGE IN MONTHS (Pediatric critical — vaccination, screening, growth) ───
-- Used for: lead screening windows, well-child visit eligibility, vaccine timing

SELECT
    patient_id,
    date_of_birth,
    DATEDIFF(MONTH, date_of_birth, GETDATE()) AS age_months_approx,
    -- Note: DATEDIFF(MONTH,...) counts month boundaries, not exact months.
    -- For most pediatric screening logic (± 3 month windows), this is acceptable.
    -- For precise day-level accuracy, use the formula below:
    (DATEDIFF(YEAR, date_of_birth, GETDATE()) * 12)
        + MONTH(GETDATE()) - MONTH(date_of_birth)
        - CASE WHEN DAY(date_of_birth) > DAY(GETDATE()) THEN 1 ELSE 0 END
        AS age_months_precise
FROM patients;


-- ─── 3. FISCAL YEAR ASSIGNMENT ───────────────────────────────────────────────
-- Adjust @FiscalYearStartMonth to match your organization (DoD FY = October)

DECLARE @FiscalYearStartMonth INT = 10;  -- October for DoD; 7 for many health systems

SELECT
    encounter_date,
    CASE
        WHEN MONTH(encounter_date) >= @FiscalYearStartMonth
        THEN YEAR(encounter_date) + 1
        ELSE YEAR(encounter_date)
    END AS fiscal_year,
    CASE
        WHEN MONTH(encounter_date) >= @FiscalYearStartMonth
        THEN DATEDIFF(QUARTER,
                      DATEFROMPARTS(YEAR(encounter_date), @FiscalYearStartMonth, 1),
                      encounter_date) + 1
        ELSE DATEDIFF(QUARTER,
                      DATEFROMPARTS(YEAR(encounter_date) - 1, @FiscalYearStartMonth, 1),
                      encounter_date) + 1
    END AS fiscal_quarter
FROM encounters;


-- ─── 4. HEDIS MEASUREMENT YEAR ───────────────────────────────────────────────
-- HEDIS measures use the calendar year (Jan 1 – Dec 31)
-- "Measurement Year" (MY) and "Year Prior to Measurement Year" (YPMY)
-- are standard NCQA terms

DECLARE @MeasurementYear INT = YEAR(GETDATE()) - 1;  -- Prior full calendar year

SELECT
    DATEFROMPARTS(@MeasurementYear, 1, 1)   AS my_start_date,
    DATEFROMPARTS(@MeasurementYear, 12, 31) AS my_end_date,
    DATEFROMPARTS(@MeasurementYear - 1, 1, 1)   AS ypmy_start_date,
    DATEFROMPARTS(@MeasurementYear - 1, 12, 31) AS ypmy_end_date;


-- ─── 5. STANDARD DATE RANGE PARAMETER TEMPLATE ───────────────────────────────
-- Copy this block to the top of any new clinical query

/*
-- Standard lookback parameters (copy-paste template)
DECLARE @AsOfDate       DATE = CAST(GETDATE() AS DATE);
DECLARE @StartDate_12mo DATE = DATEADD(MONTH, -12, @AsOfDate);
DECLARE @StartDate_24mo DATE = DATEADD(MONTH, -24, @AsOfDate);
DECLARE @StartDate_36mo DATE = DATEADD(MONTH, -36, @AsOfDate);
DECLARE @FY_Start       DATE = DATEFROMPARTS(YEAR(@AsOfDate) - 1, 10, 1);  -- DoD FY
DECLARE @FY_End         DATE = DATEFROMPARTS(YEAR(@AsOfDate), 9, 30);

-- Calendar year (HEDIS-style)
DECLARE @CY_Start DATE = DATEFROMPARTS(YEAR(@AsOfDate) - 1, 1, 1);
DECLARE @CY_End   DATE = DATEFROMPARTS(YEAR(@AsOfDate) - 1, 12, 31);
*/


-- ─── 6. AGE GROUP BUCKETING ──────────────────────────────────────────────────
-- Standard pediatric age groupings for population reports

SELECT
    patient_id,
    age_years,
    CASE
        WHEN age_years < 1   THEN 'Infant (< 1 yr)'
        WHEN age_years < 2   THEN 'Toddler (1 yr)'
        WHEN age_years < 5   THEN 'Early Childhood (2-4 yrs)'
        WHEN age_years < 12  THEN 'School Age (5-11 yrs)'
        WHEN age_years < 18  THEN 'Adolescent (12-17 yrs)'
        ELSE                      'Adult (18+)'
    END AS pediatric_age_group,
    -- AAP well-child visit schedule alignment
    CASE
        WHEN age_years_months < 2    THEN 'Newborn Period'
        WHEN age_years_months < 12   THEN 'Infant (2-11 mo)'
        WHEN age_years_months < 24   THEN '12-Month Window'
        WHEN age_years_months < 36   THEN '24-Month Window'
        ELSE                              'Preschool / School Age'
    END AS aap_visit_group
FROM (
    SELECT
        patient_id,
        -- insert age_years calculation here
        0 AS age_years,
        0 AS age_years_months  -- in months
) age_calc;
