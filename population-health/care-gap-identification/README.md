# Care Gap Identification

Care gap queries identify patients who are eligible for a specific preventive service or quality measure but have not yet received it. They are the workhorse of population health outreach.

## Files

| File | Measure | Guideline Source |
|---|---|---|
| `lead-anemia-screening-gaps.sql` | Blood lead & hemoglobin screening at 12 and 24 months | AAP, CDC, Medicaid EPSDT |
| `well-child-care-gaps.sql` *(coming soon)* | Well-child visit completion by age group | AAP Bright Futures |
| `immunization-gaps.sql` *(coming soon)* | Childhood immunization series completion | ACIP, HEDIS CIS-E |

## Key Concepts

**Eligible population (denominator):** Patients who *should* have received the service based on age, enrollment, and visit history.

**Gap (numerator complement):** Patients in the denominator who do NOT have a documented result.

**Outreach priority:** Sort by gap count, risk level, and time since last contact. Do not outreach every patient simultaneously — prioritize highest risk first.

## Related Publication

Walton C, Law C, Easter PS. Improving Lead and Anemia Screening Rates within Wilford Hall Pediatric Clinic. *San Antonio Uniformed Health Consortium Patient Safety Week*, 2026.

## Disclaimer

These queries are provided for **educational and analytical reference purposes only**. They are not validated clinical decision support tools and should not be used to make individual patient care decisions without appropriate clinical review and institutional validation. HEDIS approximations do not replace official NCQA specifications for reporting purposes.

---

## License

MIT License — free to use, adapt, and share with attribution.

---

*Built by a physician who writes SQL — because the gap between clinical knowledge and data infrastructure is still too wide.*

---

*Note that I utilize AI assistance in both my writing and code generation.  Output is my own, process is augmented.*
