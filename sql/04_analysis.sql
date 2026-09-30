-- =============================================================================
-- 04_analysis.sql - Step 5: Analyze
-- Answers the project's business questions on the cleaned imdb_movies tables.
--
-- Scope reminder: non-adult feature films with 1,000+ IMDb votes (49,154 films).
-- "Rating" means IMDb's average user rating (1-10) for a film.
--
-- Sections
--   0. Reusable views
--   1. Which genres rate highest, and has that changed across decades?
--   2. Which directors are the most consistently well rated?
--   3. Do longer movies actually rate higher?
--   4. What are the top 3 films of each decade?
--   5. Which actor-director pairings work together most, and how do they rate?
--   6. How do directors' ratings change over their careers?
--   7. How have horror ratings changed since 2010?
-- =============================================================================

USE imdb_movies;


-- =============================================================================
-- 0. Reusable views
--    A view is a saved query. These hide repeated joins so each analysis query
--    can focus on the question instead of the plumbing.
-- =============================================================================

-- One row per film with its rating and decade
CREATE OR REPLACE VIEW v_movie_ratings AS
SELECT
    m.movie_id,
    m.title,
    m.release_year,
    FLOOR(m.release_year / 10) * 10 AS decade,   -- 1994 -> 1990
    m.runtime_minutes,
    r.avg_rating,
    r.num_votes
FROM movies m
JOIN ratings r ON r.movie_id = m.movie_id;

-- One row per (director, film)
CREATE OR REPLACE VIEW v_director_films AS
SELECT
    p.person_id AS director_id,
    p.name      AS director_name,
    mr.*
FROM movie_credits c
JOIN people p           ON p.person_id = c.person_id
JOIN v_movie_ratings mr ON mr.movie_id = c.movie_id
WHERE c.role = 'director';


-- =============================================================================
-- 1. GENRES
-- =============================================================================

-- 1a. Overall: film count and average rating per genre
--     (a film with 3 genres counts once in each)
SELECT
    g.genre_name,
    COUNT(*)                     AS films,
    ROUND(AVG(mr.avg_rating), 2) AS avg_rating,
    RANK() OVER (ORDER BY AVG(mr.avg_rating) DESC) AS rating_rank
FROM movie_genres mg
JOIN genres g           ON g.genre_id = mg.genre_id
JOIN v_movie_ratings mr ON mr.movie_id = mg.movie_id
GROUP BY g.genre_name
HAVING COUNT(*) >= 100          -- skip genres too small to compare (e.g. Talk-Show)
ORDER BY rating_rank;

-- 1b. Top 3 genres by average rating in each decade (min 30 films per genre-decade)
WITH genre_decade AS (
    SELECT
        mr.decade,
        g.genre_name,
        COUNT(*)        AS films,
        AVG(mr.avg_rating) AS avg_rating
    FROM movie_genres mg
    JOIN genres g           ON g.genre_id = mg.genre_id
    JOIN v_movie_ratings mr ON mr.movie_id = mg.movie_id
    GROUP BY mr.decade, g.genre_name
    HAVING COUNT(*) >= 30
),
ranked AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY decade ORDER BY avg_rating DESC) AS rank_in_decade
    FROM genre_decade
)
SELECT decade, rank_in_decade, genre_name, films, ROUND(avg_rating, 2) AS avg_rating
FROM ranked
WHERE rank_in_decade <= 3
ORDER BY decade, rank_in_decade;


-- =============================================================================
-- 2. DIRECTORS: highest and most consistent ratings (min 5 films)
--    Consistency is shown by the standard deviation (low = consistent)
--    and by the director's lowest-rated film.
--    Only films with 25,000+ votes count: without this, the top of the list is
--    directors whose films have ~1,000-5,000 votes from small, devoted fan bases.
-- =============================================================================
SELECT
    director_name,
    COUNT(*)                            AS films,
    ROUND(AVG(avg_rating), 2)           AS avg_rating,
    ROUND(STDDEV_SAMP(avg_rating), 2)   AS rating_std_dev,
    MIN(avg_rating)                     AS worst_film_rating,
    MAX(avg_rating)                     AS best_film_rating
FROM v_director_films
WHERE num_votes >= 25000
GROUP BY director_id, director_name
HAVING COUNT(*) >= 5
ORDER BY avg_rating DESC, rating_std_dev
LIMIT 15;


-- =============================================================================
-- 3. RUNTIME vs RATING
-- =============================================================================

-- 3a. Average rating by runtime band
SELECT
    CASE
        WHEN runtime_minutes < 90  THEN '1. Under 90 min'
        WHEN runtime_minutes < 120 THEN '2. 90-119 min'
        WHEN runtime_minutes < 150 THEN '3. 120-149 min'
        WHEN runtime_minutes < 180 THEN '4. 150-179 min'
        ELSE                            '5. 180+ min'
    END                          AS runtime_band,
    COUNT(*)                     AS films,
    ROUND(AVG(avg_rating), 2)    AS avg_rating,
    ROUND(AVG(num_votes))        AS avg_votes
FROM v_movie_ratings
WHERE runtime_minutes IS NOT NULL
GROUP BY runtime_band
ORDER BY runtime_band;

-- 3b. Pearson correlation between runtime and rating (-1 to 1; 0 = no relationship)
--     Calculated from sums, because MySQL has no built-in CORR() function.
SELECT
    COUNT(*) AS films,
    ROUND(
        (COUNT(*) * SUM(runtime_minutes * avg_rating) - SUM(runtime_minutes) * SUM(avg_rating))
        / SQRT(
            (COUNT(*) * SUM(runtime_minutes * runtime_minutes) - POW(SUM(runtime_minutes), 2))
          * (COUNT(*) * SUM(avg_rating * avg_rating)           - POW(SUM(avg_rating), 2))
        ), 3) AS runtime_rating_correlation
FROM v_movie_ratings
WHERE runtime_minutes IS NOT NULL;


-- =============================================================================
-- 4. TOP 3 FILMS OF EACH DECADE
--    Minimum 25,000 votes so a handful of fans can't push an obscure film to #1.
--    Ties on rating are broken by number of votes.
-- =============================================================================
WITH ranked AS (
    SELECT
        decade,
        title,
        release_year,
        avg_rating,
        num_votes,
        ROW_NUMBER() OVER (PARTITION BY decade ORDER BY avg_rating DESC, num_votes DESC) AS rank_in_decade
    FROM v_movie_ratings
    WHERE num_votes >= 25000
)
SELECT decade, rank_in_decade, title, release_year, avg_rating, num_votes
FROM ranked
WHERE rank_in_decade <= 3
ORDER BY decade, rank_in_decade;


-- =============================================================================
-- 5. ACTOR-DIRECTOR PAIRINGS (most films together, min 5)
--    Self-join: the same movie_credits table is used once for the actor and
--    once for the director, matched on the film.
-- =============================================================================
SELECT
    actor.name                  AS actor_name,
    director.name               AS director_name,
    COUNT(*)                    AS films_together,
    ROUND(AVG(mr.avg_rating), 2) AS avg_rating_together
FROM movie_credits a
JOIN movie_credits d
  ON  d.movie_id  = a.movie_id
  AND d.role      = 'director'
  AND d.person_id <> a.person_id          -- exclude actors directing themselves
JOIN people actor       ON actor.person_id    = a.person_id
JOIN people director    ON director.person_id = d.person_id
JOIN v_movie_ratings mr ON mr.movie_id        = a.movie_id
WHERE a.role IN ('actor', 'actress')
GROUP BY a.person_id, actor.name, d.person_id, director.name
HAVING COUNT(*) >= 5
ORDER BY films_together DESC, avg_rating_together DESC
LIMIT 15;


-- =============================================================================
-- 6. DIRECTOR CAREERS
-- =============================================================================

-- 6a. Do directors improve with experience?
--     Number each director's films in release order (film #1, #2, ...), then
--     average the rating for each career position. Only directors with 10+ films,
--     so every position 1-10 is measured on the same group of people.
WITH career AS (
    SELECT
        director_id,
        avg_rating,
        ROW_NUMBER() OVER (PARTITION BY director_id ORDER BY release_year, movie_id) AS film_number,
        COUNT(*)     OVER (PARTITION BY director_id)                                 AS career_films
    FROM v_director_films
)
SELECT
    film_number,
    COUNT(*)                  AS directors,
    ROUND(AVG(avg_rating), 2) AS avg_rating
FROM career
WHERE career_films >= 10 AND film_number <= 10
GROUP BY film_number
ORDER BY film_number;

-- 6b. Biggest career improvements and declines: average of a director's last 3
--     films minus their first 3 (directors with 8+ films, so the two groups don't overlap)
WITH career AS (
    SELECT
        director_id,
        director_name,
        avg_rating,
        ROW_NUMBER() OVER (PARTITION BY director_id ORDER BY release_year, movie_id)           AS from_start,
        ROW_NUMBER() OVER (PARTITION BY director_id ORDER BY release_year DESC, movie_id DESC) AS from_end,
        COUNT(*)     OVER (PARTITION BY director_id)                                           AS career_films
    FROM v_director_films
),
first_last AS (
    SELECT
        director_name,
        career_films,
        AVG(CASE WHEN from_start <= 3 THEN avg_rating END) AS first_3_avg,
        AVG(CASE WHEN from_end   <= 3 THEN avg_rating END) AS last_3_avg
    FROM career
    WHERE career_films >= 8
    GROUP BY director_id, director_name, career_films
)
(SELECT 'Most improved' AS direction, director_name, career_films,
        ROUND(first_3_avg, 2) AS first_3_avg, ROUND(last_3_avg, 2) AS last_3_avg,
        ROUND(last_3_avg - first_3_avg, 2) AS change_in_rating
 FROM first_last ORDER BY change_in_rating DESC LIMIT 5)
UNION ALL
(SELECT 'Biggest decline', director_name, career_films,
        ROUND(first_3_avg, 2), ROUND(last_3_avg, 2),
        ROUND(last_3_avg - first_3_avg, 2)
 FROM first_last ORDER BY last_3_avg - first_3_avg ASC LIMIT 5);

-- 6c. Film-by-film example with LAG(): Christopher Nolan's career
--     LAG() looks at the previous row, so each film is compared to the one before it.
SELECT
    release_year,
    title,
    avg_rating,
    LAG(avg_rating) OVER (ORDER BY release_year, movie_id)              AS previous_film_rating,
    avg_rating - LAG(avg_rating) OVER (ORDER BY release_year, movie_id) AS change_from_previous
FROM v_director_films
WHERE director_id = 'nm0634240'   -- Christopher Nolan
ORDER BY release_year, movie_id;


-- =============================================================================
-- 7. HORROR SINCE 2010
--    Compares horror to all films in the same period, because ratings overall
--    can drift over time. 2026 is excluded as an incomplete year.
-- =============================================================================

-- 7a. Horror vs all films, before and after 2010
WITH horror AS (
    SELECT mg.movie_id
    FROM movie_genres mg
    JOIN genres g ON g.genre_id = mg.genre_id
    WHERE g.genre_name = 'Horror'
)
SELECT
    CASE WHEN mr.release_year < 2010 THEN '1. Before 2010' ELSE '2. 2010-2025' END AS period,
    COUNT(h.movie_id)                                         AS horror_films,
    ROUND(COUNT(h.movie_id) * 100.0 / COUNT(*), 1)            AS horror_share_pct,
    ROUND(AVG(CASE WHEN h.movie_id IS NOT NULL THEN mr.avg_rating END), 2) AS horror_avg_rating,
    ROUND(AVG(mr.avg_rating), 2)                              AS all_films_avg_rating,
    ROUND(AVG(CASE WHEN h.movie_id IS NOT NULL THEN mr.avg_rating END)
          - AVG(mr.avg_rating), 2)                            AS horror_gap
FROM v_movie_ratings mr
LEFT JOIN horror h ON h.movie_id = mr.movie_id
WHERE mr.release_year <= 2025
GROUP BY period
ORDER BY period;

-- 7b. Year by year since 2000: horror output and rating vs all films
WITH horror AS (
    SELECT mg.movie_id
    FROM movie_genres mg
    JOIN genres g ON g.genre_id = mg.genre_id
    WHERE g.genre_name = 'Horror'
)
SELECT
    mr.release_year,
    COUNT(h.movie_id)                                                      AS horror_films,
    ROUND(AVG(CASE WHEN h.movie_id IS NOT NULL THEN mr.avg_rating END), 2) AS horror_avg_rating,
    ROUND(AVG(mr.avg_rating), 2)                                           AS all_films_avg_rating
FROM v_movie_ratings mr
LEFT JOIN horror h ON h.movie_id = mr.movie_id
WHERE mr.release_year BETWEEN 2000 AND 2025
GROUP BY mr.release_year
ORDER BY mr.release_year;

-- 7c. Highest-rated horror films since 2010 (min 25,000 votes)
SELECT mr.title, mr.release_year, mr.avg_rating, mr.num_votes
FROM v_movie_ratings mr
JOIN movie_genres mg ON mg.movie_id = mr.movie_id
JOIN genres g        ON g.genre_id  = mg.genre_id
WHERE g.genre_name = 'Horror'
  AND mr.release_year BETWEEN 2010 AND 2025
  AND mr.num_votes >= 25000
ORDER BY mr.avg_rating DESC, mr.num_votes DESC
LIMIT 10;
