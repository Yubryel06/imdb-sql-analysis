# Building the Dashboard in Tableau Public

A step-by-step guide to turning the exported CSVs into a published dashboard. No coding needed: everything is drag and drop. Plan on 2–3 hours the first time.

---

## Part 1: Set up (15 minutes)

1. **Create a free account** at [public.tableau.com](https://public.tableau.com) (click **Sign Up**).
2. **Download Tableau Public** (the free desktop app) from the same site: **Create → Download Tableau Public**. Install it and sign in.
   - Tableau Public saves your work **to your online profile**, not to your computer. Everything you publish is public, which is the point: it's your portfolio.
3. **The data files** are in the project's `data/exports/` folder, created by:
   ```
   python scripts/export_dashboard_csvs.py
   ```

| File | One row per | Use it for |
|---|---|---|
| `movies.csv` | Film | Runtime chart, horror trend |
| `movie_genres.csv` | Film + genre (a 3-genre film appears 3 times) | Genre chart |
| `director_films.csv` | Director + film, numbered in career order | Career chart |
| `actor_director_pairs.csv` | Actor–director pair with 5+ films together | Optional extra chart |

---

## Part 2: Connect the data (10 minutes)

1. Open Tableau Public. On the left under **Connect → To a File**, click **Text file** and choose `movies.csv`.
2. Check the preview at the bottom: you should see 49,154 rows with titles and ratings.
3. Add the other files as **separate** data sources (don't join them):
   **Data** menu → **New Data Source** → **Text file** → pick `movie_genres.csv`. Repeat for `director_films.csv`.
4. Click **Sheet 1** at the bottom-left to start building.

> **Two things you'll do constantly:**
> - Tableau **adds up** numbers by default (SUM). For ratings you want the **average**: right-click the green pill → **Measure → Average**.
> - Year columns may be treated as numbers to add up. Right-click the pill → **Dimension**.

To switch between data sources, click the one you want at the top of the **Data** pane on the left.

---

## Part 3: Build 4 charts (about 1.5 hours)

Each chart is its own sheet. Rename a sheet by double-clicking its tab at the bottom. Create a new sheet with the small icon next to the tabs.

### Chart 1: "Which genres rate highest?" (bar chart)
Data source: **movie_genres.csv**

1. Drag **genre** to **Rows**.
2. Drag **avg_rating** to **Columns**, then change it to **Average** (right-click → Measure → Average).
3. Click the **sort descending** button in the toolbar (bars sorted high to low).
4. Remove tiny genres: drag **genre** to **Filters**, and untick **News** and **Talk-Show** (under 100 films each).
5. Show the numbers: drag **avg_rating** onto **Label** in the Marks card, and set it to Average too.

✅ You should see Documentary at the top (~7.19) and Horror at the bottom (~5.25).

### Chart 2: "Do longer movies rate higher?" (bar chart)
Data source: **movies.csv**

1. Drag **runtime_band** to **Columns**.
2. Drag **avg_rating** to **Rows** → Average.
3. Right-click **runtime_band** → **Filter** → untick **Null** (the 58 films with no runtime).
4. Drag **avg_rating** onto **Label** → Average.

✅ Bars should rise from ~5.83 (Under 90 min) to ~7.21 (180+ min).

### Chart 3: "Do directors get better with experience?" (line chart)
Data source: **director_films.csv**

1. Drag **career_films** to **Filters** → **Range of values** → set the minimum to **10**. (Only directors with 10+ films, so every point compares the same people.)
2. Drag **career_film_number** to **Filters** → set the range **1 to 10**.
3. Drag **career_film_number** to **Columns** → right-click → **Dimension**.
4. Drag **avg_rating** to **Rows** → Average. It becomes a line automatically.
5. If the line looks flat, right-click the vertical axis → **Edit Axis** → untick **Include zero**.

✅ The line should peak around film 2–3 (~6.71) and slope down to ~6.37 by film 10.

### Chart 4: "Horror vs all films since 2000" (line chart with two colors)
Data source: **movies.csv**

1. Create a field that marks horror films: **Analysis** menu → **Create Calculated Field**. Name it `Is Horror` and type:
   ```
   IF CONTAINS([genres], "Horror") THEN "Horror" ELSE "All other films" END
   ```
   Click **OK**.
2. Drag **release_year** to **Columns** → right-click → **Dimension**.
3. Drag **release_year** to **Filters** → range **2000 to 2025**.
4. Drag **avg_rating** to **Rows** → Average.
5. Drag **Is Horror** onto **Color** in the Marks card.
6. Untick **Include zero** on the vertical axis as in Chart 3.

✅ Two lines: horror stays about 1 point below other films, dips after 2010, and rises again from 2023.

---

## Part 4: Combine them into a dashboard (30 minutes)

1. Click the **New Dashboard** icon at the bottom (the second icon next to the sheet tabs).
2. On the left, set **Size** to **Automatic**, or **Fixed: 1200 × 900** for a predictable layout.
3. Drag your 4 sheets from the left into a 2 × 2 grid.
4. Add a title: tick **Show dashboard title** at the bottom-left, then double-click it and write something like: **What Makes a Great Movie? 49,154 films analyzed**.
5. Add a **Text** object (drag it from **Objects** at the bottom-left) along the bottom with the source line, which IMDb requires:
   > Information courtesy of IMDb (https://www.imdb.com). Used with permission. Films with 1,000+ votes.
6. Give each chart a clear title that states the finding, not just the topic. For example, "Documentaries rate highest, horror lowest" is better than "Genre Ratings".

---

## Part 5: Publish and link it (10 minutes)

1. **File → Save to Tableau Public As…** and name it `What Makes a Great Movie`.
2. It opens in your browser. Copy the URL.
3. Add the link to the README's **Dashboard** section.
4. Add the link to your resume and LinkedIn next to the GitHub link.

---

## Stuck?

| Problem | Fix |
|---|---|
| Numbers look huge (like 300,000) | The pill is on SUM; change it to **Average** |
| Years show as one bar or a big sum | Right-click the year pill → **Dimension** |
| Line looks flat | Right-click the axis → **Edit Axis** → untick **Include zero** |
| Accented names look garbled | Re-open the CSV: **Data Source** tab → click the file → set **Character Set** to **UTF-8** |
| Everything went wrong | Undo is **Ctrl+Z**, and you can always delete a sheet and start it over |

**Stretch idea** once the 4 charts work: a table from `actor_director_pairs.csv` showing the top 10 pairs by `films_together`.
