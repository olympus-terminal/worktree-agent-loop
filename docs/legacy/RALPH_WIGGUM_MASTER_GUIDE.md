# Ralph Wiggum Master Guide: TARA-Oceans Marine Metagenome Manuscript

## Overview

This guide enables an autonomous agent to execute Ralph Wiggum loops for preparing the **master TARA-Oceans manuscript** - a comprehensive analysis linking marine metagenome protein domains to environmental conditions via satellite embeddings.

**Scope:** Full global dataset (TARA Oceans, OSD, Malaspina, GOS, MMETSP) - approximately twice the data of the AlphaEarth coastal analysis.

**Relationship to AlphaEarth:** The `/media/drn/External1/TARA-Oceans/AlphaEarth/manuscript/` contains a "story within a story" focusing on coastal microalgae (~1,090 genomes). This master manuscript covers the complete pipeline and full dataset. The two manuscripts will eventually merge.

---

## Project Architecture

### Directory Structure
```
/media/drn/External1/TARA-Oceans/
├── 01_raw_data/                    # Downloaded sequences and metadata
│   ├── tara_metagenomes/           # TARA Oceans metagenome assemblies
│   ├── tara_mags/                  # TARA MAGs (Metagenome-Assembled Genomes)
│   ├── tara_polar/                 # TARA Polar expedition data
│   ├── osd/                        # Ocean Sampling Day (2014)
│   ├── malaspina/                  # Malaspina circumnavigation
│   ├── gos/                        # Global Ocean Sampling expedition
│   ├── transcriptomes/             # MMETSP transcriptomes
│   ├── gene_catalogs/              # OM-RGC v2
│   ├── environmental_data/         # PANGAEA oceanographic data
│   └── metadata/                   # Consolidated metadata files
├── 02_processed_data/              # Pipeline outputs
│   └── proteins/                   # Extracted protein sequences
├── 03_analyses/                    # Analysis results
├── 04_models/                      # ML model checkpoints
├── 05_results/                     # Final outputs
├── tools/
│   └── la4sr/                      # Microalgal sequence classifier
├── algal_sequence_unification/     # Reference database consolidation
├── AlphaEarth/                     # Coastal analysis (sub-manuscript)
│   └── manuscript/                 # AlphaEarth Ralph Wiggum setup
├── GoogleEarthEngine/              # GEE embedding extraction
└── MANUSCRIPT/                     # Master manuscript (to be created)
```

### Dual-Environment Operation

**LOCAL** (`/media/drn/External1/TARA-Oceans/`):
- Script development and testing
- Single-file validation
- Result analysis and figure generation
- Manuscript writing

**HPC** (`/scratch/drn2/PROJECTS/TARA-LA4SR/`):
- Batch processing (SLURM arrays)
- GPU inference (la4sr classification)
- PFAM hmmsearch on full datasets
- Large-scale correlation analysis

**Synchronization:**
```bash
# Local → HPC
rsync -Pvrt /media/drn/External1/TARA-Oceans/ hpc:/scratch/drn2/PROJECTS/TARA-LA4SR/

# HPC → Local
rsync -Pvrt hpc:/scratch/drn2/PROJECTS/TARA-LA4SR/ /media/drn/External1/TARA-Oceans/
```

**CRITICAL:** Never create filelists with local paths for batch processing. Generate filelists on-demand per environment.

---

## Data Sources Summary

| Dataset | Samples | Status | Key Files |
|---------|---------|--------|-----------|
| TARA Oceans | ~2,000+ | Complete | `tara_metagenomes/`, GPS mapping complete |
| TARA Polar | ~200+ | In progress | `tara_polar/`, tracking file exists |
| OSD 2014 | ~150+ | Complete | `osd_complete_metadata.tsv` |
| Malaspina | ~300+ | Complete | `malaspina_complete_metadata.tsv` |
| GOS | ~80+ | Complete | `gos_complete_metadata.tsv` |
| MMETSP | ~700+ | Complete | `samn_mmetsp_complete_20260113.tsv` |

---

## Phase-Based Manuscript Development

The manuscript follows a 7-phase analysis pipeline. Each phase has specific tasks that can be tracked via Ralph Wiggum loops.

### Phase 1: Data Acquisition & Collation

**Goal:** Consolidate all raw data with GPS coordinates and metadata.

**Input Requirements:**
- Protein FASTA files from each dataset
- GPS coordinates (decimal degrees)
- Environmental metadata (temperature, salinity, depth)
- Taxonomic information

**Key Files:**
```
01_raw_data/metadata/
├── ALL_assemblies_GPS_mapping.tsv      # Master GPS linkage
├── gos_complete_metadata.tsv           # GOS metadata
├── malaspina_complete_metadata.tsv     # Malaspina metadata
├── osd_complete_metadata.tsv           # OSD metadata
├── ers_to_samea_mapping_COMPLETE.tsv   # ENA ID conversions
└── data_inventory_20251223.txt         # Complete inventory
```

**Tasks:**
1. Verify all datasets downloaded
2. Validate GPS coordinates for all samples
3. Consolidate metadata into unified format
4. Document any missing data or exclusions

### Phase 2: Microalgal Sequence Extraction (la4sr)

**Goal:** Classify protein sequences to extract microalgal proteins from mixed metagenomes.

**Tool:** la4sr (Large-scale Algal Sequence Recognition)
- Singularity container: `tools/la4sr/la4sr_sp2.sif`
- Model checkpoint: `tools/la4sr/Pythia70m-b-checkpoint-55000/`

**Workflow (HPC):**
```bash
# Generate filelist on HPC
find ./02_processed_data/proteins -name "*.fa" > filelist.txt

# Run la4sr inference (SLURM job)
sbatch stage2_inference_gpu_FIXED_20260102_130000.sbatch
```

**Output:** Classification TSV with algal/bacterial/viral/fungal predictions per sequence

**Key Scripts:**
- `infer_algagpt_masked_fixed_20260107_150000.py` - Production inference
- `stage2_inference_GODMODE_*.sbatch` - High-throughput batch jobs

### Phase 3: PFAM Domain Annotation

**Goal:** Annotate extracted algal proteins with PFAM domains.

**Method:** hmmsearch against Pfam-A database

**Workflow (HPC):**
```bash
# PFAM search job
sbatch hmmsearch_pfam_20260106_130000.sbatch
```

**Output Format:** seqtblout files with domain hits per protein

**Key Files:**
- `hmmsearch_pfam_20260106_130000.sbatch` - Main search job
- `hmmsearch_missing_mgya_20260113_134018.sbatch` - Recovery job

### Phase 4: AlphaEarth Embedding Extraction

**Goal:** Extract 64-dimensional environmental embeddings from Google Earth Engine for each GPS coordinate.

**Prerequisites:**
- Google Earth Engine account and authentication
- Python `earthengine-api` package

**Reference Script:** `extract_alphaearth_embeddings_20251019.py` (in AlphaEarth/)

**Core API Call:**
```python
import ee
ee.Initialize()
collection = ee.ImageCollection("GOOGLE/SATELLITE_EMBEDDING/V1/ANNUAL")
mosaic = collection.mosaic()
# Extract at GPS coordinates
```

**Output:** 64 dimensions (A00-A63) per sample

### Phase 5: Correlation Analysis

**Goal:** Correlate PFAM domain abundances with environmental embeddings.

**Method:**
- Spearman rank correlation (robust to outliers)
- FDR correction (Benjamini-Hochberg) for multiple testing
- ~640,000-960,000 tests (10,000+ PFAMs × 64 dimensions)

**Reference Script:** `analyze_alphaearth_pfam_correlations_20251017.py`

**Expected Results:**
- Total tests: N_pfams × 64
- Significant (FDR < 0.05): Typically 0.5-5% of tests
- Hub dimensions and hub PFAMs identified

### Phase 6: Machine Learning Validation

**Goal:** Validate PFAM-environment associations with XGBoost/SHAP.

**Targets:**
- Regression: Temperature, latitude, embedding dimensions
- Classification: Environment type, climatic zone, phylum

**Reference Scripts:**
- `02_pfams_to_metadata_xgboost_*.py`
- `03_shap_interpretation_*.py`

### Phase 7: Manuscript Preparation

**Goal:** Write publication-ready manuscript with figures.

**Format:** Cell Press style (LaTeX with tectonic)

**Structure:**
1. Title page with highlights
2. Abstract (150 words) + eTOC blurb (40 words)
3. Introduction
4. Results (4-5 subsections)
5. Discussion + Limitations
6. STAR Methods
7. References
8. Figures (main + supplementary)

---

## Ralph Wiggum Setup for Master Manuscript

### Directory to Create
```
/media/drn/External1/TARA-Oceans/MANUSCRIPT/
├── main.tex                    # Master LaTeX document
├── *.tex                       # Section files
├── references.bib              # Bibliography
├── main_figs/                  # Main figures
├── supplement/                 # Supplementary materials
├── source_data/                # Statistics source files
├── PRD.md                      # Requirements document
├── plan.md                     # Task list (JSON format)
├── activity.md                 # Progress log
├── PROMPT.md                   # Agent prompt
├── ralph.sh                    # Loop script
└── CLAUDE.md                   # Data integrity rules
```

### Task Categories for plan.md

```json
[
  {"category": "data", "description": "Document data acquisition status"},
  {"category": "data", "description": "Verify GPS coordinate coverage"},
  {"category": "methods", "description": "Write la4sr classification methods"},
  {"category": "methods", "description": "Write PFAM annotation methods"},
  {"category": "methods", "description": "Write AlphaEarth embedding methods"},
  {"category": "methods", "description": "Write correlation analysis methods"},
  {"category": "methods", "description": "Write XGBoost/SHAP methods"},
  {"category": "results", "description": "Write dataset overview with exact counts"},
  {"category": "results", "description": "Write la4sr classification results"},
  {"category": "results", "description": "Write correlation analysis results"},
  {"category": "results", "description": "Write hub analysis results"},
  {"category": "results", "description": "Write ML validation results"},
  {"category": "figure", "description": "Create study overview figure"},
  {"category": "figure", "description": "Create geographic distribution map"},
  {"category": "figure", "description": "Create biclustered heatmap"},
  {"category": "figure", "description": "Create SHAP importance figure"},
  {"category": "content", "description": "Write introduction"},
  {"category": "content", "description": "Write discussion"},
  {"category": "content", "description": "Write abstract"},
  {"category": "quality", "description": "Final compilation check"}
]
```

---

## CRITICAL POLICIES

### Data Integrity (MANDATORY)

**From CLAUDE.md - these rules are NON-NEGOTIABLE:**

1. **NEVER fabricate data**
   - No `np.random`, `torch.rand` for scientific results
   - No placeholder statistics
   - No hardcoded "demonstration" values

2. **All statistics must trace to source files**
   - Read actual data files
   - Copy exact numbers
   - Document provenance

3. **If data unavailable: STOP and request it**
   - Do not substitute synthetic data
   - Do not round or estimate

### Source Data Files

Statistics for the manuscript must come from:
```
/media/drn/External1/TARA-Oceans/01_raw_data/metadata/
├── data_inventory_20251223.txt
├── ALL_assemblies_GPS_mapping.tsv
├── *_complete_metadata.tsv files

/media/drn/External1/TARA-Oceans/AlphaEarth/
├── alphaearth_pfam_correlations_*_summary.txt
├── alphaearth_xgboost_*_model_performance.tsv
├── alphaearth_xgboost_*_feature_importance.tsv
```

### Figure Protocol (MANDATORY)

**From FIGURE_PROTOCOL.md:**

- **Font:** 6pt Arial ONLY - no exceptions
- **Line weight:** 0.25pt
- **Format:** PDF + SVG only (NO PNG)
- **Background:** Transparent (never white)
- **Colors:** Custom colormaps (no matplotlib defaults)
- **Text:** NO overlapping - #1 rejection reason
- **Validation:** Zoom 400%, Illustrator test, grayscale test

---

## Environment Detection in Scripts

Always include environment detection:

```python
import os

def get_base_dir():
    cwd = os.getcwd()
    if '/scratch/' in cwd:
        return '/scratch/drn2/PROJECTS/TARA-LA4SR'
    elif '/media/' in cwd:
        return '/media/drn/External1/TARA-Oceans'
    else:
        raise ValueError(f"Unknown environment: {cwd}")
```

```bash
if [[ $(pwd) == /scratch/* ]]; then
    BASE_DIR="/scratch/drn2/PROJECTS/TARA-LA4SR"
elif [[ $(pwd) == /media/* ]]; then
    BASE_DIR="/media/drn/External1/TARA-Oceans"
else
    echo "ERROR: Unknown environment"
    exit 1
fi
```

---

## Ralph Loop Execution

### PROMPT.md Template

```markdown
@plan.md @activity.md @PRD.md

We are writing a scientific manuscript for the TARA-Oceans marine metagenome analysis.

**CRITICAL DATA INTEGRITY POLICY:**
- ALL statistics MUST come from actual data files
- NEVER fabricate, estimate, or "round" scientific values
- If you cannot read a required file, STOP and report the error

First read activity.md to understand current state.
Open plan.md and choose the single highest priority task with `"passes": false`.

Work on exactly ONE task:
1. Read required source files
2. Extract real values
3. Write/edit the LaTeX section
4. Compile with tectonic
5. Verify compilation succeeds

After completing:
1. Append dated progress entry to activity.md
2. Update task's `"passes"` to `true`
3. Make one git commit

ONLY WORK ON A SINGLE TASK PER ITERATION.

When ALL tasks pass, output: <promise>COMPLETE</promise>
```

### ralph.sh Template

```bash
#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations>"
  exit 1
fi

MAX_ITERATIONS=$1
MANUSCRIPT_DIR="/media/drn/External1/TARA-Oceans/MANUSCRIPT"
cd "$MANUSCRIPT_DIR"

for ((i=1; i<=$MAX_ITERATIONS; i++)); do
  echo "========================================"
  echo "Iteration $i of $MAX_ITERATIONS"
  echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "========================================"

  result=$(claude --model claude-opus-4-5-20251101 --dangerously-skip-permissions -p "$(cat PROMPT.md)" \
    --output-format text \
    --permission-mode acceptEdits \
    --allowedTools "Read,Edit,Write,Bash(tectonic:*),Bash(git add:*),Bash(git commit:*),Bash(git status),Bash(ls:*),Glob,Grep" \
    2>&1) || true

  echo "$result"

  if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
    echo "SUCCESS: All tasks complete after $i iterations."
    exit 0
  fi

  echo "--- End of iteration $i ---"
  sleep 2
done

echo "WARNING: Reached max iterations ($MAX_ITERATIONS)"
exit 1
```

---

## Merging with AlphaEarth Manuscript

The AlphaEarth coastal analysis (`/media/drn/External1/TARA-Oceans/AlphaEarth/manuscript/`) is a subset analysis. When merging:

1. **AlphaEarth becomes a Results subsection** or Supplementary Analysis
2. **Share methodology** - reference same STAR Methods
3. **Cross-reference figures** - AlphaEarth heatmap may become Figure S1
4. **Consistent statistics** - both use same FDR thresholds, same methods

**AlphaEarth manuscript location:**
```
/media/drn/External1/TARA-Oceans/AlphaEarth/manuscript/
├── main.tex, *.tex files
├── plan.md (12 tasks, 2 complete as of 2026-01-14)
├── ralph.sh (tested and working)
└── source_data/ (statistics files)
```

---

## Key Reference Documents

| Document | Location | Purpose |
|----------|----------|---------|
| CLAUDE.md | `/media/drn/External1/TARA-Oceans/CLAUDE.md` | Data integrity rules |
| FIGURE_PROTOCOL.md | `AlphaEarth/FIGURE_PROTOCOL.md` | Figure standards |
| METHODS_FOR_AlphaEarth_Genomics | `AlphaEarth/METHODS_*.md` | Analysis pipeline details |
| Data Inventory | `01_raw_data/metadata/data_inventory_20251223.txt` | Dataset summary |

---

## Execution Checklist

Before running Ralph loops:

- [ ] Verify source data files exist and are readable
- [ ] Create MANUSCRIPT/ directory structure
- [ ] Copy essential documentation (CLAUDE.md, FIGURE_PROTOCOL.md)
- [ ] Set up LaTeX template with tectonic
- [ ] Initialize git repository
- [ ] Create PRD.md, plan.md, activity.md, PROMPT.md
- [ ] Create and chmod +x ralph.sh
- [ ] Test single iteration before full run

**Run command:**
```bash
cd /media/drn/External1/TARA-Oceans/MANUSCRIPT
./ralph.sh 25  # Adjust iterations as needed
```

---

## Contact & Provenance

**Guide Created:** 2026-01-14
**Project Location:** `/media/drn/External1/TARA-Oceans/`
**HPC Location:** `/scratch/drn2/PROJECTS/TARA-LA4SR/`

---

*This guide enables autonomous manuscript preparation while maintaining strict data integrity. Every statistic in the final manuscript must trace back to actual analysis outputs.*
