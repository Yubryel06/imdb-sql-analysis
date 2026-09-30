-- =============================================================================
-- 05_dashboard_views.sql - Step 6: Present
-- Flat, dashboard-ready views. Each one is exported to a CSV by
-- scripts/export_dashboard_csvs.py for use in Tableau Public.
--
-- The views are denormalized on purpose (titles, names, and ratings repeated
-- on every row) so the dashboard tool needs no joins.
-- Requires the views created in 04_analysis.sql.
-- =============================================================================

USE imdb_movies;

-- One row per film
CREATE OR REPLACE VIEW dash_movies AS
SELECT
    mr.movie_id,
    mr.title,
    mr.release_year,
    mr.decade,
    mr.runtime_minutes,
    CASE
        WHEN mr.runtime_minutes IS NULL THEN NULL
        WHEN mr.runtime_minutes < 90  THEN '1. Under 90 min'
        WHEN mr.runtime_minutes < 120 THEN '2. 90-119 min'
        WHEN mr.runtime_minutes < 150 THEN '3. 120-149 min'
        WHEN mr.runtime_minutes < 180 THEN '4. 150-179 min'
        ELSE                               '5. 180+ min'
    END AS runtime_band,
    mr.avg_rating,
    mr.num_votes,
    (SELECT GROUP_CONCAT(g.genre_name ORDER BY g.genre_name SEPARATOR ', ')
       FROM movie_genres mg JOIN genres g ON g.genre_id = mg.genre_id
      WHERE mg.movie_id = mr.movie_id)  AS genres,
    (SELECT GROUP_CONCAT(p.name ORDER BY p.name SEPARATOR ', ')
       FROM movie_credits c JOIN people p ON p.person_id = c.person_id
      WHERE c.movie_id = mr.movie_id AND c.role = 'director') AS directors
FROM v_movie_ratings mr;

-- One row per (film, genre): a film with 3 genres appears 3 times
CREATE OR REPLACE VIEW dash_movie_genres AS
SELECT
    mr.movie_id,
    mr.title,
    mr.release_year,
    mr.decade,
    g.genre_name AS genre,
    mr.avg_rating,
    mr.num_votes
FROM v_movie_ratings mr
JOIN movie_genres mg ON mg.movie_id = mr.movie_id
JOIN genres g        ON g.genre_id  = mg.genre_id;

-- One row per (director, film), numbered in career order
CREATE OR REPLACE VIEW dash_director_films AS
SELECT
    director_id,
    director_name,
    movie_id,
    title,
    release_year,
    avg_rating,
    num_votes,
    ROW_NUMBER() OVER (PARTITION BY director_id ORDER BY release_year, movie_id) AS career_film_number,
    COUNT(*)     OVER (PARTITION BY director_id)                                 AS career_films
FROM v_director_films;

-- One row per actor-director pair with 5+ films together
CREATE OR REPLACE VIEW dash_actor_director_pairs AS
SELECT
    actor.name                   AS actor_name,
    director.name                AS director_name,
    COUNT(*)                     AS films_together,
    ROUND(AVG(mr.avg_rating), 2) AS avg_rating_together
FROM movie_credits a
JOIN movie_credits d
  ON  d.movie_id  = a.movie_id
  AND d.role      = 'director'
  AND d.person_id <> a.person_id
JOIN people actor       ON actor.person_id    = a.person_id
JOIN people director    ON director.person_id = d.person_id
JOIN v_movie_ratings mr ON mr.movie_id        = a.movie_id
WHERE a.role IN ('actor', 'actress')
GROUP BY a.person_id, actor.name, d.person_id, director.name
HAVING COUNT(*) >= 5;
