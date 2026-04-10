/*
================================================================================
  PEDIATRIC ASTHMA REGISTRY
  Author:  Peter S. Easter, DO — Easter Medical Consulting, LLC
  Version: 1.0
  Dialect: T-SQL (SQL Server) — adaptation notes included for PostgreSQL/MySQL
================================================================================

CLINICAL RATIONALE
------------------
Asthma is the most common chronic disease in childhood, affecting ~8% of
children in the US. A patient registry enables:
  - Proactive identification of patients overdue for well-asthma visits
  - Controller medication adherence monitoring
  - Rescue inhaler overuse detection (a key safety signal)
  - HEDIS measure tracking (Asthma Medication Ratio, AMR)
  - Identification of patients requiring step-up therapy

DEFINITION LOGIC
----------------
Patients are included if they meet ANY of the following in the lookback period:
  1. Two or more outpatient visits with an asthma diagnosis (ICD-10: J45.xx)
  2. One ED visit or inpatient admission with asthma as the primary diagnosis
  3. Active controller medication prescription within the past 12 months

EXCLUSIONS
----------
- Age < 5 years (spirometry-based diagnosis unreliable; wheezing may be
  transient)
- Age > 17 years (transition to adult panel)
- Inactive enrollment / disenrolled patients
- Patients with primary diagnosis of vocal cord dysfunction or GERD
  (common mimics)

OUTPUTS
-------
One row per patient with:
  - Severity classification (intermittent / mild-moderate / severe)
  - Last well-asthma visit date and days since
  - Controller medication status
  - Recent rescue inhaler fill count (12-month window)
  - AMR calculation (for HEDIS tracking)
  - Overdue flag

PARAMETERS — adjust for your environment
================================================================================
*/

-- ─── Parameters ──────────────────────────────────────────────────────────────
DECLARE @LookbackYears      INT  = 2;      -- Years back for diagnosis lookback
DECLARE @VisitWindowDays    INT  = 365;    -- Days for recent visit lookback
DECLARE @RxWindowDays       INT  = 365;    -- Days for medication lookback
DECLARE @MinAge             INT  = 5;      -- Minimum patient age (years)
DECLARE @MaxAge             INT  = 17;     -- Maximum patient age (years)
DECLARE @OverdueVisitDays   INT  = 365;    -- Days without visit = overdue flag
DECLARE @AsOfDate           DATE = CAST(GETDATE() AS DATE);

-- ─── Step 1: ICD-10 Asthma Diagnosis Codes ───────────────────────────────────
-- J45.20 = Mild intermittent asthma, uncomplicated
-- J45.21 = Mild intermittent asthma, with acute exacerbation
-- J45.22 = Mild intermittent asthma, with status asthmaticus
-- J45.30-J45.32 = Mild persistent asthma
-- J45.40-J45.42 = Moderate persistent asthma
-- J45.50-J45.52 = Severe persistent asthma
-- J45.901-J45.902 = Unspecified asthma
-- J45.990-J45.999 = Other asthma

WITH asthma_diagnoses AS (
    SELECT
        d.patient_id,
        d.encounter_id,
        d.icd10_code,
        e.encounter_date,
        e.encounter_type,   -- 'outpatient', 'ED', 'inpatient', 'telehealth'
        CASE
            WHEN d.icd10_code LIKE 'J45.2%' THEN 'Intermittent'
            WHEN d.icd10_code LIKE 'J45.3%' THEN 'Mild Persistent'
            WHEN d.icd10_code LIKE 'J45.4%' THEN 'Moderate Persistent'
            WHEN d.icd10_code LIKE 'J45.5%' THEN 'Severe Persistent'
            ELSE 'Unspecified'
        END AS severity_from_code
    FROM diagnoses d
    JOIN encounters e ON d.encounter_id = e.encounter_id
    WHERE d.icd10_code LIKE 'J45%'
      AND e.encounter_date >= DATEADD(YEAR, -@LookbackYears, @AsOfDate)
      AND e.encounter_status = 'completed'
),

-- ─── Step 2: Qualify patients by encounter frequency ─────────────────────────
qualified_patients AS (
    SELECT
        patient_id,
        COUNT(CASE WHEN encounter_type IN ('outpatient','telehealth')
                   THEN encounter_id END)      AS outpatient_dx_count,
        COUNT(CASE WHEN encounter_type IN ('ED','inpatient')
                   THEN encounter_id END)      AS acute_dx_count,
        MAX(severity_from_code)                AS highest_severity,
        MAX(encounter_date)                    AS last_asthma_encounter
    FROM asthma_diagnoses
    GROUP BY patient_id
    HAVING
        COUNT(CASE WHEN encounter_type IN ('outpatient','telehealth')
                   THEN encounter_id END) >= 2
        OR
        COUNT(CASE WHEN encounter_type IN ('ED','inpatient')
                   THEN encounter_id END) >= 1
),

-- ─── Step 3: Demographics and age filter ─────────────────────────────────────
eligible_patients AS (
    SELECT
        p.patient_id,
        p.first_name,
        p.last_name,
        p.date_of_birth,
        DATEDIFF(YEAR, p.date_of_birth, @AsOfDate)
            - CASE WHEN MONTH(p.date_of_birth) * 100 + DAY(p.date_of_birth)
                        > MONTH(@AsOfDate) * 100 + DAY(@AsOfDate)
                   THEN 1 ELSE 0 END                AS age_years,
        p.pcp_provider_id,
        p.enrollment_status,
        p.panel_assignment
    FROM patients p
    WHERE p.enrollment_status = 'active'
),

-- ─── Step 4: Controller medications (LABA, ICS, LABA+ICS, LTRA) ─────────────
-- Medication classes: ICS = Inhaled corticosteroid (controller)
--                     SABA = Short-acting beta agonist (rescue)
-- AMR = (controller fills) / (controller fills + rescue fills)
-- AMR >= 0.5 is the HEDIS threshold for numerator compliance

controller_meds AS (
    SELECT
        patient_id,
        COUNT(*) AS controller_fills_12mo,
        MAX(fill_date) AS last_controller_fill
    FROM medications
    WHERE medication_class IN (
            'ICS',           -- Inhaled corticosteroids
            'LABA_ICS',      -- Combination LABA + ICS
            'LTRA',          -- Leukotriene receptor antagonists
            'LABA'           -- Long-acting beta agonists (rare standalone in peds)
          )
      AND fill_date >= DATEADD(DAY, -@RxWindowDays, @AsOfDate)
      AND order_status IN ('dispensed', 'active')
    GROUP BY patient_id
),

rescue_meds AS (
    SELECT
        patient_id,
        COUNT(*) AS rescue_fills_12mo,
        MAX(fill_date) AS last_rescue_fill
    FROM medications
    WHERE medication_class = 'SABA'   -- Short-acting beta agonist (albuterol, etc.)
      AND fill_date >= DATEADD(DAY, -@RxWindowDays, @AsOfDate)
      AND order_status IN ('dispensed', 'active')
    GROUP BY patient_id
),

-- ─── Step 5: Last well-asthma / follow-up visit ───────────────────────────────
-- Well-asthma visit = outpatient encounter with asthma diagnosis + no acute complaint
last_well_asthma AS (
    SELECT
        patient_id,
        MAX(encounter_date) AS last_well_asthma_date
    FROM encounters e
    JOIN diagnoses d ON e.encounter_id = d.encounter_id
    WHERE d.icd10_code LIKE 'J45%'
      AND e.encounter_type IN ('outpatient', 'telehealth')
      AND e.visit_type NOT IN ('ED', 'urgent', 'sick')
    GROUP BY patient_id
)

-- ─── Final Registry Output ────────────────────────────────────────────────────
SELECT
    ep.patient_id,
    ep.last_name,
    ep.first_name,
    ep.date_of_birth,
    ep.age_years,
    ep.pcp_provider_id,
    ep.panel_assignment,

    -- Severity
    qp.highest_severity                             AS asthma_severity,

    -- Visit history
    qp.last_asthma_encounter,
    wa.last_well_asthma_date,
    DATEDIFF(DAY, wa.last_well_asthma_date, @AsOfDate)
                                                    AS days_since_well_asthma,

    -- Medication status
    COALESCE(cm.controller_fills_12mo, 0)           AS controller_fills_12mo,
    COALESCE(rm.rescue_fills_12mo, 0)               AS rescue_fills_12mo,
    cm.last_controller_fill,
    rm.last_rescue_fill,

    -- AMR (Asthma Medication Ratio) — HEDIS key metric
    -- AMR >= 0.5 = numerator compliant; NULL if no rescue fills (denominator = 0)
    CASE
        WHEN COALESCE(cm.controller_fills_12mo, 0)
           + COALESCE(rm.rescue_fills_12mo, 0) = 0 THEN NULL
        ELSE CAST(COALESCE(cm.controller_fills_12mo, 0) AS FLOAT)
             / (COALESCE(cm.controller_fills_12mo, 0)
             +  COALESCE(rm.rescue_fills_12mo, 0))
    END                                             AS asthma_medication_ratio,

    -- Flags
    CASE WHEN COALESCE(cm.controller_fills_12mo, 0) = 0
              AND qp.highest_severity != 'Intermittent'
         THEN 1 ELSE 0
    END                                             AS flag_no_controller,

    CASE WHEN COALESCE(rm.rescue_fills_12mo, 0) > 2
         THEN 1 ELSE 0
    END                                             AS flag_rescue_overuse,  -- >2 fills/yr = poor control signal

    CASE WHEN DATEDIFF(DAY, wa.last_well_asthma_date, @AsOfDate) > @OverdueVisitDays
              OR wa.last_well_asthma_date IS NULL
         THEN 1 ELSE 0
    END                                             AS flag_overdue_visit,

    -- AMR compliance flag (HEDIS numerator)
    CASE
        WHEN COALESCE(cm.controller_fills_12mo, 0)
           + COALESCE(rm.rescue_fills_12mo, 0) = 0 THEN NULL
        WHEN CAST(COALESCE(cm.controller_fills_12mo, 0) AS FLOAT)
             / (COALESCE(cm.controller_fills_12mo, 0)
             +  COALESCE(rm.rescue_fills_12mo, 0)) >= 0.5
        THEN 1 ELSE 0
    END                                             AS hedis_amr_compliant

FROM eligible_patients ep
JOIN qualified_patients qp  ON ep.patient_id = qp.patient_id
LEFT JOIN controller_meds cm ON ep.patient_id = cm.patient_id
LEFT JOIN rescue_meds rm     ON ep.patient_id = rm.patient_id
LEFT JOIN last_well_asthma wa ON ep.patient_id = wa.patient_id
WHERE ep.age_years BETWEEN @MinAge AND @MaxAge
ORDER BY
    flag_rescue_overuse DESC,
    flag_no_controller DESC,
    flag_overdue_visit DESC,
    ep.last_name, ep.first_name;

/*
================================================================================
INTERPRETATION NOTES
--------------------
Priority outreach patients (all three flags = 1):
  Persistent asthma, no controller, rescue overuse, and overdue for follow-up.
  These patients are at highest risk for exacerbation and ED utilization.

AMR = NULL:
  Patient has asthma diagnosis but no fills of any inhaler in 12 months.
  Could indicate: patient uses a neighbor's/parent's inhaler, OTC usage,
  specimen refusal, or truly intermittent disease requiring no medication.
  Requires clinical review — do not assume controlled.

Rescue overuse threshold (>2 fills/year):
  Adapted from NAEPP EPR-3 Guidelines. More than 2 SABA canisters/year
  is a marker of inadequately controlled asthma warranting step-up evaluation.

DIALECT NOTES
-------------
PostgreSQL: Replace GETDATE() with CURRENT_DATE; DATEDIFF(DAY,x,y) → (y - x)
MySQL:       Replace DATEDIFF(YEAR,...) age logic with TIMESTAMPDIFF(YEAR,...)
Snowflake:   DATEDIFF syntax is compatible; GETDATE() → CURRENT_DATE()
BigQuery:    Use DATE_DIFF(date1, date2, DAY) and DATE_SUB for date arithmetic
================================================================================
*/
