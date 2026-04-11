# Food Inspections Assignment — DAMG7370

**Designing Advanced Data Architectures for Business Intelligence**
**Northeastern University — Spring 2026**
**Author:** Michael Dereje (dereje.m@northeastern.edu)

---

## Project Overview

End-to-end data engineering and BI project analyzing food establishment inspection data from **Chicago** and **Dallas**. The project follows the **Medallion Architecture** (Bronze → Silver → Gold) using Databricks, with dimensional modeling, SCD Type 2 implementation via Delta Live Tables, and Power BI dashboards.

### Key Metrics
| Dataset | Bronze Rows | Silver Rows | Gold Fact Rows |
|---------|------------|-------------|----------------|
| Chicago | 308,161 | 1,025,507 | ~1M |
| Dallas | 78,984 | 306,446 | ~300K |
| **Combined** | **387,145** | **1,331,953** | **1,331,953** |

---

## Repository Structure

```
DAMG-7370-FP/
├── setup/                          # Bronze layer — data ingestion
│   ├── 01_create_volume.py         # Create Unity Catalog volume
│   └── 02_bronze_ingestion.py      # Read CSVs, clean column names, write Bronze Delta tables
│
├── profiling/                      # Part 1 — Data profiling with DQX
│   ├── 01_manual_profiling.py      # Null analysis, value distributions, violations structure
│   ├── 02_dqx_profiling.py         # DQX Profiler on both Bronze tables
│   └── 03_violations_analysis.py   # Chicago parsing + Dallas unpivot + validation checks
│
├── queries/                        # Silver & Gold layer — ETL pipeline
│   ├── 01_silver_chicago.py        # Chicago Silver: validate, parse violations, derive scores
│   ├── 02_silver_dallas.py         # Dallas Silver: validate, unpivot violations, apply Rules 8 & 9
│   └── 03_gold_layer.py            # Load all dim_ and fact_ tables from Silver
│
├── pipeline/                       # DLT pipeline — SCD Type 2
│   └── 04_dlt_violations.py        # Delta Live Tables SCD2 on dim_violation
│
├── Food_Inspections_Chicago_Dallas.pdf          # Assignment instructions
├── food_inspections_profiling_report.docx        # Part 1: Data profiling report
├── Food_Inspections_Source_to_Target_Mapping.xlsx # Part 2: Source-to-target mapping document
├── Mapping_Template.xlsx                         # Original mapping template
├── food_inspections_dimensional_model.sql        # Part 2: DDL for ER Studio / Navicat import
├── dimensional_model.nmodel                      # Part 2: Navicat model file
├── dimensional_model.png                         # Part 2: ER diagram screenshot
├── dimensional_model.pdf                         # Part 2: ER diagram PDF export
├── inspections_for_chicago_and_dallas_mdereje.pbix # Part 4: Power BI report
├── databricks-Serverless Starter Warehouse.pbids   # Power BI Databricks connection
├── notes.md                                      # Project notes
└── README.md                                     # This file
```

---

## Prerequisites

- **Databricks Workspace** with Unity Catalog enabled
- **Python/PySpark** runtime on Databricks cluster
- **DQX Profiler**: `%pip install databricks-labs-dqx`
- **Delta Live Tables** access for SCD2 pipeline
- **Power BI Desktop** or Power BI Service for dashboards
- **Navicat** or **ER Studio** for dimensional model diagram (optional)

---

## Setup Instructions

### 1. Data Ingestion (Bronze Layer)

#### a. Create the Volume
```python
spark.sql("CREATE VOLUME IF NOT EXISTS workspace.default.food_inspections")
```

#### b. Upload Source Data
1. Download CSV files from the assignment links (Chicago and Dallas)
2. In Databricks: **Catalog → workspace → default → Volumes → food_inspections**
3. Click **Upload to this volume** and upload both CSV files:
   - `chicago_inspection_dataset.csv`
   - `dallas_inspection_dataset.csv`

#### c. Run Bronze Ingestion
Run `setup/02_bronze_ingestion.py` — this reads both CSVs, cleans column names (removes spaces/special characters for Delta compatibility), and writes Bronze Delta tables:
- `workspace.default.bronze_chicago_inspections` (308,161 rows, 17 columns)
- `workspace.default.bronze_dallas_inspections` (78,984 rows, 114 columns)

### 2. Data Profiling (Part 1)

Run notebooks in `profiling/` folder in order:
1. `01_manual_profiling.py` — Null analysis, value distributions, schema comparison
2. `02_dqx_profiling.py` — DQX Profiler with `display()` output for screenshots
3. `03_violations_analysis.py` — Violations structure analysis for both cities

**Output:** `food_inspections_profiling_report.docx` (pre-generated, add screenshots to Appendix)

### 3. Silver Layer (Cleansed Data)

Run notebooks in `queries/` folder:

#### a. Chicago Silver (`01_silver_chicago.py`)
- Validates: null DBA name, inspection date, type, zip, results
- Derives inspection score from results (Pass=90, Conditions=80, Fail=70, No Entry=0)
- Parses pipe-delimited violations into individual rows (violation_code, description, comments)
- Deduplicates violations per inspection
- Includes inspections with no violations (NULL violation fields)
- **Output:** `workspace.default.silver_chicago_inspections` (1,025,507 rows)

#### b. Dallas Silver (`02_silver_dallas.py`)
- Validates: null restaurant name, negative scores, scores > 100, zip format
- Truncates ZIP+4 codes to 5 digits
- Unpivots 25 violation column groups into rows using `stack()`
- Applies Rule 8: drops inspections with score ≥ 90 and > 3 violations
- Applies Rule 9: drops inspections with score ≥ 90 containing Urgent/Critical violations
- Parses lat/long from combined field, generates synthetic inspection IDs
- **Output:** `workspace.default.silver_dallas_inspections` (306,446 rows)

### 4. Gold Layer (Dimensional Model — Part 3)

Run `queries/03_gold_layer.py` — loads all dimension and fact tables:

| Table | Type | Rows | Description |
|-------|------|------|-------------|
| `dim_date` | Dimension | ~4,549 | Standard calendar dimension with fiscal year |
| `dim_establishment` | Dimension | ~58,244 | Business/restaurant info (SCD Type 1) |
| `dim_location` | Dimension | ~27,901 | Geographic info with lat/long |
| `dim_violation` | Dimension | ~950 | Violation codes from both cities |
| `dim_inspection_type` | Dimension | ~113 | Inspection type lookup with categories |
| `dim_inspection_result` | Dimension | 7 | Result/score mapping |
| `fact_inspection_violation` | Fact | ~1,331,953 | Grain: one row per violation per inspection |

### 5. SCD Type 2 — DLT Pipeline (Part 3)

#### a. Create the Pipeline
1. Go to **Pipelines → Create Pipeline**
2. Configure:
   - **Pipeline name:** `food_inspections_scd2`
   - **Pipeline mode:** Triggered
   - **Source code:** Select `pipeline/04_dlt_violations.py`
   - **Catalog:** `workspace`
   - **Target schema:** `default`
3. Click **Create**, then **Start**

#### b. Verify
```python
scd2 = spark.table("workspace.default.dim_violation_scd2")
print(f"Total: {scd2.count()}")
print(f"Current: {scd2.where(col('__END_AT').isNull()).count()}")
print(f"Historical: {scd2.where(col('__END_AT').isNotNull()).count()}")
```

**Output:** `workspace.default.dim_violation_scd2` (116 rows, all current on initial load)

DLT manages SCD2 columns automatically:
- `__START_AT` — when this version became effective
- `__END_AT` — when this version was superseded (NULL if current)

### 6. Power BI Dashboards (Part 4)

#### a. Connect to Databricks
1. Open Power BI → **Get Data → Databricks**
2. Enter **Server Hostname** and **HTTP Path** from your SQL Warehouse connection details
3. Authenticate with a **Personal Access Token**
4. Load all 7 Gold layer tables

#### b. Dashboard Pages

**Page 1 — Inspection Overview**
- KPI cards: Total Inspections (361K), Avg Score (80.41), Pass Rate (71%), Total Violations (1M)
- City slicer (Chicago / Dallas)
- Inspections by Result (bar chart)
- Inspections Over Time (line chart, split by city)

**Page 2 — Violations Analysis**
- Top 10 Violations (horizontal bar chart)
- Violations by Severity (donut: 70% Minor, 20% Critical, 10% Serious)
- Top Businesses by Violations (table with Subway, Dunkin Donuts, McDonald's)

**Page 3 — Inspection Report**
- City, Restaurant Name (searchable), Year slicers
- Location map (lat/long bubbles)
- Risk Level donut
- Detailed inspection table (ID, date, business, result, score, violations)

#### c. DAX Measures
```dax
Total Inspections = DISTINCTCOUNT(fact_inspection_violation[inspection_id])
Total Violations = COUNTROWS(FILTER(fact_inspection_violation, NOT(ISBLANK(fact_inspection_violation[violation_key]))))
Avg Inspection Score = AVERAGE(fact_inspection_violation[inspection_score])
Pass Rate = DIVIDE(
    CALCULATE(DISTINCTCOUNT(fact_inspection_violation[inspection_id]), dim_inspection_result[result_category] = "Pass"),
    DISTINCTCOUNT(fact_inspection_violation[inspection_id])
)
Violations Per Inspection = DIVIDE([Total Violations], [Total Inspections])
```

---

## Dimensional Model

**Star Schema** with grain: one row per violation per inspection.

```
                    dim_date
                       |
  dim_inspection_type--+-----------dim_establishment
                       |
              fact_inspection_violation
                       |
  dim_inspection_result-+-----------dim_location
                       |
                  dim_violation
                   (SCD Type 2)
```

- **Fact table:** `fact_inspection_violation` — FKs to all 6 dimensions, measures (inspection_score, violation_points), degenerate dimensions (source_city, inspection_id, violation_slot)
- **SCD Type 2:** `dim_violation` — tracks changes to violation descriptions over time via DLT
- **Score derivation:** Chicago scores derived from results text; Dallas scores come directly from data

---

## Silver Layer Validation Rules

| # | Rule | Applies To | Action |
|---|------|-----------|--------|
| 1 | Restaurant/DBA Name not null | Both | Drop |
| 2 | Inspection Date not null | Both | Drop |
| 3 | Inspection Type not null | Both | Drop |
| 4 | Zip code valid 5-digit format | Both | Drop / Truncate |
| 5 | Dallas score ≤ 100 | Dallas | Drop |
| 6 | Chicago results not null | Chicago | Drop |
| 7 | Deduplicate violations per inspection | Both | Deduplicate |
| 8 | Score ≥ 90 cannot have > 3 violations | Dallas | Drop |
| 9 | No PASS if violation contains Urgent/Critical | Dallas | Drop |
| 10 | Derive Chicago scores from results | Chicago | Transform |
| 11 | Negative scores invalid | Dallas | Drop |
| 12 | Standardize violation codes between datasets | Both | Transform |

---

## Key Technical Decisions

- **Column name cleaning:** Delta Lake requires no spaces/special chars — `clean_column_names()` regex converts to `lowercase_underscore` format
- **Chicago violations parsing:** Pipe-delimited (`|`) text split into rows, then regex extracts code, description, and comments
- **Dallas violations unpivot:** 25 column groups stacked into rows using `stack()` SQL expression
- **No-violation inspections included:** Chicago inspections with no violations retained with NULL violation fields for complete pass-rate analysis
- **Surrogate keys via `monotonically_increasing_id()`:** Tables rebuilt on each run with `mode("overwrite")` — keys are internally consistent per run
- **Dallas synthetic inspection IDs:** Generated via `SHA2(restaurant_name + inspection_date)` since Dallas has no native ID

---

## Tools & Technologies

| Tool | Purpose |
|------|---------|
| Databricks (Unity Catalog, Delta Lake) | Data processing, storage, ETL |
| Databricks DQX | Data quality profiling |
| Delta Live Tables (DLT) | SCD Type 2 implementation |
| PySpark / Spark SQL | ETL transformations |
| Power BI Service | BI dashboards and reporting |
| Navicat | ER diagram / dimensional model design |
| Git | Version control |
