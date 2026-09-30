"""
Step 1 - Extract: download the IMDb datasets and keep only the rows this project needs.

Rows are filtered, not cleaned: every kept row is written exactly as IMDb published it
(including the \\N placeholders), so the cleaning happens later in SQL where it can be shown.

Kept:
  - Feature films (titleType = 'movie'), non-adult, with at least MIN_VOTES votes
  - Ratings, crew, and principal cast/crew rows for those films
  - People who appear in those films' cast or crew

Usage:
  python scripts/download_and_filter.py              # default: 1,000+ votes
  python scripts/download_and_filter.py --min-votes 5000

Information courtesy of IMDb (https://www.imdb.com). Used with permission.
"""

import argparse
import gzip
import time
import urllib.request
from pathlib import Path

BASE_URL = "https://datasets.imdbws.com/"
FILES = [
    "title.basics.tsv.gz",
    "title.ratings.tsv.gz",
    "title.crew.tsv.gz",
    "title.principals.tsv.gz",
    "name.basics.tsv.gz",
]

PROJECT_DIR = Path(__file__).resolve().parent.parent
RAW_DIR = PROJECT_DIR / "data" / "raw"
FILTERED_DIR = PROJECT_DIR / "data" / "filtered"


def download(filename):
    """Download one file into data/raw, skipping it if it is already there."""
    target = RAW_DIR / filename
    if target.exists():
        print(f"  {filename}: already downloaded, skipping")
        return

    partial = target.with_suffix(target.suffix + ".part")
    with urllib.request.urlopen(BASE_URL + filename) as response, open(partial, "wb") as out:
        total = int(response.headers.get("Content-Length", 0))
        done = 0
        next_report = 0
        while chunk := response.read(1024 * 1024):
            out.write(chunk)
            done += len(chunk)
            if total and done / total >= next_report:
                print(f"  {filename}: {done / 1048576:,.0f} / {total / 1048576:,.0f} MB")
                next_report += 0.25
    partial.rename(target)


def filter_file(filename, keep_row):
    """
    Stream a raw .tsv.gz file and write the header plus every row where keep_row(fields)
    is True to data/filtered/<name>.tsv. Returns (rows_read, rows_kept).
    """
    source = RAW_DIR / filename
    target = FILTERED_DIR / filename.removesuffix(".gz")
    rows_read = rows_kept = 0

    with gzip.open(source, "rt", encoding="utf-8", newline="") as src, \
            open(target, "w", encoding="utf-8", newline="") as dst:
        dst.write(next(src))  # header row
        for line in src:
            rows_read += 1
            if keep_row(line.rstrip("\n").split("\t")):
                dst.write(line)
                rows_kept += 1

    print(f"  {target.name}: kept {rows_kept:,} of {rows_read:,} rows")
    return rows_read, rows_kept


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--min-votes", type=int, default=1000, help="minimum IMDb votes for a film to be kept")
    args = parser.parse_args()

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    FILTERED_DIR.mkdir(parents=True, exist_ok=True)
    start = time.time()

    print("Downloading IMDb files...")
    for filename in FILES:
        download(filename)

    print(f"\nFiltering to non-adult feature films with {args.min_votes:,}+ votes...")

    # ratings: tconst, averageRating, numVotes
    well_voted = set()
    with gzip.open(RAW_DIR / "title.ratings.tsv.gz", "rt", encoding="utf-8") as f:
        next(f)
        for line in f:
            tconst, _, votes = line.rstrip("\n").split("\t")
            if int(votes) >= args.min_votes:
                well_voted.add(tconst)

    # basics: tconst, titleType, primaryTitle, originalTitle, isAdult, ...
    movie_ids = set()

    def is_kept_movie(fields):
        if fields[1] == "movie" and fields[4] == "0" and fields[0] in well_voted:
            movie_ids.add(fields[0])
            return True
        return False

    filter_file("title.basics.tsv.gz", is_kept_movie)
    filter_file("title.ratings.tsv.gz", lambda fields: fields[0] in movie_ids)

    # crew: tconst, directors, writers (comma-separated nconst lists)
    person_ids = set()

    def is_kept_crew(fields):
        if fields[0] not in movie_ids:
            return False
        for column in fields[1:3]:
            if column != "\\N":
                person_ids.update(column.split(","))
        return True

    filter_file("title.crew.tsv.gz", is_kept_crew)

    # principals: tconst, ordering, nconst, category, job, characters
    def is_kept_principal(fields):
        if fields[0] not in movie_ids:
            return False
        person_ids.add(fields[2])
        return True

    filter_file("title.principals.tsv.gz", is_kept_principal)

    # name.basics: nconst, primaryName, ...
    filter_file("name.basics.tsv.gz", lambda fields: fields[0] in person_ids)

    print(f"\nDone in {(time.time() - start) / 60:.1f} minutes.")
    print(f"Filtered files are in {FILTERED_DIR}")


if __name__ == "__main__":
    main()
