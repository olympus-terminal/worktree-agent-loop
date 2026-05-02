[
  {
    "id": 1,
    "category": "analysis",
    "priority": 1,
    "passes": false,
    "reviewer_concern": "R1#2 (missing sensitivity analysis)",
    "description": "Run sensitivity analysis on threshold parameter. Script: scripts/sensitivity_TIMESTAMP.py. Output: source_data/sensitivity.tsv. Edit main.tex with results. Commit: 'Add threshold sensitivity analysis'."
  },
  {
    "id": 2,
    "category": "analysis",
    "priority": 2,
    "passes": false,
    "reviewer_concern": "R2#1 (statistical test)",
    "description": "Compute bootstrap CI on the headline statistic. Script: scripts/bootstrap_ci_TIMESTAMP.py. Output: source_data/bootstrap_ci.md. Edit main.tex Results section. Commit: 'Add bootstrap CI to headline statistic'."
  },
  {
    "id": 3,
    "category": "writing",
    "priority": 3,
    "passes": false,
    "reviewer_concern": "R3#1 (Discussion framing)",
    "description": "Reframe Discussion paragraph to address reviewer concern about alternative interpretations. Use numbers from source_data/. Commit: 'Reframe Discussion: address alternative interpretations'."
  }
]
