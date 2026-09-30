# What Makes a Great Movie? An IMDb Film Analysis in SQL

An end-to-end data analytics project on **49,154 feature films** from IMDb's public data. The raw data is extracted with Python, modeled into a normalized MySQL database, cleaned in SQL, and analyzed with CTEs and window functions to find out what separates highly rated films from the rest.

**Skills demonstrated:** relational database design · data cleaning · ETL pipeline · advanced SQL (CTEs, recursive CTEs, window functions, self-joins, views) · Python · data visualization

---

## Key Findings

"Rating" is IMDb's average user rating (1–10). All queries are in [`sql/04_analysis.sql`](sql/04_analysis.sql).

**1. Genre matters more than almost anything else.** Documentaries (7.19), biographies (6.90), and film-noir (6.85) rate highest; horror (5.25) and sci-fi (5.44) rate lowest, nearly 2 points below documentaries. Documentaries have been the top-rated genre in every decade since the 1970s.

**2. The most consistent directors are the classics.** Among directors with 5+ widely seen films (25,000+ votes each), Charles Chaplin leads (8.30 average, never below 8.1), followed by Sergio Leone, Lee Unkrich, and Christopher Nolan. Andrei Tarkovsky is the most consistent of all: all 7 of his films rate between 7.8 and 8.0.

**3. Longer films rate higher, but runtime alone explains little.** Ratings rise steadily from 5.83 (under 90 min) to 7.21 (3+ hours), but the correlation is only 0.26. Films over 3 hours also average 67,000 votes versus 10,000 for films under 90 minutes, which suggests prestige dramas and epics are made long, rather than length itself making films better.

**4. The best film of each decade** (25,000+ votes): *Modern Times* (1930s), *It's a Wonderful Life* (1940s), *12 Angry Men* (1950s), *The Good, the Bad and the Ugly* (1960s), *The Godfather* (1970s), *The Empire Strikes Back* (1980s), *The Shawshank Redemption* (1990s, 9.3, highest overall), *The Dark Knight* (2000s), and *Inception* (2010s).

**5. The most frequent partnerships are franchises and auteur "families".** Kemal Sunal and Kartal Tibet made 26 Turkish comedies together; director Gerald Thomas and his *Carry On* regulars account for 5 of the top 10 pairs. The highest-rated frequent pairs are Japanese masters and their actors: Toshirō Mifune with Akira Kurosawa (16 films, 7.81) and Chishū Ryū with Yasujirō Ozu (20 films, 7.66).

**6. Directors peak early.** For the 803 directors with 10+ films, ratings peak at their 2nd–3rd film (6.71) and fall steadily to 6.37 by their 10th. Part of this is an era effect, since later films are more recent and recent films rate lower overall. Bob Clark shows the extreme: he went from *Black Christmas* (7.1) and *A Christmas Story* (7.9) to *Superbabies: Baby Geniuses 2* (1.5); his first 3 films averaged 6.30, his last 3 averaged 2.40.

**7. Horror boomed in volume, not quality, but is recovering.** Horror output rose from 51 films in 2000 to 269 in 2022, and its share of all films grew from 12.6% (before 2010) to 14.5% (2010–2025). Its rating gap to the average film widened from −0.90 before 2010 to −1.03 after. Since 2023 it has recovered: 2025 horror averaged 5.40, its best year since 2003. The top recent horror films are *Tumbbad* (8.2), *Get Out* (7.8), and *Obsession* (7.8).

### Limitations

- **Fan voting:** films with few votes can be rated very high by small, devoted fan bases. The 25,000-vote minimum used in findings 2 and 4 reduces this effect.
- **Recency:** recent films have had less time to collect votes, and their ratings often settle over time; 2026 is a partial year.
- **Selection:** only films with 1,000+ votes are included, which favors well-known films, especially for older decades and niche genres like documentaries.

---

## Dashboard

**[View the interactive dashboard on Tableau Public](https://public.tableau.com/app/profile/yubryel.castillo/viz/WhatMakesaGreatMovie/WhatMakesaGreatMovie)**

Four of the findings on one page: average rating by genre (genres with 2,000+ films), by runtime, by a director's film number (directors with 10+ films), and horror vs all other films by year since 2000.

---

## Data

**Source:** [IMDb Non-Commercial Datasets](https://data.imdb.com/non-commercial-datasets/)

| File | Contents |
|---|---|
| `title.basics` | Title, type, year, runtime, genres |
| `title.ratings` | Average rating and number of votes |
| `title.crew` | Directors and writers per title |
| `title.principals` | Main cast and crew per title |
| `name.basics` | People: name, birth/death year, profession |

**Scope:** Non-adult feature films with at least 1,000 votes (49,154 of IMDb's 12.8 million titles). This removes TV episodes, shorts, and obscure titles with too few ratings to be reliable.

IMDb data is licensed for personal, non-commercial use and is **not included in this repository**. The download script rebuilds it locally (see [How to Run](#how-to-run)).

*Information courtesy of IMDb (https://www.imdb.com). Used with permission.*

---

## Database Design

The raw IMDb files pack several values into one field (for example, genres as `"Action,Comedy,Drama"`). These are split into related tables:

```
movies            (movie_id, title, original_title, release_year, runtime_minutes)
ratings           (movie_id → movies, avg_rating, num_votes)
genres            (genre_id, genre_name)
movie_genres      (movie_id → movies, genre_id → genres)
people            (person_id, name, birth_year, death_year)
movie_credits     (credit_id, movie_id → movies, person_id → people, role, billing_order)
credit_characters (credit_id → movie_credits, character_name)
```

Foreign keys and CHECK constraints reject bad data at insert time. See the **[ER diagram and design notes](docs/er_diagram.md)**.

---

## Pipeline

| Step | File | What it does |
|---|---|---|
| 1. Extract | [`scripts/download_and_filter.py`](scripts/download_and_filter.py) | Downloads 1.35 GB of IMDb files and streams them down to the rows in scope |
| 2. Design | [`sql/01_schema.sql`](sql/01_schema.sql) | Creates the normalized tables, keys, and constraints |
| 3. Load | [`sql/02_load_staging.sql`](sql/02_load_staging.sql) | Loads the raw data, untouched, into staging tables |
| 4. Clean | [`sql/03_cleaning.sql`](sql/03_cleaning.sql) | Converts types, handles missing values, splits lists, and fills the final tables |
| 5. Analyze | [`sql/04_analysis.sql`](sql/04_analysis.sql) | Answers the seven questions |
| 6. Present | [`sql/05_dashboard_views.sql`](sql/05_dashboard_views.sql), [`scripts/export_dashboard_csvs.py`](scripts/export_dashboard_csvs.py) | Builds dashboard-ready views and exports them to CSV |

### Data cleaning

Every issue is counted in a `cleaning_log` table before it is fixed.

| Issue | Rows | Action |
|---|---|---|
| Missing runtime (`\N`) | 58 | Film kept; runtime set to `NULL` |
| Missing genres (`\N`) | 103 | Film kept with no genre rows |
| Death year earlier than birth year | 8 | Person kept; both years set to `NULL` |
| Credit refers to a person missing from IMDb's name file | 36 | Credit dropped |
| Duplicate person/film/role rows (actor playing several characters; director listed in two files) | 165,223 | Merged into one credit, all characters kept |

Also:
- Converted numbers stored as text (year, runtime, rating, votes) to numeric types
- Split comma-separated genres, directors, and writers into rows with recursive CTEs
- Extracted character names from JSON arrays (`["Andy Dufresne"]` → `Andy Dufresne`)
- Kept real outliers: *Out 1* (1971) at 776 minutes, and historical writers born before 1800

---

## How to Run

**Requirements:** Python 3.10+, MySQL 8.0

1. Clone this repository.
2. Download and filter the data:
   ```
   python scripts/download_and_filter.py
   ```
3. Allow loading local files (once, as root):
   ```sql
   SET GLOBAL local_infile = 1;
   ```
4. From the project root, run the SQL files in order:
   ```
   mysql -u root -p --local-infile=1 --default-character-set=utf8mb4 < sql/01_schema.sql
   mysql -u root -p --local-infile=1 --default-character-set=utf8mb4 < sql/02_load_staging.sql
   mysql -u root -p --local-infile=1 --default-character-set=utf8mb4 < sql/03_cleaning.sql
   mysql -u root -p --local-infile=1 --default-character-set=utf8mb4 < sql/04_analysis.sql
   mysql -u root -p --local-infile=1 --default-character-set=utf8mb4 < sql/05_dashboard_views.sql
   ```
5. Export the dashboard CSVs to `data/exports/`:
   ```
   python scripts/export_dashboard_csvs.py
   ```

---

## Repository Structure

```
├── README.md
├── data/                          # Not tracked in git (IMDb license)
├── docs/
│   ├── er_diagram.md              # Database diagram and design notes
│   └── dashboard_guide.md         # How the Tableau dashboard is built
├── scripts/
│   ├── download_and_filter.py
│   └── export_dashboard_csvs.py
└── sql/
    ├── 01_schema.sql
    ├── 02_load_staging.sql
    ├── 03_cleaning.sql
    ├── 04_analysis.sql
    └── 05_dashboard_views.sql
```

---

## Author

**Yubryel Castillo**, Computer Science student focused on data analytics
[LinkedIn](https://www.linkedin.com/in/yubryel-castillo/) · [GitHub](https://github.com/Yubryel06) · [Tableau Public](https://public.tableau.com/app/profile/yubryel.castillo)
