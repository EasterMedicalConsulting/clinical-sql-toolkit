/*
================================================================================
  PENICILLIN ALLERGY DOCUMENTATION & DE-LABELING IDENTIFICATION
  Author:  Peter S. Easter, DO — Easter Medical Consulting, LLC
  Version: 1.0
  Dialect: T-SQL (SQL Server) — adaptation notes included
================================================================================

CLINICAL RATIONALE
------------------
Penicillin allergy is the most commonly reported drug allergy in the US,
affecting ~10% of the population. However, studies consistently show that
>90% of patients with a penicillin allergy label are NOT truly allergic
when formally evaluated. Consequences of inaccurate penicillin allergy labeling:

  - Unnecessary use of broader-spectrum antibiotics (fluoroquinolones,
    vancomycin, clindamycin) with higher side effect profiles
  - Increased rates of C. difficile, MRSA, and antibiotic resistance
  - Higher treatment costs
  - Worse clinical outcomes in surgical prophylaxis and serious infections

Penicillin allergy de-labeling — through structured history review,
graded oral challenge, or formal skin testing — is a high-value, low-risk
intervention supported by AAAAI, AAP, ACAAI, and IDSA guidelines.

This query supports:
  1. Identifying patients with a penicillin allergy label documented
  2. Flagging documentation quality issues (reaction type missing,
     reaction severity missing, date of reaction missing)
  3. Identifying patients who are candidates for de-labeling based on
     reaction characteristics (e.g., remote, low-risk, non-IgE-mediated)
  4. Tracking de-labeling outcomes after intervention

RELATED PUBLICATION
-------------------
Abdul-Raheem J, Malek M, Klamm J, Easter PS. Standardizing Penicillin
Allergy Documentation and De-Labeling in Pediatrics: A Clinic Based
QI Intervention. San Antonio Uniformed Health Consortium Patient Safety
Week, 2025. [2nd Place]

ALLERGY CLASSIFICATION USED IN THIS QUERY
------------------------------------------
LOW RISK (de-labeling candidates):
  - Rash only (non-urticarial): maculopapular, morbilliform
  - Reaction > 10 years ago or in childhood only
  - GI symptoms only (nausea, vomiting, diarrhea)
  - Family history only (not personal reaction)
  - Unknown/vague reaction ("just listed as allergy")

HIGH RISK (formal evaluation before de-labeling):
  - Urticaria / hives
  - Angioedema
  - Anaphylaxis
  - Stevens-Johnson Syndrome / TEN
  - Drug reaction within past year

================================================================================
*/

-- ─── Parameters ──────────────────────────────────────────────────────────────
DECLARE @AsOfDate           DATE = CAST(GETDATE() AS DATE);
DECLARE @RemoteReactionYears INT = 10;   -- Reaction older than this = remote/low-risk
DECLARE @MinAge              INT = 2;    -- Minimum patient age for query
DECLARE @MaxAge              INT = 17;   -- Maximum patient age (pediatric scope)

-- ─── Step 1: Patients with any penicillin allergy label ──────────────────────
-- Penicillin class includes: amoxicillin, ampicillin, amoxicillin-clavulanate,
-- piperacillin-tazobactam, dicloxacillin, oxacillin, nafcillin

WITH pcn_allergies AS (
    SELECT
        al.patient_id,
        al.allergy_id,
        al.allergen_name,
        al.allergen_class,          -- 'penicillin', 'cephalosporin', etc.
        al.reaction_type,           -- 'rash', 'urticaria', 'anaphylaxis', 'GI', etc.
        al.reaction_severity,       -- 'mild', 'moderate', 'severe', 'unknown'
        al.reaction_date,
        al.documented_date,
        al.documentation_source,    -- 'patient_reported', 'provider_documented', 'historical'
        al.allergy_status,          -- 'active', 'inactive', 'entered_in_error'
        al.entered_by_role,         -- 'physician', 'nurse', 'patient', 'unknown'

        -- Age at reaction (if date known)
        CASE WHEN al.reaction_date IS NOT NULL
             THEN DATEDIFF(YEAR, p.date_of_birth, al.reaction_date)
             ELSE NULL END                                  AS age_at_reaction_years,

        -- Years since reaction
        CASE WHEN al.reaction_date IS NOT NULL
             THEN DATEDIFF(YEAR, al.reaction_date, @AsOfDate)
             ELSE NULL END                                  AS years_since_reaction

    FROM allergy_list al
    JOIN patients p ON al.patient_id = p.patient_id
    WHERE al.allergen_class = 'penicillin'
       OR al.allergen_name IN (
            'penicillin', 'amoxicillin', 'ampicillin',
            'amoxicillin-clavulanate', 'augmentin',
            'piperacillin-tazobactam', 'zosyn',
            'dicloxacillin', 'oxacillin', 'nafcillin'
          )
    AND al.allergy_status = 'active'
),

-- ─── Step 2: Patient demographics ────────────────────────────────────────────
patient_base AS (
    SELECT
        p.patient_id,
        p.first_name,
        p.last_name,
        p.date_of_birth,
        DATEDIFF(YEAR, p.date_of_birth, @AsOfDate)
            - CASE WHEN MONTH(p.date_of_birth) * 100 + DAY(p.date_of_birth)
                        > MONTH(@AsOfDate) * 100 + DAY(@AsOfDate)
                   THEN 1 ELSE 0 END                        AS age_years,
        p.pcp_provider_id,
        p.enrollment_status
    FROM patients p
    WHERE p.enrollment_status = 'active'
),

-- ─── Step 3: Documentation quality classification ─────────────────────────────
documentation_quality AS (
    SELECT
        pa.patient_id,
        pcn.allergy_id,
        pcn.allergen_name,
        pcn.reaction_type,
        pcn.reaction_severity,
        pcn.reaction_date,
        pcn.years_since_reaction,
        pcn.age_at_reaction_years,
        pcn.documentation_source,

        -- Documentation completeness score
        CASE WHEN pcn.reaction_type IS NULL OR pcn.reaction_type = 'unknown'
             THEN 0 ELSE 1 END
        + CASE WHEN pcn.reaction_severity IS NULL OR pcn.reaction_severity = 'unknown'
               THEN 0 ELSE 1 END
        + CASE WHEN pcn.reaction_date IS NULL
               THEN 0 ELSE 1 END                            AS documentation_score,  -- 0-3

        -- De-labeling risk classification
        CASE
            -- HIGH RISK: IgE-mediated or severe reactions
            WHEN pcn.reaction_type IN ('anaphylaxis','angioedema','urticaria','hives',
                                       'stevens-johnson','ten','serum_sickness')
            THEN 'High Risk - Formal Evaluation Required'

            -- HIGH RISK: Recent reaction
            WHEN pcn.years_since_reaction < 1
            THEN 'High Risk - Recent Reaction'

            -- LOW RISK: Non-IgE-mediated, remote reactions
            WHEN pcn.reaction_type IN ('maculopapular_rash','morbilliform_rash',
                                       'GI','nausea','vomiting','diarrhea')
                 AND pcn.years_since_reaction >= @RemoteReactionYears
            THEN 'Low Risk - De-labeling Candidate'

            -- LOW RISK: Vague/unknown documentation
            WHEN (pcn.reaction_type IS NULL OR pcn.reaction_type IN ('unknown','unspecified'))
                 AND pcn.years_since_reaction >= @RemoteReactionYears
            THEN 'Low Risk - Vague Documentation, De-labeling Candidate'

            -- LOW RISK: Documented in childhood (may be viral exanthem)
            WHEN pcn.age_at_reaction_years IS NOT NULL
                 AND pcn.age_at_reaction_years < 5
                 AND pcn.reaction_type NOT IN ('anaphylaxis','angioedema','urticaria')
            THEN 'Low Risk - Childhood Reaction (possible viral exanthem)'

            -- INDETERMINATE
            ELSE 'Indeterminate - Clinical Review Needed'
        END AS delabeling_risk_category,

        -- De-labeling candidate flag
        CASE
            WHEN pcn.reaction_type IN ('anaphylaxis','angioedema','urticaria','hives',
                                       'stevens-johnson','ten','serum_sickness')
            THEN 0
            WHEN pcn.years_since_reaction < 1 THEN 0
            ELSE 1
        END AS delabeling_candidate_flag

    FROM patient_base pa
    JOIN pcn_allergies pcn ON pa.patient_id = pcn.patient_id
    WHERE pa.age_years BETWEEN @MinAge AND @MaxAge
)

-- ─── Final Output ─────────────────────────────────────────────────────────────
SELECT
    pb.patient_id,
    pb.last_name,
    pb.first_name,
    pb.date_of_birth,
    pb.age_years,
    pb.pcp_provider_id,

    dq.allergen_name,
    dq.reaction_type,
    dq.reaction_severity,
    dq.reaction_date,
    dq.years_since_reaction,
    dq.age_at_reaction_years,
    dq.documentation_source,

    -- Quality and classification
    dq.documentation_score,
    CASE dq.documentation_score
        WHEN 3 THEN 'Complete'
        WHEN 2 THEN 'Partially Documented'
        WHEN 1 THEN 'Minimally Documented'
        WHEN 0 THEN 'Undocumented'
    END AS documentation_quality,

    dq.delabeling_risk_category,
    dq.delabeling_candidate_flag,

    -- Action flags
    CASE WHEN dq.documentation_score < 2 THEN 1 ELSE 0 END
        AS flag_documentation_improvement_needed,
    dq.delabeling_candidate_flag
        AS flag_delabeling_candidate

FROM patient_base pb
JOIN documentation_quality dq ON pb.patient_id = dq.patient_id
ORDER BY
    dq.delabeling_candidate_flag DESC,
    dq.documentation_score ASC,
    pb.pcp_provider_id,
    pb.last_name;

/*
================================================================================
AGGREGATION: QI Dashboard Summary
================================================================================
*/
/*
SELECT
    delabeling_risk_category,
    COUNT(*)                                        AS patient_count,
    AVG(CAST(documentation_score AS FLOAT))         AS avg_documentation_score,
    SUM(flag_documentation_improvement_needed)      AS needs_documentation_improvement,
    SUM(delabeling_candidate_flag)                  AS delabeling_candidates
FROM documentation_quality
GROUP BY delabeling_risk_category
ORDER BY patient_count DESC;
*/

/*
================================================================================
INTERPRETATION NOTES
--------------------
Cross-reactivity with cephalosporins:
  The historical 10% cross-reactivity figure between penicillin and
  cephalosporins is not supported by current evidence. True cross-reactivity
  is <2% and is driven by shared R1 side chains, not the beta-lactam ring.
  This query focuses on penicillin specifically; a companion query for
  cephalosporin allergy documentation is recommended.

De-labeling pathways:
  - Low-risk patients: Graded oral amoxicillin challenge (outpatient)
  - Indeterminate: Penicillin skin testing followed by graded challenge
  - High-risk: Allergist referral for formal evaluation
  AAAAI/ACAAI 2022 practice parameters are the recommended reference.

Documentation source reliability:
  Patient-reported allergies have lower specificity for true allergy than
  provider-documented reactions. Consider weighting documentation_source
  in risk classification if your EHR captures this reliably.

DIALECT NOTES
-------------
Same as prior queries. No dialect-specific functions beyond standard date math.
================================================================================
*/
