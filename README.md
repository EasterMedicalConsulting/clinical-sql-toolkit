# Clinical SQL Toolkit

**Generalized SQL for population health management, clinical registry development, HEDIS measure approximation, and quality improvement analytics.**

Maintained by [Peter S. Easter, DO, MBA/MHA, FAAP, FAMIA](https://www.linkedin.com/in/YOUR-LINKEDIN-URL)
Dual Board-Certified Physician · Pediatrics & Clinical Informatics · Easter Medical Consulting, LLC

---

## Purpose

This toolkit provides production-ready, well-documented SQL patterns for common clinical data problems. Every query in this repository is grounded in real clinical workflows and reflects problems encountered in practice — not hypothetical scenarios.

Queries are written in **T-SQL (SQL Server)** as the primary dialect, with adaptation notes for PostgreSQL, MySQL, Snowflake, and BigQuery where syntax differs meaningfully. All examples use generic, de-identified schema conventions with no real patient data.

---

## Repository Structure

```
clinical-sql-toolkit/
├── population-health/
│   ├── chronic-disease-registry/     # Disease-specific patient registries
│   ├── care-gap-identification/      # Patients missing recommended care
│   └── empanelment/                  # Panel management and risk stratification
├── hedis-approximations/             # HEDIS measure logic approximations
├── quality-improvement/              # QI analytics: utilization, no-shows, access
├── clinical-decision-support/        # CDS logic and alerting patterns
└── utilities/                        # Reusable date functions, templates, helpers
```

---

## Clinical Context

These queries are designed for analysts and physician informaticists working in:
- Outpatient primary care (pediatric and adult)
- Military Health System / Federal health environments
- Hospital-based population health programs
- EHR analytics layers (Cerner, Epic, and EHR-agnostic data warehouses)

All queries assume a normalized clinical data warehouse schema. Column naming follows common conventions but **will require adaptation to your organization's specific schema**.

---

## Key Principles

- **Clinically grounded:** Every query reflects a real care gap, quality measure, or operational problem — not just a technical exercise.
- **Generalized:** No vendor-specific or organization-specific logic. Parameterize and adapt.
- **Documented:** Each query includes clinical rationale, data dependencies, and interpretation guidance — not just SQL comments.
- **Honest about limitations:** HEDIS approximations are approximations. Notes indicate where claims-based vs. EHR-based logic diverges from the official HEDIS technical specifications.

---

## Getting Started

Clone the repo and start with the folder most relevant to your use case:

```bash
git clone https://github.com/EasterMedicalConsulting/clinical-sql-toolkit.git
```

Each subdirectory has its own `README.md` with context on the queries within it.

---

## Contributing

Clinical informaticists and health data analysts are welcome to open issues or pull requests. Please include:
- Clinical rationale for additions or changes
- Dialect compatibility notes
- De-identification confirmation for any example data

---

## Disclaimer

These queries are provided for **educational and analytical reference purposes only**. They are not validated clinical decision support tools and should not be used to make individual patient care decisions without appropriate clinical review and institutional validation. HEDIS approximations do not replace official NCQA specifications for reporting purposes.

---

## License

MIT License — free to use, adapt, and share with attribution.

---

*Built by a physician who writes SQL — because the gap between clinical knowledge and data infrastructure is still too wide.*

---

*Note that I utilize AI assistance in both my writing and code generation.  Output is my own, process is augmented*
