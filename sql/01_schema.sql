-- =============================================================================
-- 01_schema.sql - Step 2: Design
-- Creates the imdb_movies database and its final, normalized tables.
--
-- Design notes
--   * IMDb's own IDs (tconst 'tt...', nconst 'nm...') are kept as primary keys so
--     every row can be traced back to its source record on IMDb.
--   * Multi-value fields in the raw data (genres "Action,Drama", director lists)
--     become their own rows in linking tables (movie_genres, movie_credits).
--   * Foreign keys and CHECK constraints guard data quality: bad rows are rejected
--     at insert time instead of silently skewing the analysis.
--
-- Safe to re-run: drops and recreates only this project's final tables.
-- =============================================================================

CREATE DATABASE IF NOT EXISTS imdb_movies
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE imdb_movies;

-- Drop in reverse dependency order (child tables before parents)
DROP TABLE IF EXISTS credit_characters;
DROP TABLE IF EXISTS movie_credits;
DROP TABLE IF EXISTS movie_genres;
DROP TABLE IF EXISTS ratings;
DROP TABLE IF EXISTS genres;
DROP TABLE IF EXISTS people;
DROP TABLE IF EXISTS movies;


-- One row per film
CREATE TABLE movies (
    movie_id         VARCHAR(12)       NOT NULL,   -- IMDb tconst, e.g. tt0111161
    title            VARCHAR(255)      NOT NULL,   -- title used on IMDb
    original_title   VARCHAR(255)      NOT NULL,   -- title in original language
    release_year     SMALLINT UNSIGNED NOT NULL,
    runtime_minutes  SMALLINT UNSIGNED NULL,       -- NULL when IMDb has no runtime
    PRIMARY KEY (movie_id),
    INDEX idx_movies_release_year (release_year),
    CONSTRAINT chk_movies_release_year CHECK (release_year BETWEEN 1870 AND 2100),
    CONSTRAINT chk_movies_runtime      CHECK (runtime_minutes > 0)
);


-- One row per film (1-to-1 with movies)
CREATE TABLE ratings (
    movie_id    VARCHAR(12)   NOT NULL,
    avg_rating  DECIMAL(3,1)  NOT NULL,   -- IMDb weighted average, 1.0 to 10.0
    num_votes   INT UNSIGNED  NOT NULL,
    PRIMARY KEY (movie_id),
    CONSTRAINT fk_ratings_movie FOREIGN KEY (movie_id) REFERENCES movies (movie_id),
    CONSTRAINT chk_ratings_avg  CHECK (avg_rating BETWEEN 1.0 AND 10.0)
);


-- Lookup table: one row per genre name
CREATE TABLE genres (
    genre_id    TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
    genre_name  VARCHAR(30)      NOT NULL,
    PRIMARY KEY (genre_id),
    UNIQUE KEY uq_genres_name (genre_name)
);


-- Many-to-many: a film can have several genres, a genre has many films
CREATE TABLE movie_genres (
    movie_id  VARCHAR(12)      NOT NULL,
    genre_id  TINYINT UNSIGNED NOT NULL,
    PRIMARY KEY (movie_id, genre_id),
    INDEX idx_movie_genres_genre (genre_id),   -- speeds up "all films in genre X"
    CONSTRAINT fk_movie_genres_movie FOREIGN KEY (movie_id) REFERENCES movies (movie_id),
    CONSTRAINT fk_movie_genres_genre FOREIGN KEY (genre_id) REFERENCES genres (genre_id)
);


-- One row per person (actors, directors, writers, crew)
CREATE TABLE people (
    person_id   VARCHAR(12)       NOT NULL,   -- IMDb nconst, e.g. nm0000151
    name        VARCHAR(255)      NOT NULL,
    birth_year  SMALLINT UNSIGNED NULL,
    death_year  SMALLINT UNSIGNED NULL,
    PRIMARY KEY (person_id)
);


-- Many-to-many: who worked on which film, and in what role.
-- Directors and writers come from title.crew (complete lists);
-- cast and other crew come from title.principals (top-billed only).
CREATE TABLE movie_credits (
    credit_id       INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    movie_id        VARCHAR(12)      NOT NULL,
    person_id       VARCHAR(12)      NOT NULL,
    role            VARCHAR(30)      NOT NULL,   -- actor, actress, director, writer, producer, ...
    billing_order   TINYINT UNSIGNED NULL,       -- position in IMDb's credits; NULL if not listed
    PRIMARY KEY (credit_id),
    UNIQUE KEY uq_credit (movie_id, person_id, role),   -- no duplicate credits
    INDEX idx_credits_person_role (person_id, role),    -- speeds up "all films by person X"
    CONSTRAINT fk_credits_movie  FOREIGN KEY (movie_id)  REFERENCES movies (movie_id),
    CONSTRAINT fk_credits_person FOREIGN KEY (person_id) REFERENCES people (person_id)
);


-- One-to-many: the character(s) played in an acting credit.
-- Split out because one actor can play several characters in the same film.
CREATE TABLE credit_characters (
    credit_id       INT UNSIGNED  NOT NULL,
    character_name  VARCHAR(255)  NOT NULL,
    PRIMARY KEY (credit_id, character_name),
    CONSTRAINT fk_characters_credit FOREIGN KEY (credit_id) REFERENCES movie_credits (credit_id)
);
