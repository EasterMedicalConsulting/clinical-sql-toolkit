# Chronic Disease Registries

Patient registries are the foundation of population health management. These queries identify and characterize patients with specific chronic conditions, enabling proactive outreach, care gap closure, and panel-level quality monitoring.

## Files

| File | Condition | Focus |
|---|---|---|
| `pediatric-asthma-registry.sql` | Asthma (pediatric) | Diagnosis identification, severity classification, medication adherence |
| `diabetes-registry.sql` | Type 1 & 2 Diabetes | Glycemic control, complication screening, medication management |
| `hypertension-registry.sql` | Hypertension | BP control, medication classes, comorbidity burden |

## Schema Assumptions

All queries assume a standard clinical data warehouse with the following tables:
- `patients` — demographics, PCP assignment, enrollment status
- `encounters` — visit history with dates, types, and providers
- `diagnoses` — ICD-10 codes linked to encounters
- `medications` — active and historical medication records
- `lab_results` — structured lab values with LOINC codes
- `vitals` — height, weight, BP, BMI linked to encounters

Adapt table and column names to match your environment.
