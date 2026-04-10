# Clinical Decision Support (CDS) Logic

SQL patterns for identifying CDS opportunities — patients where a structured intervention, alert, or provider nudge is warranted based on existing clinical data.

## Files

| File | Clinical Problem | Intervention |
|---|---|---|
| `penicillin-allergy-documentation.sql` | Penicillin allergy over-labeling | Documentation quality improvement + de-labeling candidate identification |
| `naloxone-coprescription.sql` *(coming soon)* | Opioid prescribing without naloxone coprescription | Alert logic for pharmacy CDS |

## Design Philosophy

Effective CDS is specific, actionable, and rare enough to be noticed. Most CDS failures are failures of alert fatigue — too many alerts, too little specificity. These queries are designed to:

1. Surface only patients where an action is genuinely warranted
2. Provide enough clinical context in the output to make the action obvious
3. Support both real-time (point-of-care) and asynchronous (population-level) delivery

## Related Publication

Abdul-Raheem J, Malek M, Klamm J, Easter PS. Standardizing Penicillin Allergy Documentation and De-Labeling in Pediatrics: A Clinic Based QI Intervention. *San Antonio Uniformed Health Consortium Patient Safety Week*, 2025. [2nd Place]

Rittel AG, Highland KB, Maneval MS, Bockhorst AD, Moreno A, Sim A, Easter PS, et al. Development, implementation, and evaluation of a clinical decision support tool to improve naloxone coprescription within Military Health System pharmacies. *American Journal of Health-System Pharmacy.* 2022;79(1):e58-e64.
