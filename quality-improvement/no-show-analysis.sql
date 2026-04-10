/*
================================================================================
  APPOINTMENT NO-SHOW ANALYSIS
  Author:  Peter S. Easter, DO — Easter Medical Consulting, LLC
  Version: 1.0
  Dialect: T-SQL (SQL Server) — adaptation notes included
================================================================================

CLINICAL RATIONALE
------------------
Appointment no-shows are a significant driver of clinic inefficiency, access
inequity, and care continuity failure. No-shows affect:
  - Provider productivity and revenue cycle
  - Panel access for other patients (wasted slots)
  - Care continuity and chronic disease management
  - Quality measure performance (missed care opportunities)

Understanding no-show patterns by scheduling interval, visit type, provider,
day of week, and patient demographics enables targeted interventions:
  - Scheduling interval optimization (double-booking, open-access)
  - Reminder system design (call vs. text vs. automated)
  - Identifying high-risk patients for proactive outreach
  - Reducing same-day cancellation vs. true no-show rates

RELATED PUBLICATION
-------------------
Burneskis JM, Easter PS, Lai MH. The Impact of Scheduling Interval on
No-Show Rates in the Military Health System. Army Medical Department
Graduate Research and Education Symposium, 2018.

MEASURE DEFINITIONS
-------------------
  No-Show Rate    = No-shows / (Scheduled - Provider Cancellations)
  Same-Day Cancel = Patient cancellations within N hours of appointment
  Lead Time       = Days between appointment scheduling date and visit date
  Scheduling Interval = Bucket of lead time (same-day, 1-7d, 8-14d, 15-30d, 31+d)

================================================================================
*/

-- ─── Parameters ──────────────────────────────────────────────────────────────
DECLARE @StartDate          DATE = DATEADD(MONTH, -12, CAST(GETDATE() AS DATE));
DECLARE @EndDate            DATE = CAST(GETDATE() AS DATE);
DECLARE @SameDayCancelHours INT  = 2;   -- Hours before appointment = same-day cancel
DECLARE @AsOfDate           DATE = CAST(GETDATE() AS DATE);

-- ─── Step 1: Base appointment dataset ────────────────────────────────────────
WITH appointments AS (
    SELECT
        a.appointment_id,
        a.patient_id,
        a.provider_id,
        a.clinic_id,
        a.scheduled_date,           -- Date of the appointment
        a.scheduled_time,           -- Time of the appointment
        a.booking_date,             -- Date the appointment was booked
        a.appointment_type,         -- 'well_child', 'sick', 'follow_up', etc.
        a.appointment_status,       -- 'completed', 'no_show', 'cancelled_patient',
                                    --  'cancelled_provider', 'cancelled_clinic', 'rescheduled'
        a.cancellation_date,        -- Date/time of cancellation if applicable
        a.cancellation_reason,

        -- Lead time: days between booking and appointment
        DATEDIFF(DAY, a.booking_date, a.scheduled_date) AS lead_time_days,

        -- Scheduling interval bucket
        CASE
            WHEN DATEDIFF(DAY, a.booking_date, a.scheduled_date) = 0  THEN 'Same-Day'
            WHEN DATEDIFF(DAY, a.booking_date, a.scheduled_date) <= 7  THEN '1-7 Days'
            WHEN DATEDIFF(DAY, a.booking_date, a.scheduled_date) <= 14 THEN '8-14 Days'
            WHEN DATEDIFF(DAY, a.booking_date, a.scheduled_date) <= 30 THEN '15-30 Days'
            WHEN DATEDIFF(DAY, a.booking_date, a.scheduled_date) <= 60 THEN '31-60 Days'
            ELSE '60+ Days'
        END AS scheduling_interval,

        -- Same-day cancellation flag
        CASE
            WHEN a.appointment_status IN ('cancelled_patient','rescheduled')
                 AND DATEDIFF(HOUR, a.cancellation_date,
                              CAST(CAST(a.scheduled_date AS VARCHAR) + ' '
                                   + CAST(a.scheduled_time AS VARCHAR) AS DATETIME)) <= @SameDayCancelHours
            THEN 1 ELSE 0
        END AS same_day_cancel_flag,

        -- Day of week
        DATENAME(WEEKDAY, a.scheduled_date) AS day_of_week,
        DATEPART(WEEKDAY, a.scheduled_date) AS day_of_week_num  -- 1=Sun, 2=Mon...

    FROM appointments a
    WHERE a.scheduled_date BETWEEN @StartDate AND @EndDate
      AND a.appointment_status NOT IN ('cancelled_provider', 'cancelled_clinic')
      -- Exclude provider/clinic cancellations from denominator
),

-- ─── Step 2: Patient demographics for segmentation ───────────────────────────
patient_info AS (
    SELECT
        p.patient_id,
        DATEDIFF(YEAR, p.date_of_birth, @AsOfDate) AS age_years,
        p.zip_code,
        p.payer_type,       -- 'tricare', 'medicaid', 'medicare', 'commercial', 'self_pay'
        p.preferred_language,
        p.race,
        p.ethnicity
    FROM patients p
),

-- ─── Step 3: No-show flags ────────────────────────────────────────────────────
base AS (
    SELECT
        a.*,
        pi.age_years,
        pi.zip_code,
        pi.payer_type,
        pi.preferred_language,
        CASE WHEN a.appointment_status = 'no_show' THEN 1 ELSE 0 END AS is_no_show,
        CASE WHEN a.appointment_status = 'completed' THEN 1 ELSE 0 END AS is_completed
    FROM appointments a
    LEFT JOIN patient_info pi ON a.patient_id = pi.patient_id
)

-- ─── Analysis 1: No-show rate by scheduling interval ─────────────────────────
-- KEY QUESTION: Does scheduling further in advance predict higher no-show rates?

SELECT
    scheduling_interval,
    COUNT(*)                                                AS total_scheduled,
    SUM(is_no_show)                                         AS no_shows,
    SUM(is_completed)                                       AS completed,
    SUM(same_day_cancel_flag)                               AS same_day_cancels,
    CAST(SUM(is_no_show) AS FLOAT) / NULLIF(COUNT(*), 0)   AS no_show_rate,
    AVG(CAST(lead_time_days AS FLOAT))                      AS avg_lead_time_days
FROM base
GROUP BY scheduling_interval
ORDER BY
    CASE scheduling_interval
        WHEN 'Same-Day'   THEN 1
        WHEN '1-7 Days'   THEN 2
        WHEN '8-14 Days'  THEN 3
        WHEN '15-30 Days' THEN 4
        WHEN '31-60 Days' THEN 5
        ELSE 6
    END;

/*
================================================================================
ANALYSIS 2: No-show rate by day of week
Uncomment to run.
================================================================================
*/
/*
SELECT
    day_of_week,
    day_of_week_num,
    COUNT(*)                                                AS total_scheduled,
    SUM(is_no_show)                                         AS no_shows,
    CAST(SUM(is_no_show) AS FLOAT) / NULLIF(COUNT(*), 0)   AS no_show_rate
FROM base
GROUP BY day_of_week, day_of_week_num
ORDER BY day_of_week_num;
*/

/*
================================================================================
ANALYSIS 3: No-show rate by appointment type
================================================================================
*/
/*
SELECT
    appointment_type,
    COUNT(*)                                                AS total_scheduled,
    SUM(is_no_show)                                         AS no_shows,
    CAST(SUM(is_no_show) AS FLOAT) / NULLIF(COUNT(*), 0)   AS no_show_rate
FROM base
GROUP BY appointment_type
ORDER BY no_show_rate DESC;
*/

/*
================================================================================
ANALYSIS 4: No-show rate by payer type (equity lens)
Higher no-show rates in certain payer groups may reflect transportation,
work schedule, or access barriers rather than disengagement.
================================================================================
*/
/*
SELECT
    payer_type,
    COUNT(*)                                                AS total_scheduled,
    SUM(is_no_show)                                         AS no_shows,
    CAST(SUM(is_no_show) AS FLOAT) / NULLIF(COUNT(*), 0)   AS no_show_rate
FROM base
GROUP BY payer_type
ORDER BY no_show_rate DESC;
*/

/*
================================================================================
ANALYSIS 5: High-risk patient identification (predictive targeting)
Patients with >= 2 no-shows in the past 12 months for proactive outreach.
================================================================================
*/
/*
SELECT
    patient_id,
    COUNT(*)            AS total_appointments,
    SUM(is_no_show)     AS total_no_shows,
    CAST(SUM(is_no_show) AS FLOAT)
        / NULLIF(COUNT(*),0) AS individual_no_show_rate,
    MAX(scheduled_date) AS most_recent_appt
FROM base
GROUP BY patient_id
HAVING SUM(is_no_show) >= 2
ORDER BY total_no_shows DESC, individual_no_show_rate DESC;
*/

/*
================================================================================
INTERPRETATION NOTES
--------------------
Scheduling interval and no-show rate:
  Evidence suggests a positive correlation between lead time and no-show rates
  in primary care. Appointments scheduled > 30 days out carry substantially
  higher risk. Open-access (same-day) scheduling models can reduce no-show
  rates but require careful capacity planning.

Denominator definition matters:
  This query excludes provider and clinic cancellations from the denominator.
  Some organizations include them; clarify with stakeholders before reporting
  to ensure consistency.

Same-day cancellation vs. no-show:
  Same-day cancellations are operationally similar to no-shows (slot wasted)
  but represent a qualitatively different behavior — the patient communicated.
  Track separately; interventions differ.

Equity interpretation:
  Segment by payer, language, and geography before concluding that a patient
  population is "non-compliant." Structural barriers (transportation, childcare,
  work flexibility) are the primary drivers of no-show disparities, not intent.

DIALECT NOTES
-------------
PostgreSQL: DATENAME → TO_CHAR(date, 'Day'); DATEDIFF → date subtraction (date2 - date1)
MySQL:      DATENAME → DAYNAME(); DATEDIFF(date1, date2) is reversed in MySQL
Snowflake:  DATEDIFF('day', x, y); DATENAME → DAYNAME()
BigQuery:   FORMAT_DATE('%A', date) for day name; DATE_DIFF for intervals
================================================================================
*/
