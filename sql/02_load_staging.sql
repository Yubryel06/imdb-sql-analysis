-- =============================================================================
-- 02_load_staging.sql - Step 3: Load
-- Loads the filtered IMDb files into staging tables, exactly as published.
--
-- Staging tables are a raw, untouched copy of the source data:
--   * Every column is text, so nothing is converted or rejected on the way in.
--   * ESCAPED BY '' keeps IMDb's \N placeholders as the literal text '\N'
--     (MySQL would otherwise silently turn them into NULL). Converting them is
--     part of the cleaning step, where it is done explicitly and can be shown.
--   * The final tables (01_schema.sql) are filled from these in 03_cleaning.sql.
--
-- Requirements:
--   * Server: SET GLOBAL local_infile = 1;   (run once as root)
--   * Client: run from the project root with local-infile enabled, e.g.
--       mysql --local-infile=1 -u root -p < sql/02_load_staging.sql
--
-- Safe to re-run: drops and reloads only the stg_ tables.
-- =============================================================================

USE imdb_movies;

DROP TABLE IF EXISTS stg_title_basics;
DROP TABLE IF EXISTS stg_title_ratings;
DROP TABLE IF EXISTS stg_title_crew;
DROP TABLE IF EXISTS stg_title_principals;
DROP TABLE IF EXISTS stg_name_basics;


-- Column names match the IMDb file headers so staging maps 1-to-1 to the source
CREATE TABLE stg_title_basics (
    tconst          VARCHAR(20),
    titleType       VARCHAR(50),
    primaryTitle    VARCHAR(500),
    originalTitle   VARCHAR(500),
    isAdult         VARCHAR(10),
    startYear       VARCHAR(10),
    endYear         VARCHAR(10),
    runtimeMinutes  VARCHAR(10),
    genres          VARCHAR(255)
);

CREATE TABLE stg_title_ratings (
    tconst          VARCHAR(20),
    averageRating   VARCHAR(10),
    numVotes        VARCHAR(20)
);

CREATE TABLE stg_title_crew (
    tconst          VARCHAR(20),
    directors       TEXT,            -- comma-separated nconst list
    writers         TEXT             -- comma-separated nconst list
);

CREATE TABLE stg_title_principals (
    tconst          VARCHAR(20),
    ordering        VARCHAR(10),
    nconst          VARCHAR(20),
    category        VARCHAR(50),
    job             VARCHAR(500),
    characters      TEXT             -- JSON array, e.g. ["Kate Kelly"]
);

CREATE TABLE stg_name_basics (
    nconst             VARCHAR(20),
    primaryName        VARCHAR(500),
    birthYear          VARCHAR(10),
    deathYear          VARCHAR(10),
    primaryProfession  VARCHAR(500),
    knownForTitles     VARCHAR(500)
);


LOAD DATA LOCAL INFILE 'data/filtered/title.basics.tsv'
    INTO TABLE stg_title_basics
    CHARACTER SET utf8mb4
    FIELDS TERMINATED BY '\t' ESCAPED BY ''
    LINES TERMINATED BY '\n'
    IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'data/filtered/title.ratings.tsv'
    INTO TABLE stg_title_ratings
    CHARACTER SET utf8mb4
    FIELDS TERMINATED BY '\t' ESCAPED BY ''
    LINES TERMINATED BY '\n'
    IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'data/filtered/title.crew.tsv'
    INTO TABLE stg_title_crew
    CHARACTER SET utf8mb4
    FIELDS TERMINATED BY '\t' ESCAPED BY ''
    LINES TERMINATED BY '\n'
    IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'data/filtered/title.principals.tsv'
    INTO TABLE stg_title_principals
    CHARACTER SET utf8mb4
    FIELDS TERMINATED BY '\t' ESCAPED BY ''
    LINES TERMINATED BY '\n'
    IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'data/filtered/name.basics.tsv'
    INTO TABLE stg_name_basics
    CHARACTER SET utf8mb4
    FIELDS TERMINATED BY '\t' ESCAPED BY ''
    LINES TERMINATED BY '\n'
    IGNORE 1 LINES;


-- Verification: row counts should match the filtered files (minus header rows)
SELECT 'stg_title_basics'     AS staging_table, COUNT(*) AS row_count FROM stg_title_basics
UNION ALL SELECT 'stg_title_ratings',    COUNT(*) FROM stg_title_ratings
UNION ALL SELECT 'stg_title_crew',       COUNT(*) FROM stg_title_crew
UNION ALL SELECT 'stg_title_principals', COUNT(*) FROM stg_title_principals
UNION ALL SELECT 'stg_name_basics',      COUNT(*) FROM stg_name_basics;
