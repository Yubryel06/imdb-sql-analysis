-- =============================================================================
-- 03_cleaning.sql - Step 4: Clean
-- Converts the raw staging tables into the clean, typed, final tables.
--
-- Every data problem found is counted in the cleaning_log table before it is
-- fixed, so the effect of each cleaning rule is documented and reproducible.
--
-- Note on '\\N': IMDb writes missing values as the two characters \N.
-- In a MySQL string a backslash must be doubled, so '\\N' means exactly \N.
--
-- Safe to re-run: empties and refills the final tables.
-- =============================================================================

USE imdb_movies;

-- -----------------------------------------------------------------------------
-- 0. Reset final tables (children first, because of foreign keys) and the log
-- -----------------------------------------------------------------------------
DELETE FROM credit_characters;
DELETE FROM movie_credits;
DELETE FROM movie_genres;
DELETE FROM ratings;
DELETE FROM genres;
DELETE FROM people;
DELETE FROM movies;
ALTER TABLE genres        AUTO_INCREMENT = 1;
ALTER TABLE movie_credits AUTO_INCREMENT = 1;

DROP TABLE IF EXISTS cleaning_log;
CREATE TABLE cleaning_log (
    log_id         INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    table_name     VARCHAR(30)  NOT NULL,
    issue          VARCHAR(100) NOT NULL,
    rows_affected  INT UNSIGNED NOT NULL,
    action_taken   VARCHAR(150) NOT NULL
);


-- -----------------------------------------------------------------------------
-- 1. MOVIES: convert year/runtime text to numbers, \N to NULL
-- -----------------------------------------------------------------------------
INSERT INTO cleaning_log (table_name, issue, rows_affected, action_taken)
SELECT 'movies', 'Missing release year', COUNT(*), 'Film dropped (year is required for analysis)'
FROM stg_title_basics WHERE startYear = '\\N';

INSERT INTO cleaning_log (table_name, issue, rows_affected, action_taken)
SELECT 'movies', 'Missing runtime', COUNT(*), 'Film kept; runtime set to NULL'
FROM stg_title_basics WHERE runtimeMinutes = '\\N';

INSERT INTO movies (movie_id, title, original_title, release_year, runtime_minutes)
SELECT
    tconst,
    primaryTitle,
    originalTitle,
    CAST(startYear AS UNSIGNED),
    CAST(NULLIF(runtimeMinutes, '\\N') AS UNSIGNED)   -- \N -> NULL, then text -> number
FROM stg_title_basics
WHERE startYear <> '\\N';


-- -----------------------------------------------------------------------------
-- 2. RATINGS: convert text to DECIMAL / INT
-- -----------------------------------------------------------------------------
INSERT INTO ratings (movie_id, avg_rating, num_votes)
SELECT
    r.tconst,
    CAST(r.averageRating AS DECIMAL(3,1)),
    CAST(r.numVotes AS UNSIGNED)
FROM stg_title_ratings r
JOIN movies m ON m.movie_id = r.tconst;


-- -----------------------------------------------------------------------------
-- 3. GENRES: split "Action,Comedy,Drama" into one row per genre
--
-- The recursive CTE peels off one genre per pass:
--   pass 1: genre = 'Action', rest = 'Comedy,Drama'
--   pass 2: genre = 'Comedy', rest = 'Drama'
--   pass 3: genre = 'Drama',  rest = NULL  -> stops
-- -----------------------------------------------------------------------------
INSERT INTO cleaning_log (table_name, issue, rows_affected, action_taken)
SELECT 'movie_genres', 'Missing genres', COUNT(*), 'Film kept with no genre rows'
FROM stg_title_basics WHERE genres = '\\N';

DROP TEMPORARY TABLE IF EXISTS tmp_movie_genres;
CREATE TEMPORARY TABLE tmp_movie_genres (
    movie_id    VARCHAR(12) NOT NULL,
    genre_name  VARCHAR(30) NOT NULL
);

INSERT INTO tmp_movie_genres (movie_id, genre_name)
WITH RECURSIVE genre_split AS (
    SELECT
        tconst,
        SUBSTRING_INDEX(genres, ',', 1) AS genre,
        IF(LOCATE(',', genres) > 0, SUBSTRING(genres, LOCATE(',', genres) + 1), NULL) AS rest
    FROM stg_title_basics
    WHERE genres <> '\\N'
    UNION ALL
    SELECT
        tconst,
        SUBSTRING_INDEX(rest, ',', 1),
        IF(LOCATE(',', rest) > 0, SUBSTRING(rest, LOCATE(',', rest) + 1), NULL)
    FROM genre_split
    WHERE rest IS NOT NULL
)
SELECT gs.tconst, gs.genre
FROM genre_split gs
JOIN movies m ON m.movie_id = gs.tconst;

INSERT INTO genres (genre_name)
SELECT DISTINCT genre_name FROM tmp_movie_genres ORDER BY genre_name;

INSERT INTO movie_genres (movie_id, genre_id)
SELECT t.movie_id, g.genre_id
FROM tmp_movie_genres t
JOIN genres g ON g.genre_name = t.genre_name;


-- -----------------------------------------------------------------------------
-- 4. PEOPLE: convert years, then blank out impossible birth/death pairs
-- -----------------------------------------------------------------------------
INSERT INTO people (person_id, name, birth_year, death_year)
SELECT
    nconst,
    primaryName,
    CAST(NULLIF(birthYear, '\\N') AS UNSIGNED),
    CAST(NULLIF(deathYear, '\\N') AS UNSIGNED)
FROM stg_name_basics;

INSERT INTO cleaning_log (table_name, issue, rows_affected, action_taken)
SELECT 'people', 'Death year earlier than birth year', COUNT(*),
       'Person kept; both years set to NULL (cannot tell which is wrong)'
FROM people WHERE death_year < birth_year;

UPDATE people
SET birth_year = NULL, death_year = NULL
WHERE death_year < birth_year;


-- -----------------------------------------------------------------------------
-- 5. CREDITS: combine cast (principals) with directors/writers (crew)
-- -----------------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS tmp_credits;
CREATE TEMPORARY TABLE tmp_credits (
    movie_id        VARCHAR(12)  NOT NULL,
    person_id       VARCHAR(12)  NOT NULL,
    role            VARCHAR(30)  NOT NULL,
    billing_order   TINYINT UNSIGNED NULL,
    character_name  VARCHAR(255) NULL,
    INDEX idx_tmp_credit (movie_id, person_id, role)
);

-- 5a. Cast and crew from principals. Characters arrive as JSON, e.g. ["Kate Kelly"];
--     each row holds exactly one character, so the first array element is extracted.
INSERT INTO tmp_credits (movie_id, person_id, role, billing_order, character_name)
SELECT
    tconst,
    nconst,
    category,
    CAST(ordering AS UNSIGNED),
    IF(characters = '\\N', NULL, JSON_UNQUOTE(JSON_EXTRACT(characters, '$[0]')))
FROM stg_title_principals;

-- 5b. Directors from crew: split the comma-separated person list (same technique as genres)
INSERT INTO tmp_credits (movie_id, person_id, role)
WITH RECURSIVE director_split AS (
    SELECT
        tconst,
        SUBSTRING_INDEX(directors, ',', 1) AS person_id,
        IF(LOCATE(',', directors) > 0, SUBSTRING(directors, LOCATE(',', directors) + 1), NULL) AS rest
    FROM stg_title_crew
    WHERE directors <> '\\N'
    UNION ALL
    SELECT
        tconst,
        SUBSTRING_INDEX(rest, ',', 1),
        IF(LOCATE(',', rest) > 0, SUBSTRING(rest, LOCATE(',', rest) + 1), NULL)
    FROM director_split
    WHERE rest IS NOT NULL
)
SELECT tconst, person_id, 'director' FROM director_split;

-- 5c. Writers from crew
INSERT INTO tmp_credits (movie_id, person_id, role)
WITH RECURSIVE writer_split AS (
    SELECT
        tconst,
        SUBSTRING_INDEX(writers, ',', 1) AS person_id,
        IF(LOCATE(',', writers) > 0, SUBSTRING(writers, LOCATE(',', writers) + 1), NULL) AS rest
    FROM stg_title_crew
    WHERE writers <> '\\N'
    UNION ALL
    SELECT
        tconst,
        SUBSTRING_INDEX(rest, ',', 1),
        IF(LOCATE(',', rest) > 0, SUBSTRING(rest, LOCATE(',', rest) + 1), NULL)
    FROM writer_split
    WHERE rest IS NOT NULL
)
SELECT tconst, person_id, 'writer' FROM writer_split;

-- 5d. Remove credits for films or people that don't exist (would break foreign keys)
INSERT INTO cleaning_log (table_name, issue, rows_affected, action_taken)
SELECT 'movie_credits', 'Credit refers to a person missing from IMDb name file', COUNT(*), 'Credit dropped'
FROM tmp_credits t
WHERE NOT EXISTS (SELECT 1 FROM people p WHERE p.person_id = t.person_id);

INSERT INTO cleaning_log (table_name, issue, rows_affected, action_taken)
SELECT 'movie_credits', 'Credit refers to a film not in movies', COUNT(*), 'Credit dropped'
FROM tmp_credits t
WHERE NOT EXISTS (SELECT 1 FROM movies m WHERE m.movie_id = t.movie_id);

DELETE t FROM tmp_credits t
LEFT JOIN people p ON p.person_id = t.person_id
LEFT JOIN movies m ON m.movie_id = t.movie_id
WHERE p.person_id IS NULL OR m.movie_id IS NULL;

-- 5e. Merge duplicates: the same person/film/role can appear several times
--     (one row per character played, or a director listed in both principals and crew)
INSERT INTO cleaning_log (table_name, issue, rows_affected, action_taken)
SELECT 'movie_credits', 'Duplicate person/film/role rows', COUNT(*) - COUNT(DISTINCT movie_id, person_id, role),
       'Merged into one credit (earliest billing kept; all characters kept)'
FROM tmp_credits;

INSERT INTO movie_credits (movie_id, person_id, role, billing_order)
SELECT movie_id, person_id, role, MIN(billing_order)
FROM tmp_credits
GROUP BY movie_id, person_id, role;

-- 5f. Characters: one row per character, linked to the merged credit
INSERT INTO credit_characters (credit_id, character_name)
SELECT DISTINCT c.credit_id, t.character_name
FROM tmp_credits t
JOIN movie_credits c
  ON c.movie_id = t.movie_id AND c.person_id = t.person_id AND c.role = t.role
WHERE t.character_name IS NOT NULL;

DROP TEMPORARY TABLE tmp_movie_genres;
DROP TEMPORARY TABLE tmp_credits;


-- -----------------------------------------------------------------------------
-- 6. Summary
-- -----------------------------------------------------------------------------
SELECT table_name, issue, rows_affected, action_taken
FROM cleaning_log
ORDER BY log_id;

SELECT 'movies' AS final_table, COUNT(*) AS row_count FROM movies
UNION ALL SELECT 'ratings',           COUNT(*) FROM ratings
UNION ALL SELECT 'genres',            COUNT(*) FROM genres
UNION ALL SELECT 'movie_genres',      COUNT(*) FROM movie_genres
UNION ALL SELECT 'people',            COUNT(*) FROM people
UNION ALL SELECT 'movie_credits',     COUNT(*) FROM movie_credits
UNION ALL SELECT 'credit_characters', COUNT(*) FROM credit_characters;
