-- ============================================================================
-- Food Inspections Dimensional Model - DDL for ER Studio Import
-- DAMG7370 - Designing Advanced Data Architectures for Business Intelligence
-- 
-- Star Schema: fact_inspection_violation + 6 dimension tables
-- Grain: One row per violation per inspection
-- Architecture: Medallion (Bronze > Silver > Gold)
-- ============================================================================

-- ============================================================================
-- DIMENSION: dim_date
-- Standard calendar dimension (generated, not sourced from data)
-- SCD Type 0 (static - loaded once)
-- ============================================================================
CREATE TABLE dim_date (
    date_key            INT             NOT NULL,       -- PK: YYYYMMDD format (e.g., 20260101)
    full_date           DATE            NOT NULL,       -- Full date value
    year                INT             NOT NULL,       -- Calendar year
    quarter             INT             NOT NULL,       -- Quarter (1-4)
    month               INT             NOT NULL,       -- Month (1-12)
    month_name          VARCHAR(20)     NOT NULL,       -- Month name (January, February, etc.)
    day                 INT             NOT NULL,       -- Day of month
    day_of_week         VARCHAR(20)     NOT NULL,       -- Day name (Monday, Tuesday, etc.)
    day_of_week_num     INT             NOT NULL,       -- Day of week number (1=Monday)
    is_weekend          BOOLEAN         NOT NULL,       -- Weekend flag
    fiscal_year         VARCHAR(10)     NULL,           -- Fiscal year label (e.g., FY2017)
    CONSTRAINT pk_dim_date PRIMARY KEY (date_key)
);

-- ============================================================================
-- DIMENSION: dim_establishment
-- Business/restaurant information
-- SCD Type 1 (overwrite on change)
-- Sources: Chicago (dba_name, license, facility_type, risk) 
--          Dallas (restaurant_name - no license/facility/risk available)
-- ============================================================================
CREATE TABLE dim_establishment (
    establishment_key   BIGINT          NOT NULL,       -- PK: surrogate key
    establishment_id    VARCHAR(200)    NOT NULL,       -- NK: license (Chicago) or name|address composite (Dallas)
    source_city         VARCHAR(10)     NOT NULL,       -- Chicago or Dallas
    dba_name            VARCHAR(200)    NOT NULL,       -- Doing Business As name
    aka_name            VARCHAR(200)    NULL,           -- Also Known As (Chicago only)
    license_number      VARCHAR(50)     NULL,           -- License number (Chicago only)
    facility_type       VARCHAR(100)    NULL,           -- Facility type (Chicago only; default 'Restaurant' for Dallas)
    risk_level          VARCHAR(50)     NULL,           -- Risk classification (Chicago only)
    CONSTRAINT pk_dim_establishment PRIMARY KEY (establishment_key)
);

-- ============================================================================
-- DIMENSION: dim_location
-- Geographic/address information
-- SCD Type 1 (overwrite on change)
-- Sources: Chicago (address, city, state, zip, latitude, longitude)
--          Dallas (street_address, zip_code, lat_long_location - parsed)
-- ============================================================================
CREATE TABLE dim_location (
    location_key        BIGINT          NOT NULL,       -- PK: surrogate key
    location_id         VARCHAR(300)    NOT NULL,       -- NK: address|zip composite
    address             VARCHAR(200)    NOT NULL,       -- Street address
    city                VARCHAR(50)     NOT NULL,       -- City (Chicago or Dallas)
    state               VARCHAR(2)      NOT NULL,       -- State (IL or TX)
    zip_code            VARCHAR(5)      NOT NULL,       -- 5-digit zip code
    latitude            DOUBLE          NULL,           -- Latitude coordinate
    longitude           DOUBLE          NULL,           -- Longitude coordinate
    CONSTRAINT pk_dim_location PRIMARY KEY (location_key)
);

-- ============================================================================
-- DIMENSION: dim_violation
-- Standardized violation codes and descriptions from both cities
-- SCD Type 2 (track historical changes to violation descriptions)
-- 
-- NOTE: Dallas and Chicago violation codes do NOT need to match.
-- Both sets are stored in this single dimension, distinguished by source_city.
-- Natural key = (violation_code, source_city)
--
-- Sources: Chicago (parsed from pipe-delimited violations text column)
--          Dallas (violation_description_N, violation_detail_N columns)
-- ============================================================================
CREATE TABLE dim_violation (
    violation_key       BIGINT          NOT NULL,       -- PK: surrogate key
    violation_code      VARCHAR(20)     NOT NULL,       -- NK: violation code number (e.g., '31', '38')
    source_city         VARCHAR(10)     NOT NULL,       -- NK: Chicago or Dallas
    violation_description VARCHAR(500)  NOT NULL,       -- Short violation description
    violation_detail    VARCHAR(2000)   NULL,           -- Full regulatory citation (Dallas) or comments (Chicago)
    violation_severity  VARCHAR(20)     NULL,           -- Derived: Critical / Serious / Minor
    is_current          BOOLEAN         NOT NULL,       -- SCD2: True if current version
    effective_date      DATE            NOT NULL,       -- SCD2: Date this version became effective
    end_date            DATE            NULL,           -- SCD2: Date superseded (NULL if current)
    CONSTRAINT pk_dim_violation PRIMARY KEY (violation_key)
);

-- ============================================================================
-- DIMENSION: dim_inspection_type
-- Inspection type lookup
-- SCD Type 1 (overwrite on change)
-- Sources: Chicago (20+ types: Canvass, License, Complaint, etc.)
--          Dallas (3 types: Routine, Follow-up, Complaint)
-- ============================================================================
CREATE TABLE dim_inspection_type (
    inspection_type_key BIGINT          NOT NULL,       -- PK: surrogate key
    inspection_type     VARCHAR(100)    NOT NULL,       -- NK: inspection type name
    source_city         VARCHAR(10)     NOT NULL,       -- Chicago or Dallas
    inspection_category VARCHAR(50)     NULL,           -- Grouped: Routine, Re-Inspection, Complaint, Other
    CONSTRAINT pk_dim_inspection_type PRIMARY KEY (inspection_type_key)
);

-- ============================================================================
-- DIMENSION: dim_inspection_result
-- Result/score mapping with derived numeric scores
-- SCD Type 1 (overwrite on change)
-- 
-- Chicago provides text results; scores are derived per assignment rules:
--   Pass = 90, Pass w/ Conditions = 80, Fail = 70, No Entry = 0, Others = NULL
-- Dallas provides numeric scores; text results are derived from score ranges.
-- ============================================================================
CREATE TABLE dim_inspection_result (
    result_key          BIGINT          NOT NULL,       -- PK: surrogate key
    result_text         VARCHAR(50)     NOT NULL,       -- NK: text result (Pass, Fail, etc.)
    derived_score       INT             NULL,           -- Derived numeric score
    result_category     VARCHAR(20)     NULL,           -- Grouped: Pass, Fail, Other
    CONSTRAINT pk_dim_inspection_result PRIMARY KEY (result_key)
);

-- ============================================================================
-- FACT TABLE: fact_inspection_violation
-- Grain: One row per violation per inspection
-- 
-- Contains foreign keys to all 6 dimensions plus degenerate dimensions
-- and measures. Both Chicago and Dallas data flows into this single fact table.
--
-- Chicago violations are parsed from the pipe-delimited text column.
-- Dallas violations are unpivoted from 25 wide column groups into rows.
-- ============================================================================
CREATE TABLE fact_inspection_violation (
    inspection_violation_id BIGINT      NOT NULL,       -- PK: surrogate key
    date_key                INT         NOT NULL,       -- FK -> dim_date
    establishment_key       BIGINT      NOT NULL,       -- FK -> dim_establishment
    location_key            BIGINT      NOT NULL,       -- FK -> dim_location
    violation_key           BIGINT      NOT NULL,       -- FK -> dim_violation
    inspection_type_key     BIGINT      NOT NULL,       -- FK -> dim_inspection_type
    result_key              BIGINT      NOT NULL,       -- FK -> dim_inspection_result
    source_city             VARCHAR(10) NOT NULL,       -- DD: Chicago or Dallas
    inspection_id           VARCHAR(50) NULL,           -- DD: original ID (Chicago native; Dallas generated)
    inspection_score        INT         NULL,           -- Measure: numeric score (Dallas actual; Chicago derived)
    violation_points        INT         NULL,           -- Measure: violation points (Dallas 1-3; Chicago NULL)
    violation_slot          INT         NULL,           -- DD: Dallas slot number 1-25 (Chicago NULL)
    CONSTRAINT pk_fact_inspection_violation PRIMARY KEY (inspection_violation_id),
    CONSTRAINT fk_fact_date FOREIGN KEY (date_key) REFERENCES dim_date (date_key),
    CONSTRAINT fk_fact_establishment FOREIGN KEY (establishment_key) REFERENCES dim_establishment (establishment_key),
    CONSTRAINT fk_fact_location FOREIGN KEY (location_key) REFERENCES dim_location (location_key),
    CONSTRAINT fk_fact_violation FOREIGN KEY (violation_key) REFERENCES dim_violation (violation_key),
    CONSTRAINT fk_fact_inspection_type FOREIGN KEY (inspection_type_key) REFERENCES dim_inspection_type (inspection_type_key),
    CONSTRAINT fk_fact_result FOREIGN KEY (result_key) REFERENCES dim_inspection_result (result_key)
);

-- ============================================================================
-- INDEXES for query performance
-- ============================================================================
CREATE INDEX idx_fact_date ON fact_inspection_violation (date_key);
CREATE INDEX idx_fact_establishment ON fact_inspection_violation (establishment_key);
CREATE INDEX idx_fact_location ON fact_inspection_violation (location_key);
CREATE INDEX idx_fact_violation ON fact_inspection_violation (violation_key);
CREATE INDEX idx_fact_inspection_type ON fact_inspection_violation (inspection_type_key);
CREATE INDEX idx_fact_result ON fact_inspection_violation (result_key);
CREATE INDEX idx_fact_source_city ON fact_inspection_violation (source_city);
CREATE INDEX idx_dim_violation_current ON dim_violation (is_current, source_city, violation_code);
CREATE INDEX idx_dim_establishment_nk ON dim_establishment (establishment_id, source_city);
CREATE INDEX idx_dim_location_nk ON dim_location (location_id);
