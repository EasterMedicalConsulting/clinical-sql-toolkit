/*
================================================================================
  PEDIATRIC LEAD & ANEMIA SCREENING CARE GAPS
  Author:  Peter S. Easter, DO — Easter Medical Consulting, LLC
  Version: 1.0
  Dialect: T-SQL (SQL Server) — adaptation notes included
================================================================================

CLINICAL RATIONALE
------------------
Lead poisoning and iron-deficiency anemia are the two most common preventable
environmental and nutritional conditions affecting young children in the US.
Both are asymptomatic until advanced — making structured screening the only
reliable detection method.

  LEAD:
  - AAP and CDC recommend universal blood lead testing at ages 12 and 24 months
    in high-risk populations; many states mandate universal screening
  - Even low blood lead levels (<5 mcg/dL) are associated with cognitive and
    behavioral sequelae; there is no safe threshold
  - Medicaid EPSDT regulations require lead screening at 12 and 24 months for
    all enrolled children

  ANEMIA:
  - AAP recommends hemoglobin or hematocrit screening at 12 months
  - Iron deficiency affects ~9% of children aged 1-3; higher rates in
    low-income, exclusively breastfed, and preterm populations
  - Routine screening enables early intervention before cognitive effects accrue

MEASURE LOGIC
-------------
Patients are flagged as having a care gap if they:
  - Are in the eligible age window (see parameters)
  - Have had a qualifying well-child visit (establishes the opportunity)
  - Do NOT have a documented result for the required test within the
    measurement window

RELATED PUBLICATION
-------------------
Walton C, Law C, Easter PS. Improving Lead and Anemia Screening Rates within
Wilford Hall Pediatric Clinic. San Antonio Uniformed Health Consortium
Patient Safety Week, 2026.

================================================================================
*/

-- ─── Parameters ──────────────────────────────────────────────────────────────
DECLARE @AsOfDate       DATE = CAST(GETDATE() AS DATE);

-- Lead screening windows: 12-month visit ± 3 months, 24-month visit ± 3 months
DECLARE @Lead12_AgeMin  INT  = 9;    -- months
DECLARE @Lead12_AgeMax  INT  = 15;
DECLARE @Lead24_AgeMin  INT  = 21;
DECLARE @Lead24_AgeMax  INT  = 30;

-- Anemia screening: hemoglobin at 12-month visit ± 3 months
DECLARE @Anemia_AgeMin  INT  = 9;
DECLARE @Anemia_AgeMax  INT  = 15;

-- LOINC codes for relevant labs
-- 5671-3  = Blood lead, venous (preferred)
-- 10831-3 = Blood lead, capillary (acceptable; confirm reflex venous if elevated)
-- 718-7   = Hemoglobin [Mass/volume] in Blood
-- 4544-3  = Hematocrit [Volume Fraction] of Blood

-- ─── Step 1: Eligible patient population ─────────────────────────────────────
WITH patient_ages AS (
    SELECT
        p.patient_id,
        p.first_name,
        p.last_name,
        p.date_of_birth,
        p.pcp_provider_id,
        p.enrollment_status,
        p.panel_assignment,
        DATEDIFF(MONTH, p.date_of_birth, @AsOfDate) AS age_months
    FROM patients p
    WHERE p.enrollment_status = 'active'
      AND DATEDIFF(MONTH, p.date_of_birth, @AsOfDate)
          BETWEEN @Lead12_AgeMin AND @Lead24_AgeMax  -- broadest eligible window
),

-- ─── Step 2: Well-child visits (establishes screening opportunity) ────────────
-- CPT codes for well-child visits by age:
--   99381-99385 = New patient preventive visits
--   99391-99395 = Established patient preventive visits
-- ICD-10: Z00.121 (encounter for health check for child under 29 days)
--         Z00.129, Z00.00 (routine child health exam)

well_child_visits AS (
    SELECT DISTINCT
        e.patient_id,
        e.encounter_date,
        DATEDIFF(MONTH, pa.date_of_birth, e.encounter_date) AS age_at_visit_months
    FROM encounters e
    JOIN patient_ages pa ON e.patient_id = pa.patient_id
    WHERE (
            e.cpt_code IN ('99381','99382','99391','99392')  -- infant/toddler well visits
            OR e.visit_type = 'well_child'
          )
      AND e.encounter_status = 'completed'
),

-- ─── Step 3: Lead screening results ──────────────────────────────────────────
lead_results AS (
    SELECT
        patient_id,
        result_date,
        loinc_code,
        result_value,
        result_units,
        DATEDIFF(MONTH, pa.date_of_birth, lr.result_date) AS age_at_result_months
    FROM lab_results lr
    JOIN patient_ages pa ON lr.patient_id = pa.patient_id
    WHERE lr.loinc_code IN ('5671-3', '10831-3')
      AND lr.result_status = 'final'
),

-- ─── Step 4: Anemia screening results ────────────────────────────────────────
anemia_results AS (
    SELECT
        patient_id,
        result_date,
        loinc_code,
        result_value,
        DATEDIFF(MONTH, pa.date_of_birth, ar.result_date) AS age_at_result_months
    FROM lab_results ar
    JOIN patient_ages pa ON ar.patient_id = pa.patient_id
    WHERE ar.loinc_code IN ('718-7', '4544-3')
      AND ar.result_status = 'final'
),

-- ─── Step 5: Lead 12-month gap ───────────────────────────────────────────────
lead_12_gap AS (
    SELECT
        pa.patient_id,
        1 AS eligible_for_lead_12,
        CASE WHEN EXISTS (
            SELECT 1 FROM lead_results lr
            WHERE lr.patient_id = pa.patient_id
              AND lr.age_at_result_months BETWEEN @Lead12_AgeMin AND @Lead12_AgeMax
        ) THEN 0 ELSE 1 END AS gap_lead_12mo
    FROM patient_ages pa
    WHERE pa.age_months BETWEEN @Lead12_AgeMin AND @Lead12_AgeMax
      AND EXISTS (
          SELECT 1 FROM well_child_visits wcv
          WHERE wcv.patient_id = pa.patient_id
            AND wcv.age_at_visit_months BETWEEN @Lead12_AgeMin AND @Lead12_AgeMax
      )
),

-- ─── Step 6: Lead 24-month gap ───────────────────────────────────────────────
lead_24_gap AS (
    SELECT
        pa.patient_id,
        1 AS eligible_for_lead_24,
        CASE WHEN EXISTS (
            SELECT 1 FROM lead_results lr
            WHERE lr.patient_id = pa.patient_id
              AND lr.age_at_result_months BETWEEN @Lead24_AgeMin AND @Lead24_AgeMax
        ) THEN 0 ELSE 1 END AS gap_lead_24mo
    FROM patient_ages pa
    WHERE pa.age_months BETWEEN @Lead24_AgeMin AND @Lead24_AgeMax
      AND EXISTS (
          SELECT 1 FROM well_child_visits wcv
          WHERE wcv.patient_id = pa.patient_id
            AND wcv.age_at_visit_months BETWEEN @Lead24_AgeMin AND @Lead24_AgeMax
      )
),

-- ─── Step 7: Anemia gap ───────────────────────────────────────────────────────
anemia_gap AS (
    SELECT
        pa.patient_id,
        1 AS eligible_for_anemia,
        CASE WHEN EXISTS (
            SELECT 1 FROM anemia_results ar
            WHERE ar.patient_id = pa.patient_id
              AND ar.age_at_result_months BETWEEN @Anemia_AgeMin AND @Anemia_AgeMax
        ) THEN 0 ELSE 1 END AS gap_anemia
    FROM patient_ages pa
    WHERE pa.age_months BETWEEN @Anemia_AgeMin AND @Anemia_AgeMax
      AND EXISTS (
          SELECT 1 FROM well_child_visits wcv
          WHERE wcv.patient_id = pa.patient_id
            AND wcv.age_at_visit_months BETWEEN @Anemia_AgeMin AND @Anemia_AgeMax
      )
),

-- ─── Step 8: Most recent well-child visit (for outreach context) ──────────────
last_wcv AS (
    SELECT
        patient_id,
        MAX(encounter_date) AS last_well_child_date
    FROM well_child_visits
    GROUP BY patient_id
)

-- ─── Final Output: Care Gap Summary ──────────────────────────────────────────
SELECT
    pa.patient_id,
    pa.last_name,
    pa.first_name,
    pa.date_of_birth,
    pa.age_months,
    pa.pcp_provider_id,
    pa.panel_assignment,
    lwcv.last_well_child_date,

    -- Eligibility flags
    COALESCE(l12.eligible_for_lead_12, 0)   AS eligible_lead_12,
    COALESCE(l24.eligible_for_lead_24, 0)   AS eligible_lead_24,
    COALESCE(ag.eligible_for_anemia, 0)     AS eligible_anemia,

    -- Gap flags (1 = gap exists, screening due/overdue)
    COALESCE(l12.gap_lead_12mo, 0)          AS gap_lead_12mo,
    COALESCE(l24.gap_lead_24mo, 0)          AS gap_lead_24mo,
    COALESCE(ag.gap_anemia, 0)              AS gap_anemia_12mo,

    -- Total gaps for this patient
    COALESCE(l12.gap_lead_12mo, 0)
        + COALESCE(l24.gap_lead_24mo, 0)
        + COALESCE(ag.gap_anemia, 0)        AS total_gaps,

    -- Outreach priority flag (any gap present)
    CASE WHEN COALESCE(l12.gap_lead_12mo, 0)
              + COALESCE(l24.gap_lead_24mo, 0)
              + COALESCE(ag.gap_anemia, 0) > 0
         THEN 1 ELSE 0 END                  AS outreach_needed

FROM patient_ages pa
LEFT JOIN lead_12_gap l12  ON pa.patient_id = l12.patient_id
LEFT JOIN lead_24_gap l24  ON pa.patient_id = l24.patient_id
LEFT JOIN anemia_gap ag    ON pa.patient_id = ag.patient_id
LEFT JOIN last_wcv lwcv    ON pa.patient_id = lwcv.patient_id
WHERE
    COALESCE(l12.eligible_for_lead_12, 0)
    + COALESCE(l24.eligible_for_lead_24, 0)
    + COALESCE(ag.eligible_for_anemia, 0) > 0  -- at least one eligible measure
ORDER BY
    total_gaps DESC,
    pa.pcp_provider_id,
    pa.last_name;

/*
================================================================================
AGGREGATION QUERY — Screening Rate by Provider Panel
Use this to generate the QI dashboard view or provider report card.
================================================================================
*/
/*
SELECT
    pa.pcp_provider_id,
    COUNT(DISTINCT pa.patient_id)                              AS panel_size,

    -- Lead 12-month rate
    SUM(COALESCE(l12.eligible_for_lead_12, 0))                AS eligible_lead_12,
    SUM(CASE WHEN COALESCE(l12.gap_lead_12mo, 0) = 0
                  AND COALESCE(l12.eligible_for_lead_12,0) = 1
             THEN 1 ELSE 0 END)                               AS screened_lead_12,
    CAST(SUM(CASE WHEN COALESCE(l12.gap_lead_12mo, 0) = 0
                       AND COALESCE(l12.eligible_for_lead_12,0) = 1
                  THEN 1 ELSE 0 END) AS FLOAT)
    / NULLIF(SUM(COALESCE(l12.eligible_for_lead_12,0)),0)     AS rate_lead_12,

    -- Anemia rate
    SUM(COALESCE(ag.eligible_for_anemia, 0))                  AS eligible_anemia,
    SUM(CASE WHEN COALESCE(ag.gap_anemia, 0) = 0
                  AND COALESCE(ag.eligible_for_anemia,0) = 1
             THEN 1 ELSE 0 END)                               AS screened_anemia,
    CAST(SUM(CASE WHEN COALESCE(ag.gap_anemia, 0) = 0
                       AND COALESCE(ag.eligible_for_anemia,0) = 1
                  THEN 1 ELSE 0 END) AS FLOAT)
    / NULLIF(SUM(COALESCE(ag.eligible_for_anemia,0)),0)       AS rate_anemia

FROM patient_ages pa
LEFT JOIN lead_12_gap l12  ON pa.patient_id = l12.patient_id
LEFT JOIN anemia_gap ag    ON pa.patient_id = ag.patient_id
GROUP BY pa.pcp_provider_id
ORDER BY rate_lead_12 ASC;  -- lowest performers first for QI targeting
*/

/*
================================================================================
INTERPRETATION NOTES
--------------------
Capillary lead (LOINC 10831-3):
  Acceptable for initial screening but has higher false-positive rates due to
  skin contamination. Any capillary result >= 3.5 mcg/dL should prompt
  confirmatory venous testing. Both results should be captured separately.

Gap vs. refusal:
  A documented patient/parent refusal of screening should be captured in your
  EHR and excluded from the denominator if your organization follows NCQA
  exclusion logic. Modify the gap CTEs to JOIN against a refusal table if
  your system captures this.

Medicaid EPSDT compliance:
  For Medicaid-enrolled patients, lead screening at 12 and 24 months is a
  federal requirement under EPSDT. Consider adding a Medicaid enrollment flag
  to segment reporting by payer.

DIALECT NOTES
-------------
PostgreSQL: DATEDIFF(MONTH, x, y) → EXTRACT(YEAR FROM AGE(y,x))*12 + EXTRACT(MONTH FROM AGE(y,x))
MySQL:      Use TIMESTAMPDIFF(MONTH, date_of_birth, @AsOfDate)
Snowflake:  DATEDIFF('month', date_of_birth, CURRENT_DATE())
BigQuery:   DATE_DIFF(current_date, date_of_birth, MONTH)
================================================================================
*/
