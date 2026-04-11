# Quality Improvement Analytics

SQL patterns for operational QI analysis — the layer between clinical data and actionable improvement.

## Files

| File | Description |
|---|---|
| `no-show-analysis.sql` | No-show rate by scheduling interval, day of week, appointment type, and payer. Includes patient-level risk identification. |
| `appointment-utilization.sql` *(coming soon)* | Slot utilization, open access metrics, and panel access analysis |

## Design Notes

QI analytics differ from registry queries in an important way: the denominator definition is usually the most contested part. Before running any of these queries in your environment, align with clinical and operational stakeholders on:
- What counts as a no-show vs. a same-day cancel vs. a clinic cancel
- Whether telehealth slots are included in utilization metrics
- How rescheduled appointments are attributed (original date or new date)

Document your denominator decisions. QI data loses credibility fast when two people run the "same" query and get different numbers.

---

## Disclaimer

These queries are provided for **educational and analytical reference purposes only**. They are not validated clinical decision support tools and should not be used to make individual patient care decisions without appropriate clinical review and institutional validation. HEDIS approximations do not replace official NCQA specifications for reporting purposes.

---

## License

MIT License — free to use, adapt, and share with attribution.

---

*Built by a physician who writes SQL — because the gap between clinical knowledge and data infrastructure is still too wide.*

---

*Note that I utilize AI assistance in both my writing and code generation.  Output is my own, process is augmented.*
